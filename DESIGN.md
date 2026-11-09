# StremioTV Design System

A Netflix-like, 10-foot interface for tvOS. Tokens live in [`Sources/Design/Theme.swift`](Sources/Design/Theme.swift); this document explains them. Components live in `Sources/Design/Components`.

## 1. Principles

1. **Artwork first.** Posters, backdrops and title logos carry the identity; chrome stays neutral and dark.
2. **One obvious action.** Every hero has a single white primary button ("Lecture" / "Reprendre"). Everything else is secondary.
3. **Focus is the cursor.** The focused element must be identifiable from across the room: scale + white ring, never color alone.
4. **Light on the hardware.** Targets include the Apple TV HD (A8): no blur materials in scrolling rows, short ease-out animations, cached images.

## 2. Color

| Token | Value | Use |
|---|---|---|
| `canvas` | `#141414` | App background |
| `surface` / `surfaceRaised` | white 8 % / 16 % | Cards, chips, settings panels |
| `secondaryButton` | grey 42 % at 55 % opacity | Unfocused secondary buttons |
| `accent` | `#E50914` | Progress bars, brand tint, 4K tag, errors. Never for large surfaces |
| `textPrimary/Secondary/Tertiary` | white 100 / 72 / 48 % | Hierarchy of text |
| `rating` | `#F5C518` | IMDb star |
| `match` | `#46D369` | Debrid tag |

## 3. Typography (SF Pro)

| Token | Size / weight | Use |
|---|---|---|
| `billboardTitle` | 64 black | Title fallback when no logo |
| `pageTitle` | 48 bold | Ma liste, Réglages, Sources |
| `rowTitle` | 30 bold | Row headers |
| `body` | 24 regular | Synopsis (max width 900 pt, 3–4 lines) |
| `meta` | 22 medium, monospaced digits | "★ 7.8 · 2026 · 109 min · Horror" |
| `cardTitle` | 22 semibold | Landscape cards, stream rows |
| `caption` | 18 medium | Secondary info |
| `rank` | 200 black, outlined | Top 10 numbers |

## 4. Spacing & shapes

- Scale: 4 · 8 · 12 · 16 · 24 · 40 · 64 pt. Horizontal gutter: **48 pt** inside the tvOS safe area. Gap between cards: 24 pt.
- Radius: cards and buttons 8 pt, tags 4 pt, chips capsule.
- Cards: poster 220×330 (2:3), landscape 400×225 (16:9, Reprendre), episode 360×202.
- Billboard / title hero: 760 pt minimum height, full-bleed backdrop with bottom and leading scrims.

## 5. Components

| Component | Notes |
|---|---|
| `CardFocusStyle` | Scale 1.08, 4 pt white ring, drop shadow, raises z-index. `showsRing: false` for Top 10 tiles |
| `PillButtonStyle(.primary)` | Solid white, black label — the main action |
| `PillButtonStyle(.secondary)` | Translucent grey; turns white on focus |
| `ChipButtonStyle` | Season picker; selected = raised surface, focused = white |
| `ShelfRow` | Titled horizontal row, `focusSection`, overflow allowed for focus scale |
| `PosterCard`, `LandscapeCard`, `Top10Card` | Artwork cards; landscape shows title, subtitle and red progress |
| `BackdropView`, `LogoTitle` | Hero artwork; logo falls back to text, light halo keeps dark logos legible |
| `MetaLine`, `ProgressBar`, `Tag` | Metadata line, watch progress, quality/HDR/audio tags |
| `StateView` | Loading, empty and error (+ "Réessayer") states |

## 6. Screens

- **Sidebar** (native `TabView`, `.sidebarAdaptable`): Accueil, Films, Séries, Ma liste, Recherche, Réglages.
- **Accueil / Films / Séries**: billboard → Reprendre la lecture → Ma liste → Top 10 → trending → genre rows.
- **Title page**: hero with logo, meta, synopsis, credits, progress, actions (Lecture/Reprendre, Ma liste, Choisir une source) → seasons chips → episode cards (progress, watched check; long-press for sources) → Titres similaires.
- **Player**: system `AVPlayerViewController` with title/episode metadata; "Épisode suivant" contextual action during the last 60 s.

## 7. Motion

- Focus: `easeOut` 0.18 s on scale/ring/shadow. No springs on rows (cheaper on A8, no overshoot while scrolling fast).
- Images fade in over 0.2 s. "Ma liste" icon swaps with a symbol replace transition.
