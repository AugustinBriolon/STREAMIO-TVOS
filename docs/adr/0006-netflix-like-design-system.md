# 6. Netflix-like design system with code tokens

Date: 2026-11-09

## Status

Accepted

## Context

The 1.0 UI mixed glassmorphism, blue accents and ad-hoc values (paddings 48/54/64, five different focus treatments, colors hardcoded in each view) while `DESIGN.md` described tokens that did not exist in code. The product goal is now a Netflix-like experience: artwork-led, dark, with a single obvious primary action. The app also runs on an Apple TV HD (A8), where blur materials in scrolling rows are expensive.

## Decision

We will define all tokens (palette, spacing, radius, typography, card sizes, motion) in `Theme.swift`, implement focus and buttons as reusable `ButtonStyle`s (`CardFocusStyle`, `PillButtonStyle`, `ChipButtonStyle`) driven by `@Environment(\.isFocused)`, and build screens only from shared components. The palette is a `#141414` canvas with a red `#E50914` accent reserved for progress, tags and errors.

## Options considered

### Option A — Custom tokens and button styles
- Pros: consistent look, one place to tune, cheap rendering (no materials), matches the requested Netflix-like feel.
- Cons: custom focus effects lose the system parallax.

### Option B — System `.card` / `.bordered` styles everywhere
- Pros: zero code, native parallax.
- Cons: generic Apple TV look, little control over hierarchy (primary vs secondary), heavier on A8 with many cards.

## Consequences

### Positive
- Screens share one visual language; changing a token updates every screen.
- Duplicated per-view styling (rating pills, focus effects, empty states) is replaced by shared components.

### Negative
- Focus effects must be maintained by us (no automatic parallax/tilt).

### Neutral
- `DESIGN.md` documents the tokens; `Theme.swift` is the source of truth.

## References
- [DESIGN.md](../../DESIGN.md)
