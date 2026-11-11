# 17. A "V" brand mark on a flat background

Date: 2026-11-11

## Status

Accepted

Refines [ADR-0013](0013-generated-brand-assets.md): the assets are still generated from one script, only the drawing changes.

## Context

The icon drawn for ADR 0013 was a red ring with a glow around a white play triangle, over a red radial gradient and a vignette. The ring-and-triangle shape is the default "streaming app" icon, and the glow and gradients make it look generic. The bundle identifier is `vortxtv`, so a "V" already means something in this project.

## Decision

We will draw the brand as one white, round-ended "V" holding a single red dot, on flat near-black (`#0B0B0C`), with no glow, gradient or vignette. The tvOS icon layers are the flat background (back), the V (middle) and the red dot (front), so the dot floats over the V during the parallax. The Top Shelf images pair the mark with the "StremioTV" wordmark in semibold.

`scripts/generate-brand-assets.swift` stays the single source. It now deletes only the brand asset folder instead of the whole `Sources/Assets.xcassets`.

## Options considered

### Option A — "V" with one red dot (chosen)
- Pros: a distinctive silhouette at 400x240 and at Top Shelf size; one accent, the same red as the progress bars; three simple layers keep a clean parallax; flat fills cannot band on an OLED TV.
- Cons: the V is not an obvious "video" symbol, so its meaning rests on the name.

### Option B — Heavy "S" cut by a diagonal bar
- Pros: reads as a wordmark initial.
- Cons: a cut letter is harder to keep legible when the parallax shifts its layers; says nothing about the product.

### Option C — Keep the ring and play triangle, tone the glow down
- Pros: no new drawing; instantly "video".
- Cons: keeps the shape that makes the icon look generic.

## Consequences

### Positive
- Icon and Top Shelf image no longer depend on blur, glow or gradient.
- Regenerating deletes only the brand asset folder instead of the whole catalog, so any hand-made image added to the catalog later survives. (The five unused ceremony logos that used to share the catalog were removed at the same time.)

### Negative
- The dot sits at a fixed offset inside the V: changing the V's proportions means re-tuning `drawDot`.
- Only the generated PNGs were checked, not the icon on the Apple TV home screen.

### Neutral
- The note in ADR 0013 about the Top Shelf image being visible only in the top home-screen row still applies.

## References
- [ADR-0013](0013-generated-brand-assets.md)
- https://developer.apple.com/design/human-interface-guidelines/app-icons#tvOS
