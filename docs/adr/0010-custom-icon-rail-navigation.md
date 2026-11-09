# 10. Custom icon rail instead of the system sidebar

Date: 2026-11-09

## Status

Accepted. Supersedes the native sidebar part of [ADR-0003](0003-raise-deployment-target-to-tvos-18.md). The "focusable only on request" rule is superseded by [ADR-0011](0011-rail-reachable-by-moving-left.md).

## Context

The owner asked to remove the background behind the navigation icons. The system sidebar of tvOS 26 draws a glass panel behind the list and a disc behind every icon. Four variants were tried on the Apple TV and captured: the `Tab(_:systemImage:)` API, the older `tabItem` labels, `toolbarBackgroundVisibility(.hidden, for: .tabBar)`, and custom monochrome icon labels. All rendered exactly the same: the system exposes no way to remove those backgrounds.

## Decision

We will replace `TabView(.sidebarAdaptable)` with `NavRail`: icons stacked in the left screen margin with no background at all, names sliding in while the rail has focus, a red mark on the selected destination, a soft black gradient behind the names only while expanded.

Behavior, each point found by testing on the device:
- Pages are created on first visit and kept alive (they keep data and scroll), cross-faded with `Theme.Motion.fade`.
- The rail is focusable only when requested. Left enabled it is the left-most focusable view and took the initial focus while the catalog was still loading, and after a selection; `resetFocus` could not take it back. Menu on a page root enables it and focuses it; leaving it, or selecting, disables it again.
- Menu on a page root opens the rail (`opensRailOnExit`), on a pushed screen it goes back, in the rail it leaves the app. A handler at the root swallowed Menu on pushed screens, so the only root-level handler is limited to Search, whose system keyboard cannot carry its own.
- Collapsed names take no width, so a rail item never overlaps a card the focus engine could pick for an up/down move.
- The rail opener is a stable reference object: a closure in the environment re-rendered every page.

## Options considered

### Option A — Custom icon rail (chosen)
- Pros: exactly the requested look; our own motion; no system glass.
- Cons: focus handling is ours (about 150 lines); no left-swipe entry to the rail (Menu opens it).

### Option B — Top text tab bar
- Pros: very Netflix; simple focus model.
- Cons: takes height on every page; not chosen by the owner.

### Option C — Keep the system sidebar
- Pros: no code, native behavior.
- Cons: cannot remove the backgrounds (verified).

## Consequences

### Positive
- No background behind the icons.
- Frame pacing is unchanged by the rail: 5.5 % of frames above 25 ms against 5.9 % without it ([ADR-0009](0009-off-main-image-pipeline-and-cheap-backdrop.md)).

### Negative
- Moving left from the first card does not reach the rail; Menu does.
- Hidden pages stay in memory like they did with `TabView`.

### Neutral
- The Réglages screen starts and stops its LAN server from an `isActive` flag instead of appear/disappear, since hidden pages stay alive.

## References
- [DESIGN.md](../../DESIGN.md)
