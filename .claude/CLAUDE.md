# StremioTV — project instructions

Native tvOS (Apple TV) Stremio client written in SwiftUI. Target: tvOS 18+, Swift 5 language mode, Xcode 27.

## Layout

- `project.yml` — XcodeGen spec (source of truth). Run `xcodegen generate` after adding/removing files; never hand-edit `StremioTV.xcodeproj`.
- `Sources/App` — app entry point and dependency wiring.
- `Sources/Design` — design tokens (`Theme.swift`) and reusable, pure SwiftUI components.
- `Sources/Models` — Codable models for the Stremio protocol and local library.
- `Sources/Services` — networking (`StremioService`), persistence (`LibraryStore`, `AddonStore`), pure logic (`StreamRanker`, `HTTPRequestParser`), local config web server.
- `Sources/Features/<Feature>` — one folder per screen: `View` + optional `ViewModel`.
- `Tests/StremioTVTests` — unit tests (Swift Testing).
- `docs/adr` — Architecture Decision Records.

## Conventions

- UI strings are **French**; code, comments, docs and ADRs are **English**.
- Views are pure: data loading and business rules live in view models (`@Observable @MainActor`) or services.
- Dependencies are injected through the SwiftUI environment from `StremioTVApp`; services sit behind protocols so tests can stub them.
- Use `Theme` tokens for colors, spacing, typography — no hardcoded values in features.
- Secrets (addon URLs embed debrid keys) go to the Keychain, never to `UserDefaults` or logs.

## Commands

```bash
xcodegen generate
xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "generic/platform=tvOS Simulator" build-for-testing
xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "id=<APPLE_TV_UDID>" -allowProvisioningUpdates test
```

No tvOS simulator runtime is installed on the main dev machine; tests run on the physical Apple TV.
