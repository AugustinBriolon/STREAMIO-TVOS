# 14. Profiles with a library per profile

Date: 2026-11-10

## Status

Accepted

## Context

The owner asked for profiles (create, edit, delete). The app had one global library (Ma liste and watch progress in `UserDefaults.standard`) and one set of addons. Decisions taken with the owner: a profile holds the library only (addons stay shared, since the Debrid keys belong to the household); the app reopens on the last used profile; a profile is a colored disc with a symbol.

## Decision

- `ProfileStore` keeps the profiles and the active one (always at least one, at most 6, names 1 to 16 characters, unique ignoring case and accents). Deleting a profile also erases its library; deleting the last one is refused.
- `LibraryStore` is bound to one profile: its keys are namespaced by profile id and it can switch profile in place, so the views observing it follow the active profile.
- Storage is the shared App Group defaults (`AppGroup.defaults`), so the Top Shelf extension reads the same data (ADR 0015).
- First run creates "Profil 1" and **copies** the pre-profile list and progress into it. The legacy keys are kept as a backup (see Consequences).
- UI: a "Profils" destination in the rail, named after the active profile, shows "Qui regarde ?"; "Gérer les profils" turns the cards into edit buttons; the editor sets name, color and symbol, and deletes after a confirmation whose default choice is Annuler.

## Options considered

### Option A — Library per profile, addons shared (chosen)
- Pros: one addon setup; each viewer has their own list and "Reprendre".
- Cons: addon changes affect everyone.

### Option B — Everything per profile, addons included
- Pros: full isolation.
- Cons: each profile must be configured again with the same Debrid key.

## Consequences

### Positive
- Each profile has its own Ma liste, progress and Top Shelf.

### Negative
- A first version **moved** the legacy data and then lost it: a build without the App Group replaced the app, which made the system recreate the shared container empty, and the legacy keys had already been deleted. The history on the owner's Apple TV was lost. The migration now only copies. Never install a build lacking the `com.apple.security.application-groups` entitlement over the real app (this includes UI-test hosts).

### Neutral
- Profiles are not password protected.

## References
- [ADR 0004](0004-local-persistence-userdefaults-and-keychain.md)
- [ADR 0015](0015-dynamic-top-shelf-with-app-group.md)
