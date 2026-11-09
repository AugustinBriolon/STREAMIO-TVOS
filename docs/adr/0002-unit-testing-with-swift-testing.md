# 2. Unit testing with Swift Testing

Date: 2026-11-09

## Status

Accepted

## Context

The app shipped without any test target. The Netflix-like overhaul adds non-trivial logic (stream ranking, resume/next-episode rules, a hardened local HTTP server, Keychain migration) that must be verified. The development machine has no tvOS simulator runtime; the only tvOS destination available is a physical Apple TV HD (tvOS 26). tvOS UI tests (XCUITest) depend on the focus engine and on live network catalogs, which makes them slow and flaky.

## Decision

We will add a `StremioTVTests` unit-test bundle (XcodeGen `bundle.unit-test`) using **Swift Testing** (`import Testing`, `@Test`, `#expect`). Tests cover models, pure services (`StreamRanker`, `HTTPRequestParser`), stores (with injected `UserDefaults` suites and in-memory secret storage) and view models (with a stubbed `StremioProviding`). We will not add XCUITest; user-facing flows are verified with a manual checklist on the Apple TV (documented in the README).

## Options considered

### Option A — Swift Testing unit tests + manual device checklist
- Pros: modern API, parameterized tests, runs on the physical device, no network dependency.
- Cons: user flows (focus, playback) are not automated.

### Option B — XCTest unit tests + XCUITest
- Pros: automates navigation flows.
- Cons: XCUITest on tvOS needs remote-button scripting, live catalogs make it non-deterministic, and runs take minutes on an Apple TV HD.

## Consequences

### Positive
- Every business rule introduced by the overhaul has a fast, deterministic test.
- Services are designed behind protocols, which also enforces dependency inversion.

### Negative
- Regressions in focus/navigation are only caught by manual testing.

### Neutral
- `xcodebuild test` requires a tvOS destination (device or simulator runtime).

## References
- https://developer.apple.com/documentation/testing
