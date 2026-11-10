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

- **Icon rail** (`NavRail`, ADR 0010): Accueil, Films, Séries, Ma liste, Recherche, Réglages. Icons only, no background of any kind, in the left margin; names slide in while the rail has focus (with a soft black gradient behind them), States without boxes: **selected** = filled symbol, bold name, full white, red mark; **cursor** = white and enlarged; **others** = outline symbol, medium weight, 42 % white. Moving left from any card opens it (landing on the current page), and so does Menu on a page root; Menu inside the rail closes it (ADR 0012) and selecting a destination returns focus to the page. Pages cross-fade and keep their state (ADR 0010, 0011).
- **Accueil / Films / Séries**: billboard → Reprendre la lecture → Ma liste → Top 10 → trending → genre rows.
- **Profils**: the rail entry is named after the active profile. "Qui regarde ?" shows each profile as a colored disc (8 colors) with a symbol (10), the active one marked "Profil actif", plus a dashed "Ajouter un profil" disc. "Gérer les profils" puts a pencil badge on each card; the editor previews the avatar, and deletion asks for confirmation with Annuler as the default (ADR 0014).
- **Dynamic backdrop**: list pages draw one fixed full-screen backdrop behind the scrolling content. It cross-fades (0.45 s) to the focused title 250 ms after focus settles (`BackdropModel`), is dimmed 30 % under the scrims, and returns to the billboard title when focus goes back to its buttons.
- **Title page**: hero with logo, meta, synopsis, credits, progress, actions (Lecture/Reprendre, Ma liste, Choisir une source) → seasons chips → episode cards (progress, watched check; long-press for sources) → Titres similaires.
- **Seeking**: arrows or a circle on the clickpad ring pause playback and move a red scrub head; a 384×216 preview frame (white 3 pt border) and a large timestamp float above it, clamped to the screen. Click confirms, Menu returns to where playback was. Track buttons fade out while seeking.
- **Player**: libVLC video surface with a custom overlay: title/episode, play state, red progress and remaining time, `Audio` / `Sous-titres` buttons opening a two-column track panel (solid black, short track names, checkmark on the active track) and a primary "Épisode suivant" button during the last 60 s. Controls hide after 5 s of playback without interaction; a source fallback shows "Source illisible, essai de la source N…".

## 7. Motion

Principles (Apple's fluid-interface talks, Emil Kowalski's animation rules, translated to tvOS):

- **Fast and strong ease-out** (`cubic-bezier(0.23, 1, 0.32, 1)`): feedback starts at once and settles gently, never overshoots. Focus changes happen dozens of times a minute, so `Theme.Motion.focus` is 0.2 s; fades and panels 0.25–0.3 s. No `ease-in`, no springs with bounce on navigation.
- **Retargetable, not scripted**: SwiftUI animations start from the on-screen value, so moving focus twice quickly never jumps. The backdrop fade only ever stacks two layers: it settles an unfinished fade before starting the next.
- **Only `transform` and `opacity` move**: focus scale, backdrop opacity, panel opacity. Backdrop scrims are baked into the image, so the compositor draws one opaque layer.
- **Click feedback**: every control dips to 0.96 of its focused size for 0.12 s when clicked (`Theme.Motion.scale`). On tvOS only the focused element is clickable, so the dip multiplies the focus scale.
- **Entrances**: content that arrives after loading fades in (0.3 s); rows are not staggered because they are created lazily and the stagger would replay on scroll.
- **Reduce Motion**: cards and buttons keep ring/colour feedback but stop scaling.
- **Nothing animates that is used constantly without need**: track rows, seek head and list rows react with colour only.
- **Performance budget (Apple TV HD, A8)**: browsing must stay under ~6 % of frames above 25 ms (measured with an in-app `CADisplayLink` probe, see ADR 0009). Artwork is decoded off the main thread at display size; page backdrops read their own state so a focus change never re-renders the page.
- Images fade in over 0.3 s only when they were not already cached.
