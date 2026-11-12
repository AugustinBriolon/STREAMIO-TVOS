# Loge Free / Pro / Ultra Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Free / Pro / Ultra entitlements on the Loge account: gated profiles, addons, TV/browser session pools, sync, device rename, and StoreKit 2 purchase/restore.

**Architecture:** StoreKit 2 on tvOS reports purchases to the Worker; D1 `accounts.plan` is source of truth; app + portal + API enforce the same limit matrix from `docs/superpowers/specs/2026-11-12-loge-tiers-design.md`.

**Tech Stack:** Swift / StoreKit 2 / tvOS 18, Cloudflare Worker + D1, existing `AuthService` / `ProfileStore` / `AddonStore` / sessions (ADR 0022).

## Global Constraints

- Entitlement is **per Loge account**, not per Apple TV alone.
- Session pools `tv` and `browser` are **independent**; new login kicks oldest in the **same** pool only.
- Free = local-only sync; Pro/Ultra = cloud sync.
- Do not gate playback, browse, BYO, or account deletion.
- Cinemeta hardcoded meta does **not** count toward addon quota.
- Default addon seed ≤ 1 URL on Free.
- Lifetime product only on Ultra.
- French-first paywall copy; no external checkout links on tvOS.
- Prices (EUR): Pro 3,99 / 30 ; Ultra 7,99 / 60 ; lifetime 99 (product ids in spec).

## File map

| File | Responsibility |
|---|---|
| `docs/adr/0024-loge-tiers.md` | ADR for tiers + billing |
| `backend/migrations/0002_account_plan.sql` | `plan`, `plan_expires_at`, `plan_product_id`; sessions `device_kind`, `display_name` |
| `backend/src/index.ts` | Limits, session kick, rename, billing verify, account payload |
| `Sources/Services/Billing/PlanLimits.swift` | Pure limit matrix + helpers |
| `Sources/Services/Billing/EntitlementStore.swift` | StoreKit 2 + sync plan with Worker |
| `Sources/Services/ProfileStore.swift` | Cap `create` by plan |
| `Sources/Services/AddonStore.swift` | Cap `add` + Free-safe seed |
| `Sources/Services/Sync/CloudSyncEngine.swift` | Skip/push sync by plan |
| `Sources/Services/Sync/AuthService.swift` | Expose plan/limits from account |
| `Sources/Features/Settings/SettingsView.swift` | Paywall, restore, plan UI |
| Portal HTML in `backend/src/index.ts` | Rename device, show plan, no IAP sell |
| `Tests/LogeTests/PlanLimitsTests.swift` | Matrix + kick helpers |
| `Tests/LogeTests/AddonStoreTests.swift` | Seed + cap |
| `Tests/LogeTests/ProfileStoreTests.swift` | Cap |

---

### Task 1: Limit matrix (pure Swift)

**Files:** create `Sources/Services/Billing/PlanLimits.swift`; create `Tests/LogeTests/PlanLimitsTests.swift`

- [ ] Write failing tests for Free/Pro/Ultra caps (profiles, addons, tvSessions, browserSessions) and `canAddAddon(currentCount:)`, `canAddProfile(currentCount:)`.
- [ ] Implement `enum LogePlan: String { free, pro, ultra }` + `struct PlanLimits` static table matching the spec.
- [ ] Run `PlanLimitsTests` — pass.
- [ ] Commit: `feat: add Free Pro Ultra limit matrix`

### Task 2: D1 schema + Worker account plan

**Files:** `backend/migrations/0002_account_plan.sql`; `backend/src/index.ts`

- [ ] Migration: `accounts.plan TEXT NOT NULL DEFAULT 'free'`, `plan_expires_at_ms`, `plan_product_id`; `sessions.device_kind TEXT NOT NULL DEFAULT 'tv'`, `sessions.display_name TEXT`.
- [ ] Helper `limitsFor(plan)` mirroring Swift matrix.
- [ ] Extend `GET` account / sync payloads with `{ plan, limits }`.
- [ ] Enforce profile create + addon POST against plan (400 + code `plan_limit`).
- [ ] Apply migration remote; smoke register → plan `free`.
- [ ] Commit: `feat: store account plan and enforce API limits`

