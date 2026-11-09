# 5. PIN-protected local configuration server

Date: 2026-11-09

## Status

Accepted

## Context

Typing long addon URLs with the Siri Remote is painful, so the app serves a web page on port 8080 to paste them from a phone. The pre-2.0 server was open to anyone on the LAN for the whole session, deleted addons via `GET` (CSRF from any web page), injected URLs into HTML unescaped (stored XSS) and displayed full URLs including Debrid API keys. A malicious addon controls which URLs the TV plays.

## Decision

We will keep the LAN server but harden it:
- It listens only while the Réglages screen is visible.
- Access requires a random 4-digit PIN shown on the TV; a correct PIN sets an `HttpOnly; SameSite=Strict` session cookie. The PIN rotates after 5 failed attempts.
- Mutations are `POST` only and require the session; all dynamic output is HTML-escaped; responses send a restrictive `Content-Security-Policy` and `X-Frame-Options: DENY`.
- Addons are displayed as host only; deletion is by index.
- Request parsing is a pure `HTTPRequestParser` (buffers until `Content-Length` is satisfied, 64 KB cap) and routing is a pure `ConfigPortal`, both unit-tested.

## Options considered

### Option A — Hardened LAN server with PIN
- Pros: keeps the convenient phone workflow; closes XSS/CSRF/unauthenticated access; no new dependency.
- Cons: plain HTTP on the LAN (PIN and URLs are not encrypted in transit).

### Option B — Remove the server, type URLs on the TV only
- Pros: no network attack surface.
- Cons: very poor UX for 100+ character URLs.

### Option C — QR code pairing through a cloud relay
- Pros: TLS end to end.
- Cons: requires a backend to operate; out of scope.

## Consequences

### Positive
- A device on the same Wi-Fi can no longer add or remove addons or read Debrid keys without the PIN on screen.

### Negative
- Traffic is unencrypted HTTP; a LAN attacker sniffing traffic during configuration could capture the session or a pasted URL.

### Neutral
- Users must open Réglages on the TV while configuring from their phone.

## References
- https://owasp.org/www-community/SameSite
- https://developer.apple.com/documentation/network/nwlistener
