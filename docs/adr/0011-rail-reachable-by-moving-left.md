# 11. Rail reachable by moving left, with a clear selected state

Date: 2026-11-09

## Status

Accepted. Supersedes the "focusable only on request" rule of [ADR-0010](0010-custom-icon-rail-navigation.md).

## Context

After ADR 0010 the owner could not open the rail at all. The rail was disabled unless Menu was pressed on a page, so moving left from a card did nothing (a device test had shown six left presses without effect) and Menu is not the gesture people try first. The native sidebar had opened by moving left. The selected and unselected icons were also hard to tell apart (white at 95 % against white at 50 %, plus a thin red mark).

## Decision

- The rail becomes focusable as soon as a page element has held focus (`railReady`, learned from `UIFocusSystem.didUpdateNotification`) and is switched off only between a selection and the next page focus. It keeps its original problem solved: it cannot take the initial focus while a page is still loading.
- The rail container spans the full screen height as a focus section, so moving left from a card at any height reaches it; the focus engine otherwise only found it from rows level with the six icons.
- Entering the rail from a page lands on the current destination, not on the icon nearest in height. Menu still opens it, and still leaves the app when the rail has focus.
- States are separated by shape, weight and brightness (no boxes): selected = filled symbol, bold name, full white, red mark that grows in; cursor = white and enlarged; others = outline symbol, medium weight, 42 % white.

## Options considered

### Option A — Always-focusable rail gated by "a page has had focus" (chosen)
- Pros: left swipe works from every card; initial focus stays on the page.
- Cons: relies on a UIKit notification; a page with nothing focusable for more than 2 s lets the rail take focus.

### Option B — Keep Menu-only access
- Pros: no focus risk.
- Cons: the owner could not find it.

### Option C — Intercept left moves on pages
- Pros: no always-enabled rail.
- Cons: `onMoveCommand` also fires when focus simply moves to the previous card, so "at the leftmost card" cannot be known.

## Consequences

### Positive
- Left from any card, and Menu, both open the rail; the current page is obvious in both the collapsed and expanded rail.

### Negative
- Pressing down from the last rail icon moves focus to the content below instead of stopping, because the focus engine looks for the next item in that direction.

### Neutral
- Frame pacing was not re-measured for this change (the rail itself measured 5.5 % of frames above 25 ms in ADR 0010).

## References
- [DESIGN.md](../../DESIGN.md)
