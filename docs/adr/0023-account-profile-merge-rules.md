# 23. How an Apple TV merges its profiles with the account's

Date: 2026-11-11

## Status

Accepted

Extends [ADR-0014](0014-profiles-with-per-profile-library.md).

## Context

After signing in on a second Apple TV, the account showed two profiles, "Agt" and "Profil 1" (read from the production database), while the owner expected the two profiles of the first Apple TV. Reading the code found four causes:

1. Creating, renaming or deleting a profile did not trigger a sync; only a profile switch, the end of a playback or a "Ma liste" change did. The first Apple TV's second profile never reached the account.
2. Every new Apple TV creates "Profil 1" at first launch and pushed it to the account on sign-in, next to the account's profiles. The "Profil 1" on the account was the second Apple TV's own.
3. A deleted profile came back: the account kept no record of profile deletions, unlike "Ma liste" and progress.
4. A remote profile that failed to decode was skipped without a message.

## Decision

- Any change to the profile list triggers the debounced sync.
- The first-launch profile is marked untouched until it is renamed, another profile is created, or it inherits pre-profile history. On a sync, if it is still untouched and its library is empty, the account's profiles replace it instead of being added next to it, and the app opens "Qui regarde ?". Installs from before this flag treat a lone profile still named "Profil 1" as untouched.
- A deleted profile is recorded with its date on the device and sent to the account, which stores a tombstone (`sync_tombstones`, type `profile`) and deletes its list and progress. The account never recreates a tombstoned profile or its data from a later push, and every device removes it on its next pull. The last profile on a device is never removed.
- A pull no longer re-adds a profile deleted locally whose deletion has not been pushed yet.

## Options considered

### Option A — Replace an untouched default, tombstone deletions (chosen)
- Pros: a new device ends up with exactly the account's profiles; deletions stick across devices; nothing with data is ever replaced.
- Cons: "untouched" is a heuristic; a profile used only for browsing (no list, no progress) and never renamed is replaced.

### Option B — Ask on sign-in whether to keep the device's profiles
- Pros: explicit.
- Cons: a question most people cannot answer, on a TV, during sign-in.

### Option C — Merge by name
- Pros: would fold two "Profil 1" into one.
- Cons: two people can legitimately share a name across households merged into one account, and a rename on one device would split them again.

## Consequences

### Positive
- A profile created on one Apple TV appears on the others within seconds of the change.
- A new Apple TV no longer adds a "Profil 1" to the account.

### Negative
- Existing duplicates are not cleaned: the "Profil 1" already on the account stays until it is deleted once, from the web or an Apple TV.
- The sync engine itself has no automated test (it calls `URLSession.shared` directly); the merge rules are tested on `ProfileStore`.

### Neutral
- A push right after a pull that changed profiles triggers one extra, empty sync.

## References
- [ADR-0014](0014-profiles-with-per-profile-library.md)
- [ADR-0022](0022-revocable-device-sessions.md)
