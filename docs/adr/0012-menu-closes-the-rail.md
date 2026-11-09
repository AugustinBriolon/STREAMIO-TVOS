# 12. Menu closes the rail instead of leaving the app

Date: 2026-11-09

## Status

Accepted. Supersedes the "Menu in the rail leaves the app" rule of [ADR-0010](0010-custom-icon-rail-navigation.md) and [ADR-0011](0011-rail-reachable-by-moving-left.md).

## Context

With the rail focused, Menu kept its system meaning and left the app. The owner wants Menu to close the rail without quitting.

## Decision

The rail handles Menu itself (`onExitCommand`) and returns focus to the page. Menu on a page root still opens the rail, so Menu alone no longer leaves the app from the top level; the Apple TV (Home) button does.

## Options considered

### Option A — Menu closes the rail (chosen)
- Pros: what the owner asked; a predictable open/close pair.
- Cons: no top-level exit with Menu.

### Option B — Menu closes the rail, a second Menu within 1.5 s leaves
- Pros: keeps a Menu exit.
- Cons: hidden timing rule, easy to trigger by accident.

## Consequences

### Positive
- Menu never quits the app by surprise.

### Negative
- Leaving the app requires the Home button.

### Neutral
- Pressing Menu on a pushed title page still goes back; on a page root it opens the rail.

## References
- [DESIGN.md](../../DESIGN.md)
