# StremioTV Design System & Architecture

An opinionated, cinematic, and modern design system for StremioTV on tvOS, adhering to `baseline-ui` and Apple Human Interface Guidelines for 10-foot television experiences.

---

## 1. Visual Foundation

### 1.1 Palette & Surface Roles
- **Canvas / Background**: Deep OLED Black (`#07080A` to `#000000`)
- **Card Surface**: Glassmorphism (`ultraThinMaterial` / `Color.white.opacity(0.06)`) with high-precision subtle border (`Color.white.opacity(0.12)`)
- **Focus Ring & Accent**: Dynamic System Highlight (`#0A84FF` / Electric Sky Blue, glowing 2px stroke on focus with scale spring `1.06`)
- **Badges & Metadata**:
  - Rating: Gold `#FFD60A` star with semi-transparent frosted black capsule
  - 4K / UHD: Vibrant Indigo-Violet `#5E5CE6`
  - 1080p / FHD: Cyan `#30B0C7`
  - Debrid / Fast Stream: Emerald `#30D158` (⚡️ Cached)
  - Torrent / Seeds: Light Green `#34C759`

### 1.2 Spacing Scale
- `4pt`: Micro-spacing (badge internal padding)
- `8pt`: Tight element spacing (title to subtitle)
- `16pt`: Medium item spacing (shelf cards, button internals)
- `24pt`: Grid row spacing, section headers
- `36pt`: Shelf separation
- `48pt`: Safe area margins (left/right screen gutter for 10-foot display)
- `64pt`: Large block separation (hero to shelves)

### 1.3 Typography Scale (SF Pro / System Rounded)
- **Hero Title**: `44pt`, Bold / Heavy, tracking tight
- **Section / Shelf Heading**: `28pt`, Bold
- **Card Title**: `18pt`, SemiBold, 1 line limit with truncation
- **Body / Synopsis**: `20pt`, Regular, line spacing 6pt, max width 1100pt for optimal 10-foot readability
- **Metadata & Badges**: `14pt`, Bold Monospaced Digits (`.monospacedDigit()`)

---

## 2. Interaction & Focus Physics (tvOS 10-Foot UI)

1. **Focus Engine Alignment**:
   - Every interactive element uses native focus states (`@FocusState`).
   - Cards scale smoothly to `1.06` with an interactive spring (`response: 0.28, dampingFraction: 0.75`).
   - Focused cards gain an elevated shadow (`radius: 20, y: 10`) and a vibrant subtle stroke.
2. **Hero Spotlight**:
   - Moving focus across top shelf cards dynamically updates the ambient backdrop and synopsis preview with a crossfade animation (`0.3s ease-out`).
3. **Stream Source Discovery**:
   - Multi-addon streams categorized with parsed metadata pills: resolution (4K/1080p), source provider (Lumio, Torrentio, Knightcrawler), file size, and seed count.
   - Direct launch into full-screen AVPlayer with native tvOS scrub bar and subtitle picker.
