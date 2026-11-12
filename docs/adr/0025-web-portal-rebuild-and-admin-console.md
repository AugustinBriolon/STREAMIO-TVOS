# 25. Web portal rebuild and admin console

Date: 2026-11-12

## Status

Accepted

## Context

The account portal (`/`, `/pair`) was a single 2,200-line page that had grown screen by screen. It injected the `?code=` query parameter unescaped into a `<script>` string, which was a reflected XSS on the page that holds the account token. The service also had no way for its operator to look at an account, grant a plan, sign a household out or reset a password without running SQL by hand.

## Decision

- **One design system for every web page.** `backend/src/pages/ui-kit.ts` holds the tokens (mirroring `Theme.swift`), the components, the icons and a small client runtime (toast, `confirmAction`, `api`, `withBusy`). Both pages are built with `renderPage`. Dialogs use the native `<dialog>` (focus trap, Esc, backdrop) and are animated with CSS transitions and `@starting-style`, gated by `prefers-reduced-motion`.
- **Portal rebuilt mobile-first** around five hash-routed sections (Aperçu, Profils, Appareils, Extensions, Compte): a bottom tab bar on phones and a sidebar on wide screens. The pairing code is validated against `LOGE-\d{4}` on the server before it reaches the page.
- **Admin console at `/admin`, backed by `/api/admin/*` (`backend/src/admin.ts`).** The admin is not an account row. It signs in with the `ADMIN_PASSWORD` Worker secret, which is compared in constant time. It receives an 8-hour token with `role: 'admin'` and no session, kept in `sessionStorage`. The account API rejects any token that has a role, and the admin API accepts only that role. With the secret unset, the admin API answers 503.
- **Admin actions:** list and search accounts with totals, view an account's details, set the plan with an optional expiry (recorded as `plan_product_id = 'admin.grant'` so a StoreKit report for another product does not clear it), sign out one or all devices, reset the password (which also signs every device out), and delete the account. Each action writes one `{"audit":"admin",…}` line to Workers Logs.
- **Contract tests** in `backend/test/` run the real Worker against the real `schema.sql` on `node:sqlite` with `node --test`, with no new dependencies.

## Consequences

### Positive
- The admin secret never touches the repository, and admin and account tokens cannot be swapped for each other.
- Both pages share one source for tokens, components and icons.
- The admin's authority boundaries are covered by tests that a refactor cannot silently break.

### Negative
- There is a single shared admin credential, with no per-operator identity and no MFA. Audit lines say what happened, not who did it.
- Admin login is not rate-limited. A long random secret is what protects it.
- Passwords are still hashed with salted SHA-256 (out of scope here). A move to PBKDF2 needs a migration that rehashes on the next sign-in.

## References
- `backend/src/admin.ts`, `backend/src/shared.ts`, `backend/src/pages/ui-kit.ts`
- ADR 0022 (device sessions), ADR 0024 (plans)
