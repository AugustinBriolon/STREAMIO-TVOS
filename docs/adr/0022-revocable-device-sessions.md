# 22. Revocable device sessions

Date: 2026-11-11

## Status

Accepted

## Context

The account backend (Cloudflare Worker and D1) issued stateless HMAC tokens valid for one year. Nothing recorded which device held a token, so the account could not list its devices, and a lost or sold Apple TV stayed signed in until the token expired. The Apple TV also always called itself "Apple TV" when pairing.

## Decision

We will bind every new token to a row of a `sessions` table (device name, model, creation, last seen, revocation date). The token carries the session id (`sid`). Every authenticated route goes through `authenticate()`, which rejects a token whose session is missing or revoked and records the last-seen time at most every five minutes.

- Sign-in, account creation and pairing open a session named after the device (`UIDevice.current.name`, for example "Séjour", and its model from the hardware identifier). A pairing code now yields one token: it is marked `consumed` when the token is issued.
- `GET /api/devices` lists the open sessions; `POST /api/devices/revoke` and `POST /api/devices/revoke-others` close them; `POST /api/auth/logout` closes the caller's own session.
- The online account page has an "Appareils" tab with these actions. The Apple TV shows the list read-only in Settings.
- When the account answers 401, the Apple TV signs out locally, keeps its profiles and history, and shows the welcome screen saying it was signed out.

Tokens issued before this change carry no session id. They stay valid until they expire, as decided by the owner, and do not appear in the device list.

## Options considered

### Option A — Session table with the id in the token (chosen)
- Pros: one indexed read per request; revocation takes effect on the device's next call; the list shows real device names.
- Cons: one D1 read per authenticated request, and a write every five minutes per active device.

### Option B — Token denylist
- Pros: no read for valid tokens if cached.
- Cons: cannot list devices, which is half of the need.

### Option C — Short-lived tokens with refresh tokens
- Pros: the standard pattern; limits a stolen token's life.
- Cons: a refresh flow in the app and the web page for a household app; more change than the need.

## Consequences

### Positive
- A device can be signed out from the web without touching the others, and it says so on its next launch or sync.
- Signing out on the Apple TV removes it from the account's list.

### Negative
- Legacy tokens cannot be revoked until they expire (up to one year after issue). Rotating `JWT_SECRET` would end them all at once, at the cost of signing every device out.
- `JWT_SECRET` is currently a plain variable in `wrangler.toml`, in a public repository: anyone can sign a token, including a legacy one without a session. Revocation does not protect against that until the secret is moved to `wrangler secret` and rotated.
- Requires the `migrations/0001_device_sessions.sql` migration on the production database before the worker is deployed.

### Neutral
- The Apple TV keeps working against a worker without these routes: the device list stays empty and the extra request fields are ignored.

## References
- `backend/src/index.ts` (`authenticate`, `issueToken`, `/api/devices`)
- `backend/migrations/0001_device_sessions.sql`
