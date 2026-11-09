# 8. Custom audio/subtitle panel instead of the system Menu

Date: 2026-11-09

## Status

Accepted

## Context

The player's Audio and Sous-titres buttons were SwiftUI `Menu` views. On the owner's Apple TV HD, clicking Audio often opened nothing. A temporary event log on the device showed:
- GameController reported every clickpad click (`buttonA pressed=true/false`, 16 of 16 clicks);
- clicks on the full-screen video button reached the app every time (`primaryAction` within 15 ms);
- clicks on the focused `Menu` button changed focus (popover opened) only after 2 ignored clicks, then not at all during a burst of 14 clicks;
- automated `XCUIRemote.press(.select)` always opened the menu, so the failure only appears with real short clicks.

Earlier symptoms had the same origin: while the popover was open, focus left our views (`focus == nil`), which also made it hard to keep the controls on screen.

## Decision

We will replace the `Menu` views with two plain `Button`s that open an in-app `TrackPanelView` (Audio and Sous-titres columns of focusable buttons, a checkmark on the active track). The panel keeps focus inside our own views (`PlayerFocus`), disables the video surface while open, closes with Menu, and shows `TrackDisplay.title` names (bitrate and bracketed language removed).

## Options considered

### Option A — Plain buttons and an in-app panel
- Pros: plain `Button` reacted to every click in the same log; focus stays observable; no blur needed; layout and names are ours.
- Cons: about 120 lines of UI and focus code to maintain.

### Option B — Keep `Menu` and tune focus/timers
- Pros: system look.
- Cons: the unreliable opening is inside the system popover; two rounds of focus fixes did not address it.

### Option C — `AVPlayerViewController` transport bar menus
- Pros: native track menus.
- Cons: needs AVPlayer, which cannot play these files (ADR 0007).

## Consequences

### Positive
- Opening the panel works with real clicks, including bursts (verified on device with rapid select presses).
- Menu peels one layer: panel, then controls, then player.

### Negative
- Not the system look; focus behavior inside the panel is our responsibility.

### Neutral
- Panel background is a solid black layer, not a blur material, to spare the Apple TV HD GPU.

## References
- [ADR 0007](0007-libvlc-playback-engine.md)
