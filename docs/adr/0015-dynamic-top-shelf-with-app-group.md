# 15. Dynamic Top Shelf through an App Group

Date: 2026-11-10

## Status

Accepted

## Context

ADR 0013 added static Top Shelf images. The owner wanted the Apple TV home screen to offer "Reprendre la lecture" of the active profile. A Top Shelf extension is a separate process: it cannot read the app's `UserDefaults`, so the data must live in an App Group. The development team is a personal team with a wildcard provisioning profile; before building anything this was tested: with the `com.apple.security.application-groups` entitlement, Xcode created a dedicated profile for `com.h6245.vortxtv`, the profile listed `group.com.h6245.vortxtv`, and the app installed on the Apple TV.

## Decision

- A `StremioTVTopShelf` extension (`TVTopShelfContentProvider`, bundle id `com.h6245.vortxtv.topshelf`) returns a sectioned carousel of the active profile's unfinished titles (at most 10, one per title, newest first, landscape images, progress bar). It returns `nil` when there is nothing to resume, so the system shows the static Top Shelf images of ADR 0013.
- The app and the extension share `Sources/Shared` and `Sources/Models` (Foundation-only): `AppGroup`, storage keys, `TopShelfEntry` (pure, unit-tested) and the library models.
- Selecting an item opens `stremiotv://play?id=<movie or episode id>`; the app resumes that entry of the active profile.
- The app tells the system to reload (`TVTopShelfContentProvider.topShelfContentDidChange`) when a playback ends, a title leaves "Reprendre la lecture", or the profile changes. It does not reload on every progress save (every 10 seconds during playback).

## Options considered

### Option A — Extension reading an App Group (chosen)
- Pros: shows the real, per-profile continue-watching list.
- Cons: a second target, entitlements, shared source files.

### Option B — Static images only
- Pros: nothing to maintain.
- Cons: no personal content.

### Option C — Extension fetching trending titles from Cinemeta
- Pros: no shared storage.
- Cons: not personal, extra network use from the extension.

## Consequences

### Positive
- "Reprendre la lecture" on the home screen, following the active profile.

### Negative
- The Top Shelf is only visible when the app sits on the top row of the home screen; it was not checked on the device, which has the app on the bottom row. The mapping and link parsing are unit-tested, and the built app contains the signed extension with the group entitlement.
- Both the app and the extension must always be signed with the App Group (ADR 0014).

### Neutral
- Select and play both resume the entry; there is no separate details action yet.

## References
- https://developer.apple.com/documentation/tvservices/tvtopshelfcontentprovider
