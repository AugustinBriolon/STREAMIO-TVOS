# Loge Free / Pro / Ultra — design

Date: 2026-11-12  
Status: Approved (conversation) — pending implementation

## Goal

Monetize Loge with a **good-better-best** ladder so **Pro feels accessible**, while Ultra captures power users and lifetime buyers. Entitlements apply to the **Loge household account** (all profiles / devices of that account), not a single Apple TV alone.

## Pricing (ASC / StoreKit)

| Product | Price (EUR) | Notes |
|---|---|---|
| Pro monthly | 3,99 € | Entry subscription |
| Pro yearly | 30 € | ~37 % vs 12× monthly |
| Ultra monthly | 7,99 € | Anchor above Pro |
| Ultra yearly | 60 € | |
| Ultra lifetime | 99 € initially (cap 150 € later) | **Ultra only** — never on Pro |

Apple commission 15–30 % is assumed. Cloudflare costs stay negligible; margin funds ASC, domain, support time.

**Family Sharing:** enabled for subscriptions and lifetime.  
**Restore purchases:** required on tvOS Settings + web account page hint.

## Entitlement matrix

| Capability | Free | Pro | Ultra |
|---|---|---|---|
| Profiles | 1 | 3 | 6 |
| User addons (quota) | 1 | 5 | 20 |
| Apple TV sessions (concurrent) | 1 | 2 | 4 |
| Browser / portal sessions (concurrent) | 1 | 1 | 2 |
| Cloud sync (profiles, lists, progress, addons) | local only | yes | yes |
| Rename device on portal | read-only names | yes | yes |
| Playback / browse / BYO / delete account | yes | yes | yes |

### Session kick rules (all tiers)

Two **independent** pools: `tv` and `browser`.

- Signing in a new **tv** session when the pool is full **revokes the oldest** active tv session (or the previous single one on Free).
- Same for **browser**.
- A browser login **never** kicks a TV, and vice versa.

### Addon quota rules

- Quota counts **user-managed** addon base URLs in `AddonStore` / cloud `addons`.
- **Cinemeta metadata** stays hardcoded in `StremioService` and does **not** consume quota.
- Default seed on first launch must fit Free: seed **at most one** user addon (prefer public-domain catalog **or** OpenSubtitles v3 — pick one in implementation). Do not seed three URLs on Free.
- Adding above the tier limit is blocked in app, ConfigPortal, and Worker (`POST /api/account/addons`) with a clear upgrade message.
- Downgrade: existing extras become **read-only / disabled for new fetches** until the user removes enough URLs; do not silently delete.

### Profile quota rules

- Enforce in `ProfileStore.create`, Worker profile create, and web portal.
- Downgrade with too many profiles: keep data; block creating more; require user to delete down to the cap (no silent wipe).

## Architecture

```
tvOS StoreKit 2 ──purchase/restore──► EntitlementStore (local)
        │                                    │
        │ App Store Server Notifications     │ sync entitlement
        ▼                                    ▼
   Worker (D1 accounts.plan + expires_at) ◄── POST /api/billing/apple
        │
        ├── gate profiles / addons / session pools
        └── GET /api/account → { plan, limits, devices[] }
```

- **Source of truth for paywall:** Worker `accounts.plan` ∈ `{ free, pro, ultra }` (+ `plan_expires_at`, `plan_product_id`).
- tvOS may cache a last-known plan for offline UX but **must re-validate** on launch / restore when online.
- Web portal never sells IAP (Apple rule); it only **displays** plan and deep-links to “Gérer l’abonnement sur l’Apple TV”.

### Device model changes (extends ADR 0022)

- Add `device_kind` on `sessions`: `tv` | `browser` (infer from User-Agent / explicit client header).
- Optional `display_name` (user rename) separate from raw `device_name`.
- On `issueToken` / pairing / web login: enforce pool size for that kind; revoke overflow sessions.
- `PATCH /api/devices/:id` (or POST rename) for Pro+ to set `display_name`.

## Out of scope (v1)

- Ads, tip jar, regional pricing experiments.
- Gating Top Shelf, awards shelves, or playback quality.
- Shipping Lumio or any pirate catalog as default.
- RevenueCat (revisit if StoreKit + ASN become painful).

## Success criteria

1. Free user can use one TV + one browser, one profile, one addon, local-only library.
2. Pro purchase on Apple TV unlocks sync + 3 profiles + 5 addons + 2 TVs within minutes (ASN or restore).
3. Second TV on Free kicks the first; second browser kicks the first browser; pools stay independent.
4. Portal can rename devices when plan ≥ Pro.
5. `asc` / App Review: clear non-consumable + auto-renewable products; no external purchase link for digital unlock on tvOS.

## Open implementation details (fixed defaults)

- Ultra lifetime ASC product id: `loge.ultra.lifetime`.
- Pro/Ultra sub group: `loge.pro`, `loge.ultra` with monthly/yearly levels.
- Plan comparison copy in Settings → Compte (French-first).
