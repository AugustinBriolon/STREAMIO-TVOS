# 3. Raise deployment target to tvOS 18

Date: 2026-11-09

## Status

Accepted

## Context

The overhaul aims at a Netflix-like experience. Netflix on tvOS uses a collapsible left sidebar. SwiftUI only provides a native sidebar `TabView` (`Tab` API + `.tabViewStyle(.sidebarAdaptable)`) starting with tvOS 18. The app previously targeted tvOS 17 with a top tab bar. The owner's Apple TV runs tvOS 26.

## Decision

We will raise the deployment target from tvOS 17.0 to tvOS 18.0 and use the native sidebar `TabView`.

## Options considered

### Option A — tvOS 18 + native sidebar
- Pros: system focus behaviour, accessibility and animations for free; no custom navigation code.
- Cons: drops tvOS 17 devices.

### Option B — stay on tvOS 17 with a hand-built sidebar
- Pros: keeps tvOS 17 support.
- Cons: custom focus-section handling, collapse animation and Menu-button routing to maintain (~200 lines), less native feel.

### Option C — stay on tvOS 17 with the top tab bar
- Pros: zero effort.
- Cons: does not match the requested Netflix-like navigation.

## Consequences

### Positive
- Sidebar navigation with six destinations at no maintenance cost.
- Access to tvOS 18 SwiftUI APIs (`Tab`, `@Entry`, `onScrollGeometryChange`).

### Negative
- Apple TVs stuck on tvOS 17 can no longer install the app.

### Neutral
- All Apple TV models supported by tvOS 17 also support tvOS 18, so only non-updated devices are affected.

## References
- https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable
