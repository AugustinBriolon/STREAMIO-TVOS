# 13. Brand assets generated from one script

Date: 2026-11-09

## Status

Accepted

## Context

StremioTV had no app icon: the Apple TV home screen showed the generic grid placeholder, and there was no Top Shelf image. tvOS needs a layered icon (back, middle, front layers for the parallax effect) in two sizes (400x240 at 1x/2x on the home screen, 1280x768 for the App Store), plus two Top Shelf images (1920x720 and 2320x720, each at 1x and 2x). That is 22 PNG files to keep consistent with each other and with the palette in `Theme.swift`.

## Decision

We will draw the artwork in code: `scripts/generate-brand-assets.swift` (CoreGraphics, no dependency) writes the whole `Sources/Assets.xcassets` brand asset catalog from one drawing description scaled to every size. The generated catalog is committed so a clone builds without running the script. The icon is three layers: an opaque dark background with a red glow, a red ring over a dark disc, and a white rounded play triangle; the Top Shelf images combine the logo with the "StremioTV" wordmark, centered as a group. `ASSETCATALOG_COMPILER_APPICON_NAME` points at the brand asset; actool then emits `CFBundleIcons` and `TVTopShelfImage` in the generated Info.plist (verified in the built app).

## Options considered

### Option A — Generated from a script (chosen)
- Pros: one source for 22 files; palette changes are a re-run; reviewable as code; no design tool needed.
- Cons: the drawing is code, so a designer cannot edit it directly.

### Option B — Hand-made PNGs from a design tool
- Pros: free artistic control.
- Cons: 22 files to keep in sync by hand, and no tool available here.

### Option C — Static Top Shelf plus a dynamic Top Shelf extension
- Pros: could show "Reprendre la lecture" on the Apple TV home screen.
- Cons: needs an extension target and an app group to share the library, a much larger change; left for later.

## Consequences

### Positive
- The icon and a branded Top Shelf image ship with the app; the layers give the parallax effect on focus (checked on the Apple TV home screen).

### Negative
- The Top Shelf image is only visible when the app sits in the top row of the home screen (not checked on the device, which has the app in the bottom row).
- About 9 MB of generated PNGs are committed.

### Neutral
- Re-run `swift scripts/generate-brand-assets.swift` after changing the drawing; it rewrites the whole catalog.

## References
- https://developer.apple.com/design/human-interface-guidelines/app-icons#tvOS
