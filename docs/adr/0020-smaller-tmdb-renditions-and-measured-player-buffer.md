# 20. Smaller TMDB renditions and a measured player buffer

Date: 2026-11-11

## Status

Accepted

Refines [ADR-0009](0009-off-main-image-pipeline-and-cheap-backdrop.md).

## Context

Models carry TMDB images at one large size: `w500` posters and `w1280` backdrops. A poster card is 220 x 330 pt on a 1080p screen and a landscape card is 400 x 225 pt, so the Apple TV HD downloaded and decoded far more pixels than it displayed.

Separately, the player's libVLC network buffer is 4000 ms, and a shorter one was suggested to speed up the start of playback.

## Decision

We will fetch the smallest TMDB rendition that still covers the displayed size (`ImagePipeline.sizedURL`): `w342` instead of `w500` for images shown at 513 px or less on their longest side, and `w780` instead of `w1280` for backdrops shown at 780 px or less. Other hosts and larger displays keep the original URL. The cache key stays the original URL plus size, so callers do not change.

We will keep the player buffer at 4000 ms. It is now a named constant (`VLCPlayerEngine.networkCaching`). To keep the question answerable, `PlaybackProbe` measures the start delay and the stalls from the engine's own callbacks, printed in debug builds only and never with the stream URL, and a debug launch variable (`STREMIO_NETWORK_CACHING`) overrides the buffer without rebuilding.

## Options considered

### Option A — Smaller renditions, buffer kept after measuring (chosen)
- Pros: fewer bytes to download and decode per image on the slowest device; the buffer decision rests on numbers; the probe stays available for other streams.
- Cons: an image requested at a size just above a threshold is still fetched large; the sizes are hardcoded to two TMDB widths.

### Option B — Ask TMDB for an exact width per card
- Pros: no wasted pixels.
- Cons: TMDB only serves a fixed set of widths, so an arbitrary size is not possible.

### Option C — Lower the buffer to 2000 ms
- Pros: expected faster start.
- Cons: not supported by the measurement below, and a short buffer risks stalls on slow streams.

## Consequences

### Positive
- Posters are fetched at `w342` and landscape cards at `w780`, which cuts the data per image. This was not measured in frames per second on the device.
- Measured on the Apple TV, six plays of the same episode alternating the two buffers: start delay 3.91, 3.60 and 4.41 s at 4000 ms (mean 3.97 s) against 3.80, 3.64 and 3.53 s at 2000 ms (mean 3.66 s). The ranges overlap and no stall occurred in any run, so halving the buffer did not clearly speed up the start.

### Negative
- One stream, one connection and one minute per run: this cannot show whether a short buffer stalls on a slow stream or over a whole film.
- The stall counter is covered by a unit test but never detected a stall on the device, so it was not seen working under real conditions.

### Neutral
- The 3.6 to 4 s start delay is mostly not the buffer; where it goes (opening the remote stream, seeking to the resume point) was not investigated.

## References
- [ADR-0009](0009-off-main-image-pipeline-and-cheap-backdrop.md)
- https://developer.themoviedb.org/docs/image-basics