### Task 3: Session pools + kick + rename

**Files:** `backend/src/index.ts`; portal devices UI; ADR 0022 follow-up note in new ADR

- [ ] On `openSession` / `issueToken` / web login: set `device_kind` from `X-Client-Kind: tv|browser` (default tv for pairing, browser for portal cookie/JWT).
- [ ] Before insert: if active count for kind ≥ limit, revoke oldest (`ORDER BY last_seen_at_ms ASC`).
- [ ] Tests or scripted curl: Free second TV revokes first; second browser revokes first; browser does not revoke TV.
- [ ] `POST /api/devices/rename` `{ id, displayName }` — Pro+ only; validate length ≤ 32.
- [ ] Portal: editable name field + save; Free shows hint to upgrade.
- [ ] Commit: `feat: kick session pools and allow device rename`

### Task 4: App-side gates (profiles, addons, seed)

**Files:** `ProfileStore.swift`, `AddonStore.swift`, tests, Settings/Profile UI

- [ ] Inject current `LogePlan` (from `AuthService` / `EntitlementStore`; default `.free` when logged out).
- [ ] `ProfileStore.maxProfiles` becomes plan-driven; `canAdd` uses it; UI hides Add card + shows upgrade.
- [ ] `AddonStore.add` returns false / throws limit; Settings + ConfigPortal show upgrade.
- [ ] Change `defaultAddonURLs` to **one** Free-safe URL (public domain **or** OpenSubtitles v3); keep Cinemeta hardcoded only.
- [ ] Update AddonStore/ProfileStore tests.
- [ ] Commit: `feat: gate profiles and addons by plan`

### Task 5: Sync gated by plan

**Files:** `CloudSyncEngine.swift`, tests if any

- [ ] If plan == free: do not pull/push cloud library/addons/profiles (local stays local). Optional: still allow auth device list.
- [ ] Pro/Ultra: existing sync unchanged.
- [ ] Commit: `feat: enable cloud sync for Pro and Ultra only`

### Task 6: StoreKit 2 + billing endpoint

**Files:** `EntitlementStore.swift`; `LogeApp` / Settings; Worker `POST /api/billing/apple`; ASC products (manual or `asc`)

- [ ] Create ASC products: `loge.pro.monthly`, `loge.pro.yearly`, `loge.ultra.monthly`, `loge.ultra.yearly`, `loge.ultra.lifetime`.
- [ ] tvOS: product load, purchase, restore; map product → plan; call Worker with JWS transaction.
- [ ] Worker verifies via App Store Server API (or JWS verify) and updates `accounts.plan`.
- [ ] Settings → Compte: plan badge, compare table, Acheter / Restaurer.
- [ ] Commit: `feat: add StoreKit 2 purchases synced to account plan`

### Task 7: Paywall UX + copy + ADR

**Files:** Settings, soft paywall sheets on blocked add profile / add addon / 2nd TV message; `docs/adr/0024-loge-tiers.md`

- [ ] French copy: Free vs Pro vs Ultra; no scare tactics; BYO disclaimer unchanged.
- [ ] When a TV is kicked, next sync 401 / revoked → existing signed-out welcome path with “Connecté ailleurs”.
- [ ] Write ADR 0024 summarizing tiers, kick pools, StoreKit, out of scope.
- [ ] Commit: `docs: record Free Pro Ultra monetization decisions`

### Task 8: Verification

- [ ] Matrix unit tests green.
- [ ] Manual: Free 1 TV + 1 browser; second TV kicks first; Pro purchase unlocks 2nd TV + 3 profiles + sync.
- [ ] Confirm Free seed ≤ 1 addon; Cinemeta browse still works without counting.
- [ ] Do **not** submit a new App Store binary until products + privacy text for purchase are ready.

---

## Deferred

- App Store Server Notifications v2 webhook (poll/restore enough for v1).
- RevenueCat.
- Raising lifetime to 150 €.
- Ultra-only perks beyond the matrix (priority support, etc.).
