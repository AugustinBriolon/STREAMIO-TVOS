# 9. Off-main image pipeline and a cheap page backdrop

Date: 2026-11-09

## Status

Accepted

## Context

Browsing felt choppy on the owner's Apple TV HD (A8). `XCTHitchMetric` returns no data on tvOS (`hasPerformanceMetrics: false`), so frame pacing was measured on the device with a temporary `CADisplayLink` probe: a frame counts as missed when more than 25 ms elapsed since the previous one. Scenario: scripted fast browsing of the home page (rows, 8 cards sideways, back), 17 three-second windows.

Baseline (frames above 25 ms / above 50 ms): **13.4 % / 6.3 %**. One-at-a-time ablations:

| Variant | > 25 ms | > 50 ms |
|---|---|---|
| Baseline | 13.4 % | 6.3 % |
| No focus shadow | 13.5 % | 5.3 % |
| No Top 10 outline | 12.1 % | 4.7 % |
| No artwork (flat colour) | 7.8 % | 2.6 % |
| **No dynamic backdrop** | **4.7 %** | **1.6 %** |

The dynamic backdrop (ADR-less feature added earlier the same day) was the largest cost, then artwork decoding with `AsyncImage`.

## Decision

- Add `ImagePipeline`: network fetch and ImageIO downsampling (`kCGImageSourceShouldCacheImmediately`, max pixel size = displayed size × screen scale) in a detached task, memory cache (160 MB), de-duplication of in-flight requests, background prefetch of the first posters of every row. `RemoteImage` uses it instead of `AsyncImage`.
- Bake the backdrop scrims (gradients and dimming) into the decoded backdrop image once, so the page draws one opaque layer.
- `DynamicBackdrop` fades by keeping the old image opaque and fading the new one in on top (single blended layer), and only starts once the new image is decoded.
- `DynamicBackdrop` reads `BackdropModel` itself; pages no longer observe it, so a focus change does not rebuild every shelf.

Measured after each step (> 25 ms / > 50 ms): pipeline 9.6 / 3.6 %, scrims baked 10.9 / 3.7 % (no gain, kept for simplicity of compositing), isolated observation 6.4 / 2.3 %, final **5.9 % / 2.4 %**.

## Options considered

### Option A — Pipeline plus a cheaper backdrop (chosen)
- Pros: removes about 55 % of missed frames while keeping the feature; decoding cost moves off the main thread.
- Cons: custom image code to maintain (about 120 lines); memory cache must be bounded.

### Option B — Remove the dynamic backdrop
- Pros: the cheapest browsing (4.7 %).
- Cons: loses a requested feature for about 1.2 points of missed frames.

### Option C — Keep `AsyncImage` and tune view modifiers
- Pros: no custom code.
- Cons: the ablation shows decoding is the cost, not modifiers; the shadow and outline changes measured no real gain.

## Consequences

### Positive
- Frames above 25 ms drop from 13.4 % to 5.9 %, above 50 ms from 6.3 % to 2.4 %.
- Rows are already decoded when scrolled to; images appear without placeholder flashes when cached.

### Negative
- The measurement probe was temporary and is not in the app; re-running the comparison needs it re-created.
- About 40 MB of decoded artwork stays in memory while browsing.

### Neutral
- Focus shadow and Top 10 outline were left as is (measured no meaningful gain).

## References
- [DESIGN.md](../../DESIGN.md) — motion and performance budget
