# 24. Free / Pro / Ultra household plans

Date: 2026-11-12

## Status

Accepted

## Context

Loge needs a monetization ladder that keeps Free useful, makes Pro feel cheap next to Ultra, and gates household features (profiles, addons, concurrent sessions, cloud sync) on the Loge account rather than a single Apple TV.

## Decision

Ship three plans with the matrix in `docs/superpowers/specs/2026-11-12-loge-tiers-design.md`.

- **Pools:** `tv` and `browser` sessions are independent; opening past the cap revokes the oldest session of that kind only.
- **Source of truth:** `accounts.plan` on D1; tvOS caches via `AuthService.plan`.
- **Sync:** Free is local-only (`402 plan_required` on sync routes); Pro/Ultra sync as today.
- **StoreKit 2** products: `loge.pro.monthly|yearly`, `loge.ultra.monthly|yearly|lifetime`. tvOS posts the transaction JWS to `POST /api/billing/apple`. Worker decodes the payload (device already verified with Apple); full ASN signature check deferred until App Store Server API keys are configured.
- **Rename devices** on the portal requires Pro+.

## Consequences

### Positive
- Clear upgrade moments (2nd profile, 2nd addon, 2nd TV).
- Kick rules match foyer mental model without coupling phone and Apple TV.

### Negative
- Existing Free accounts with >1 profile or addon keep data but cannot add more until they upgrade or remove extras.
- StoreKit / App Review extras are still required before charging.

## References
- Spec: `docs/superpowers/specs/2026-11-12-loge-tiers-design.md`
- Plan: `docs/superpowers/plans/2026-11-12-loge-tiers.md`
- Migration: `backend/migrations/0002_account_plan.sql`
