# 21. Loading without layout shifts

Date: 2026-11-11

## Status

Accepted

Refines [ADR-0009](0009-off-main-image-pipeline-and-cheap-backdrop.md).

## Context

Three loading behaviours made the app look unfinished on the Apple TV:

- A catalog or title page showed a centered spinner, then replaced it with the full page in one step.
- Clicking "Lecture" covered the screen with a black veil and a spinner until the player opened.
- Opening a title page showed a backdrop that then jumped. There were two causes. The page opened with the catalog item's image, and the detail metadata, once loaded, often named a different image that replaced it. And the backdrop was sized by the hero, which grows when the credits and distinctions arrive, so the picture was re-cropped.

Title logos were also loaded with `AsyncImage`, which has no memory cache and decodes on the main thread, so a logo already seen still appeared late.

## Decision

We will make every loading state keep the geometry of what it stands in for:

- Catalog, title and saga pages show static skeletons (`CatalogSkeleton`, `ShelfSkeleton`) with the real billboard and shelf geometry. They do not shimmer: a looping animation runs for the whole load and costs frames on the Apple TV HD.
- Between "Lecture" and the player, `ResolvingView` shows the title's own backdrop and logo with the lookup message, instead of a black veil.
- Page backdrops use one view, `BakedBackdrop`, with a fixed one-screen height (`Theme.Layout.backdropHeight`) and the page scrims baked into the image (see ADR-0009). A title page keeps the backdrop it opened with (`DetailViewModel.backdropURL`) and only takes the one from the details when the catalog item had none.
- `LogoTitle` loads through `ImagePipeline`, holds the logo's space while loading, and falls back to the text title only on failure.

## Options considered

### Option A — Geometry-preserving placeholders and a pinned backdrop (chosen)
- Pros: nothing moves when the content arrives; no per-frame cost during the wait; the same image path as every other artwork.
- Cons: a skeleton must be kept in step with the layout it imitates; a title page never upgrades to a higher quality image from the details.

### Option B — Animated shimmer skeletons
- Pros: the usual streaming-app look.
- Cons: a continuous animation over many blocks on the A8 chip, against the performance budget in DESIGN.md.

### Option C — Keep spinners, only fade the content in
- Pros: no new views.
- Cons: the blank screen and the layout jump remain; the fade was already in place and was not enough.

## Consequences

### Positive
- On the Apple TV, three captures taken while a title page loaded showed the same backdrop pixels (mean difference 0.00 between the last three frames; the first frame was still the loading state).
- A logo seen once appears at once the next time, from the memory cache.

### Negative
- The skeleton for a series uses the episode card size and for a movie the poster size: a page whose real content differs in shape still shifts a little.
- The fixed backdrop height assumes the 1920 x 1080 pt tvOS canvas.
- The skeleton, the resolving screen and the staged hero entrance were checked on captures at rest; their motion was not.

### Neutral
- Backdrops on title and saga pages are now dimmed by 30 %, like the home page, so the synopsis stays readable over the full-bleed image.

## References
- [ADR-0009](0009-off-main-image-pipeline-and-cheap-backdrop.md)
- [ADR-0020](0020-smaller-tmdb-renditions-and-measured-player-buffer.md)
