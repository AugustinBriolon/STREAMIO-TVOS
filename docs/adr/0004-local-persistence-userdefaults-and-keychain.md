# 4. Local persistence: UserDefaults for library, Keychain for addon URLs

Date: 2026-11-09

## Status

Accepted

## Context

The overhaul adds "Ma liste" and watch progress (resume, continue watching, next episode). Before 2.0 the app stored addon URLs in plain `UserDefaults` although they usually embed Debrid API keys, and the README wrongly called this "secure storage". tvOS has no durable Documents directory: only `UserDefaults`, the Keychain, caches (purgeable) and iCloud are durable. Data volume is small (≤ 200 progress entries, a few dozen list items, a handful of URLs).

## Decision

We will store the library (`library.myList.v1`, `library.progress.v1`) as JSON in `UserDefaults`, capping progress history to the 200 most recent entries. We will store addon URLs in the Keychain (`kSecClassGenericPassword`, `AfterFirstUnlock`) behind a `SecretStorage` protocol, and migrate the legacy `user_addon_urls_v2` / `user_addon_url` keys once, deleting them only after the Keychain write succeeds.

## Options considered

### Option A — UserDefaults (library) + Keychain (secrets)
- Pros: no dependency, synchronous, durable on tvOS, secrets protected, trivial to test with a dedicated suite / in-memory storage.
- Cons: whole-blob rewrites on every progress save (acceptable at this size, every 10 s).

### Option B — SwiftData
- Pros: queries, relationships.
- Cons: store would live in Application Support/Caches, which tvOS may purge; heavier setup and migrations for ~200 rows.

### Option C — iCloud key-value store
- Pros: sync across Apple TVs.
- Cons: requires iCloud entitlement and account; 1 MB limit; out of scope for this iteration.

## Consequences

### Positive
- Debrid keys are no longer readable from app preferences backups or exposed by mistake.
- Existing users keep their addons after the update.

### Negative
- No sync between devices.
- If the Keychain write fails, the legacy plaintext copy is kept until the next successful migration.

### Neutral
- Progress entries older than the 200 most recent are dropped.

## References
- https://developer.apple.com/documentation/security/keychain_services
