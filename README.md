# StremioTV

Native Apple TV (tvOS) client for [Stremio](https://www.stremio.com/) addons, written in SwiftUI with a Netflix-like 10-foot interface: browse Cinemeta catalogs, keep a personal list, resume where you stopped and play the best stream from your own addons in one click.

## Scope and responsibilities

**What the app does:**

- Browses the official Cinemeta catalogs (movies and series): billboard, Top 10, trending and genre rows, search.
- Shows title pages with cast, seasons, episodes (with progress) and similar titles.
- Queries every configured stream addon in parallel, ranks the results (codec the device decodes, Debrid, best quality the TV can display) and plays the best one directly; a manual source picker remains available.
- Picks French audio and subtitles automatically from the file's embedded tracks (forced subtitles with French audio, full subtitles otherwise); both can be changed from the player.
- Tracks watch progress: "Reprendre la lecture" row, resume position, episode watched at 90 %, "Épisode suivant" action in the player.
- Keeps "Ma liste" locally.
- Serves a PIN-protected local web page (port 8080, only while Réglages is open) to paste addon URLs from a phone or computer.

**What it does not do:**

- No Stremio account sync, no torrent engine: torrent-only streams are listed but not playable; use a Debrid addon.
- No transcoding: playback uses libVLC (TVVLCKit), which plays MKV, DTS/TrueHD and embedded SRT/PGS subtitles, but 4K HEVC cannot be decoded in real time on an Apple TV HD; such sources are tried last. Direct play falls back to the next candidate (up to 3) on error or when no picture appears.

**Main dependencies:**

- **Cinemeta** (`v3-cinemeta.strem.io`) — catalogs, metadata, search.
- **metahub** (`images.metahub.space`) — posters, backdrops, logos.
- **User-configured Stremio addons** — stream sources (`/stream/{type}/{id}.json`).

## Architecture

```text
Sources/
├── App/            # Entry point, dependency wiring, image cache sizing
├── Design/         # Theme tokens + pure components (cards, rows, buttons, states)
├── Models/         # Stremio protocol models, stream parsing, load state
├── Services/       # StremioService (network), LibraryStore, AddonStore (Keychain),
│                   # StreamRanker, HTTPRequestParser, ConfigPortal/ConfigServer
└── Features/       # Root (sidebar), Home, Detail, Streams, Player, Search, MyList, Settings
Tests/StremioTVTests/  # Swift Testing unit tests
```

- Views render only; loading and rules live in `@Observable @MainActor` view models and services.
- `StremioProviding` abstracts the network so view models and the playback coordinator are tested with stubs.
- `PlaybackCoordinator` turns "Lecture" into a `PlaybackSession` (ranked candidates, resume point, next episode); `PlayerController` drives the libVLC engine (`VLCPlayerEngine`) with candidate fallback, "no picture" detection and default track selection (`TrackSelector`); `PlayerView` is the SwiftUI overlay.
- Player remote: click = play/pause (or confirm a seek), left/right = seek preview that accelerates (10 → 60 s per press), circling the clickpad ring = fast seek, down = Audio / Sous-titres menus, Menu = cancel the seek, then hide controls, then close. Seeking pauses on a preview frame with its timestamp; frames come from a background grid generated during playback (`ThumbnailProvider`), since addons provide no trickplay images.
- Long press on a "Reprendre la lecture" card: remove it from the row (watched marks are kept) or toggle Ma liste. Focus returns to the card or button that started playback when the player closes.
- Design tokens and the visual language are described in [DESIGN.md](DESIGN.md). Decisions are recorded in [docs/adr](docs/adr).

## Getting Started

### Prerequisites

- macOS with Xcode 26 or later (tvOS 18+ SDK), `curl` and `shasum` (preinstalled)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple TV on tvOS 18+ paired with Xcode (Developer Mode enabled), or a tvOS simulator runtime (`xcodebuild -downloadPlatform tvOS`)
- An Apple developer team set in `project.yml` (`DEVELOPMENT_TEAM`)

### Fetch the playback engine and generate the project

TVVLCKit (official VideoLAN build, ~120 MB, checksum-verified) is downloaded into the git-ignored `Vendor/` folder:

```bash
./scripts/fetch-vlckit.sh
```

```bash
xcodegen generate
```

### Build, install and run on an Apple TV

```bash
xcrun devicectl list devices
```

```bash
xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "id=<APPLE_TV_UDID>" -derivedDataPath build -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <APPLE_TV_UDID> build/Build/Products/Debug-appletvos/StremioTV.app
```

```bash
xcrun devicectl device process launch --device <APPLE_TV_UDID> com.h6245.vortxtv
```

### Configure addons

Open **Réglages** on the TV, then on a phone or computer on the same Wi-Fi open the displayed address (`http://<tv-ip>:8080`) and enter the 4-digit code. Paste addon manifest URLs (e.g. Torrentio configured with a Debrid service). URLs can also be typed in Réglages directly. URLs are stored in the Keychain and only their host is ever displayed.

## Tests

Unit tests (Swift Testing) cover stream parsing and ranking (including HEVC on Apple TV HD), default audio/subtitle selection on real track names, seek preview/acceleration and clickpad ring rotation math, the preview grid plan, the HTTP parser and config portal security, Keychain migration, library/progress rules, episode navigation, playback resolution and view models.

```bash
xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "id=<APPLE_TV_UDID>" -allowProvisioningUpdates test
```

Use `-destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)"` instead when a tvOS simulator runtime is installed.

There are no automated UI tests (see [ADR 0002](docs/adr/0002-unit-testing-with-swift-testing.md)). Before a release, check on the device: sidebar navigation, billboard and rows, Ma liste add/remove, direct play of an MKV source with picture and subtitles, audio/subtitle menus during playback, seek preview with arrows and with a circular gesture on the clickpad ring (cannot be automated), long-press removal from Reprendre la lecture, resume, "Épisode suivant" near the end of an episode, search, Réglages PIN flow.

## Development

| Task | Command |
|---|---|
| Regenerate the Xcode project after adding/removing files | `xcodegen generate` |
| Compile app and tests without a device | `xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "generic/platform=tvOS Simulator" build-for-testing` |

Conventions (also in [.claude/CLAUDE.md](.claude/CLAUDE.md)):

- UI strings are French; code, comments and docs are English.
- Use `Theme` tokens, never hardcoded colors or sizes in features.
- New logic goes into a service or view model with a unit test; views stay pure.
- `project.yml` is the source of truth; do not edit `StremioTV.xcodeproj` by hand.

## Security model

- The configuration server only listens while Réglages is visible, requires the PIN shown on the TV, authorises changes with a `SameSite=Strict` session cookie, accepts mutations only via `POST`, escapes all output and rotates the PIN after 5 wrong attempts. See [ADR 0005](docs/adr/0005-pin-protected-local-config-server.md).
- Addon URLs (which embed Debrid API keys) are stored in the Keychain, migrated once from the pre-2.0 `UserDefaults` keys. See [ADR 0004](docs/adr/0004-local-persistence-userdefaults-and-keychain.md).

## Related documentation

- [DESIGN.md](DESIGN.md) — design system and tvOS interaction rules
- [docs/adr](docs/adr) — architecture decision records ([ADR 0007](docs/adr/0007-libvlc-playback-engine.md): why libVLC instead of AVPlayer)
- [Stremio addon protocol](https://github.com/Stremio/stremio-addon-sdk/tree/master/docs/protocol)
