# 7. libVLC (TVVLCKit) as the playback engine

Date: 2026-11-09

## Status

Accepted

## Context

After the 2.0 overhaul, most playback attempts failed and the rest showed no picture and no subtitles. Raw evidence collected on the owner's Apple TV HD (A8, tvOS 26):

- The only stream addon in use (Lumio) returned 100 % Matroska files flagged `notWebReady: true`.
- `AVPlayerItem` failed on every candidate with `AVFoundationErrorDomain -11828 Cannot Open` / `OSStatus -12847` (5/5 titles).
- `ffprobe` on the same URLs: video H.264 (1080p) or HEVC Main 10 / Dolby Vision (4K); French audio in DTS-HD MA, TrueHD, AC3 or E-AC3; subtitles embedded as SubRip and PGS.
- The Apple TV HD has no HEVC hardware decoder (`VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) == false`), which explains "sound but no picture" on HEVC files.

AVFoundation cannot demux Matroska, decode DTS/TrueHD, or render embedded SRT/PGS tracks from progressive files.

## Decision

We will play every stream with libVLC through VideoLAN's official TVVLCKit 3.7.3 binary (LGPL-2.1), fetched and checksum-verified by `scripts/fetch-vlckit.sh` into the git-ignored `Vendor/` directory and embedded through XcodeGen. The player UI becomes a custom SwiftUI overlay (transport, audio/subtitle menus, next episode). Around the engine:

- `StreamRanker` uses `DeviceCapabilities` (display height + `VTIsHardwareDecodeSupported`) to rank HEVC last on devices that cannot decode it.
- `PlayerController` falls back to the next candidate on engine error **or** when 6 s of playback produced no video output.
- `TrackSelector` picks French audio (VFF, Dolby before DTS/TrueHD, never commentary/audio description) and French subtitles (forced only with French audio, full otherwise; text before PGS), following the device language.

## Options considered

### Option A — TVVLCKit (official VideoLAN binary)
- Pros: plays MKV, DTS/TrueHD (software), SRT/PGS out of the box; uses VideoToolbox for H.264/HEVC; mature tvOS track record (VLC for tvOS).
- Cons: ~120 MB download, custom player UI to maintain, no native AVKit features (PiP-like info panel, system scrubbing previews).

### Option B — Third-party SPM repackage of VLCKit (koombea/vlckit-spm)
- Pros: one-line SPM integration.
- Cons: older 3.6.0 build repackaged by a third party (supply-chain trust).

### Option C — Keep AVPlayer and filter unplayable sources
- Pros: no dependency.
- Cons: with the current addon nothing would remain playable.

### Option D — Remux to HLS through a streaming server (Stremio server, Debrid transcoding)
- Pros: AVPlayer-native UI and subtitles.
- Cons: requires running/operating a server or a Debrid-specific API.

## Consequences

### Positive
- Titles that failed 5/5 now play with picture; embedded subtitles are selectable and auto-selected (verified on the Apple TV HD).

### Negative
- Fresh clones must run `scripts/fetch-vlckit.sh` before building.
- LGPL obligations if the app is ever distributed (dynamic framework, license notice in `Vendor/TVVLCKit-COPYING.txt`).
- 4K HEVC remains unwatchable on Apple TV HD (hardware limit); it is only tried after non-HEVC sources.

### Neutral
- `AVKit` is no longer used for playback.

## References
- https://code.videolan.org/videolan/VLCKit
- https://download.videolan.org/cocoapods/prod/
- https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md (`notWebReady`)
