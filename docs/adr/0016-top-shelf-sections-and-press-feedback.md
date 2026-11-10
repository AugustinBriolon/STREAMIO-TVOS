# 16. Top Shelf with two sections, and click feedback on focused controls

Date: 2026-11-10

## Status

Accepted. Extends [ADR-0015](0015-dynamic-top-shelf-with-app-group.md).

## Context

The owner wants the Top Shelf to behave like other streaming apps: titles being watched, and the titles of "Ma liste". He also asked for a more professional, fluid feel. Three things were measured on the Apple TV rather than assumed:

- **Top Shelf showed only the static image** although the profile had content. A temporary log written by the extension into the group container showed it ran and read the shared defaults, which held no library. The app's data was in an app-local preferences file instead: the screenshot UI-test project kept a stale, unentitled copy of the app in its build products and reinstalled it over the real app on every test run. This is also the precise cause of the data loss recorded in ADR 0014.
- **No control reacted to a click.** Styles used `isFocused ? focusScale : (isPressed ? 0.97 : 1)`; on tvOS only the focused element can be clicked, so the press branch never ran.
- **Frame pacing** on the scripted browsing scenario was 5.5 % of frames above 25 ms before this change.

## Decision

Top Shelf:
- Two sections for the active profile: "Reprendre la lecture" (16:9 stills, progress bar, latest unfinished entry per title) then "Ma liste" (posters), each capped at 10, with titles already being resumed left out of the list. No sections means the static image.
- Selecting an item opens its title page (`stremiotv://details`); the Play button resumes or plays (`stremiotv://resume`, `stremiotv://play`). The home page pushes the title page through its navigation path.
- The app asks the system to reload when the list changes, a playback ends or the profile changes.

Motion:
- `Theme.Motion.scale(focused:pressed:…)` multiplies the focus scale by a 0.96 press dip (0.12 s, strong ease-out) and is used by every button style; Reduce Motion removes scaling.
- Rail names are an overlay animated with opacity and offset; the rail no longer animates a layout width.
- Loaded content fades in (home catalog, episodes and similar titles, the "best stream" overlay) instead of replacing a spinner in one frame.
- Rows are not staggered: rows are created lazily, so a stagger would replay on every scroll.

## Options considered

### Option A — Sections built in the shared pure layer, links as an enum (chosen)
- Pros: the same rule as the in-app row, unit-tested; three explicit link kinds.
- Cons: the home page owns a navigation path for incoming links.

### Option B — One mixed carousel
- Pros: simpler provider.
- Cons: stills and posters mixed in one row; no separation between "in progress" and "saved".

## Consequences

### Positive
- Verified on the Apple TV home screen: both sections render, with the progress bar.
- A frame-by-frame reading of a screen recording shows the focused button shrinking from 85 to 82 px on click before the page opens; before, its size did not change.
- Frame pacing after the change: 4.8 % of frames above 25 ms (5.5 % before), 2.2 % above 50 ms.

### Negative
- Opening a Top Shelf link while a title page is already pushed replaces the navigation path of the home page.
- The link flows (select and Play from the Top Shelf) were not exercised on the device; link parsing and lookup are unit-tested.

### Neutral
- UI-test projects must never contain an app target with the app's bundle identifier, and their build products must not hold a copy of the app.

## References
- [ADR 0014](0014-profiles-with-per-profile-library.md)
