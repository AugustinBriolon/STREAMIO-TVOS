# 19. Settings as a sidebar and a detail pane

Date: 2026-11-11

## Status

Accepted

Refines [ADR-0010](0010-custom-icon-rail-navigation.md) for the Settings screen only.

## Context

Settings was one long scrolling page of six stacked cards. The "Remote management" card (QR code and PIN) holds nothing clickable, so the tvOS focus engine skipped it: moving down from "Playback" jumped to "Extensions" and the page scrolled past the PIN, which could then never be read. The same would happen to any future read-only section.

## Decision

We will lay Settings out like the system Settings app: a left column with one button per section and a right pane showing the focused section. The pane follows focus (`focusedSection`), and the entry whose content is showing keeps a quiet highlight while focus is in the pane. Entering the sidebar from the pane lands on the shown section, not on the nearest entry by height. Sections are an enum (`SettingsSection`) so a new one is one case.

## Options considered

### Option A — Sidebar and detail pane (chosen)
- Pros: every section is a focusable entry, so a read-only section cannot be skipped; matches the system Settings app; the long page becomes short panes.
- Cons: two focus areas to keep consistent; one more state (`section`) to maintain.

### Option B — Keep one page and make the read-only block focusable
- Pros: smallest change; it was the first fix applied.
- Cons: a focusable block with no action is a workaround, and the next read-only section needs the same one.

### Option C — Replace the stacked cards by a tab bar at the top
- Pros: fewer focus areas.
- Cons: conflicts with the left icon rail, and a top bar takes vertical space on a 16:9 screen.

## Consequences

### Positive
- The QR code and PIN are reachable by moving onto "Remote management".
- "About" now says libVLC, the real playback engine (it said AVKit).

### Negative
- The behaviour of focus moving between the sidebar and the pane was not exercised on the device; only the bottom of the old layout was seen before the rewrite.

### Neutral
- The local config server still starts only while Settings is the active tab.

## References
- [ADR-0010](0010-custom-icon-rail-navigation.md)
