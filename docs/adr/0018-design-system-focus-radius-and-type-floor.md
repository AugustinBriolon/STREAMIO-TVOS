# 18. Design system revision: ringless artwork focus, larger radii, a type floor

Date: 2026-11-11

## Status

Accepted

Refines [ADR-0006](0006-netflix-like-design-system.md).

## Context

An audit of the design system, read from the code and checked on an Apple TV HD, found four problems for a 10-foot interface:

- Focus on artwork stacked five signals: scale, white ring, specular sheen, 3D tilt and two shadows. The ring boxes the poster; Apple's own tvOS artwork does not use one.
- Full-width rows (the source picker) used the card focus. A 1.08 scale and a 6.5° tilt on a 1700 pt row push it into the screen margins and distort it.
- Radii were 8 pt (cards, buttons) and 4 pt (tags), tight at 3 m, and corners were sometimes `.continuous` and sometimes not.
- Text went down to 13 to 18 pt in Settings, pairing and the rail, with 49 hardcoded `.font(.system(size:))` and seven `Color.cyan` outside the tokens.

Liquid Glass (`glassEffect`, tvOS 26) was also tried for secondary buttons and chips. On the Apple TV HD used for testing it rendered as an opaque dark block, less legible than the current translucent grey (seen on a capture). It can only be judged properly on 4K hardware, which was not available.

## Decision

We will change the shared tokens and styles, not individual screens:

- `CardFocusStyle` draws no ring by default (scale, shadow, tilt, sheen). `showsRing: true` is reserved for cards with no artwork (logo tiles, source rows). `showsSheen: false` is for Top 10 tiles. Full-width rows pass `Theme.Motion.rowFocusScale` (1.02) and no tilt.
- Radii become 14 pt (cards), 12 pt (buttons), 20 pt (panels, section cards) and 6 pt (tags), always `.continuous`.
- The type floor is 23 pt (`caption`); `badge` is 20 pt. Headings get a negative tracking (`displayTracking`, -0.8). A new token `Palette.info` replaces the cyan.
- Liquid Glass is not adopted for now.

## Options considered

### Option A — Revise tokens and focus styles (chosen)
- Pros: one change reaches every screen; the focus reads by lift alone on artwork; text is legible at distance.
- Cons: every text size and radius moved, so each screen needs a visual check.

### Option B — Keep the ring, fix only the wide rows
- Pros: smallest change.
- Cons: leaves the stacked focus signals and the boxed posters.

### Option C — Adopt Liquid Glass for secondary controls
- Pros: native look on tvOS 26.
- Cons: no usable result on the Apple TV HD and no 4K device to evaluate it; a blur material in scrolling rows is also against the performance budget in DESIGN.md.

## Consequences

### Positive
- Source rows no longer distort or leave the safe area.
- No hardcoded font size or cyan is left in Settings and pairing, and the 13 to 18 pt text is gone.

### Negative
- Larger text lengthens several Settings and pairing layouts; only the bottom of Settings was checked on the device.
- Without a ring, focus on a poster rests on scale and shadow, a taste call that can be reverted in one default value.

### Neutral
- Large icon glyphs (40 pt and up) and the rail's own fonts keep their literal sizes.

## References
- [ADR-0006](0006-netflix-like-design-system.md)
- https://developer.apple.com/design/human-interface-guidelines/focus-and-selection
