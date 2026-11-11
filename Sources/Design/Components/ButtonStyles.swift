import SwiftUI

/// Focus style for custom interactive cards (like circular cast cards) that render their own focus visuals and 3D tilts.
struct PlainFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Artwork card focus: scale up with a white ring, like a 10-foot streaming UI.
/// Top 10 tiles pass `showsRing: false` so the rank number is not boxed.
/// `onFocus` fires when the card gains focus (list pages use it to follow the focused title).
struct CardFocusStyle: ButtonStyle {
    var showsRing = true
    var onFocus: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        CardFocusBody(configuration: configuration, showsRing: showsRing, onFocus: onFocus)
    }
}

private struct CardFocusBody: View {
    let configuration: ButtonStyleConfiguration
    let showsRing: Bool
    let onFocus: (() -> Void)?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only observe tilt when focused, keeping unfocused cards completely exempt from re-renders.
    private var tilt: (x: Double, y: Double) {
        if isFocused && !reduceMotion {
            return (RemoteTiltModel.shared.x, RemoteTiltModel.shared.y)
        }
        return (0, 0)
    }

    private var isTouching: Bool {
        isFocused && !reduceMotion && RemoteTiltModel.shared.isTouching
    }

    var body: some View {
        let currentTilt = tilt
        // Max tilt angles: 6.5 degrees (~0.11 rad) provides tactile 3D relief without distortion
        let pitchDegrees = -currentTilt.y * 6.5
        let yawDegrees = currentTilt.x * 6.5

        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused && showsRing ? 3 : 0)
            }
            .overlay {
                if isFocused && showsRing {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(Theme.Gradients.specularSheen)
                        .offset(x: CGFloat(currentTilt.x * 12), y: CGFloat(-currentTilt.y * 8))
                        .opacity(0.85 + abs(currentTilt.x) * 0.25)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, reduceMotion: reduceMotion))
            // 3D Parallax Tilt along X (pitch) and Y (yaw) with camera perspective:
            .rotation3DEffect(.degrees(pitchDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
            .rotation3DEffect(.degrees(yawDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
            // Apple TV dual-layer shadow dynamically displaced by 3D tilt:
            // 1. Broad ambient diffusion
            .shadow(
                color: Color.black.opacity(isFocused ? (configuration.isPressed ? 0.30 : 0.45) : 0),
                radius: configuration.isPressed ? Theme.Shadow.pressedAmbientRadius : Theme.Shadow.ambientRadius,
                x: CGFloat(currentTilt.x * 6),
                y: (configuration.isPressed ? Theme.Shadow.pressedAmbientY : Theme.Shadow.ambientY) + CGFloat(-currentTilt.y * 5)
            )
            // 2. Direct contact anchor
            .shadow(
                color: Color.black.opacity(isFocused ? (configuration.isPressed ? 0.22 : 0.32) : 0),
                radius: configuration.isPressed ? Theme.Shadow.pressedContactRadius : Theme.Shadow.contactRadius,
                x: CGFloat(currentTilt.x * 3),
                y: (configuration.isPressed ? Theme.Shadow.pressedContactY : Theme.Shadow.contactY) + CGFloat(-currentTilt.y * 3)
            )
            .animation(
                isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: currentTilt.x
            )
            .animation(
                isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: currentTilt.y
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .zIndex(isFocused ? 1 : 0)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    onFocus?()
                } else {
                    RemoteTiltModel.shared.settle()
                }
            }
    }
}

/// Text buttons: primary is solid white ("Lecture"), secondary is translucent grey that turns white on focus.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    var onFocus: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, kind: kind, onFocus: onFocus)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    let onFocus: (() -> Void)?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Bool { kind == .primary || isFocused }

    var body: some View {
        configuration.label
            .font(Theme.Typography.button)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .foregroundStyle(highlighted ? Color.black : Theme.Palette.textPrimary)
            .background(highlighted ? Color.white : Theme.Palette.secondaryButton,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .fill(Theme.Gradients.specularSheen)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, focusScale: 1.06, reduceMotion: reduceMotion))
            .shadow(
                color: Color.black.opacity(isFocused ? (configuration.isPressed ? 0.25 : 0.40) : 0),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 3 : 7
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus?() }
            }
    }
}

/// Selectable chip (season picker). `isSelected` is persistent state, focus is transient.
struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct ChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Theme.Typography.caption.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .foregroundStyle(isFocused ? Color.black : Theme.Palette.textPrimary)
            .background {
                Capsule().fill(isFocused ? Color.white : (isSelected ? Theme.Palette.surfaceRaised : Color.clear))
            }
            .overlay {
                if isFocused {
                    Capsule().fill(Theme.Gradients.specularSheen).allowsHitTesting(false)
                } else {
                    Capsule().strokeBorder(Theme.Palette.textTertiary, lineWidth: isSelected ? 0 : 1)
                }
            }
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, focusScale: 1.06, reduceMotion: reduceMotion))
            .shadow(color: Color.black.opacity(isFocused ? 0.35 : 0), radius: 10, y: 5)
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

/// Style de bouton sélecteur pour menus déroulants et filtres de navigation tvOS (Apple TV HIG).
/// Offre une lisibilité et une clarté de focus immédiate à 3 mètres :
/// - Repos : capsule en verre sombre dépoli avec bordure subtile.
/// - Focus : fond blanc éclatant, textes/icônes noirs, échelle 1.06x, ombre portée d'élévation et reflet spéculaire.
/// - Pression : échelle 0.96x tactile avec ressort instantané.
struct AppleTVSelectStyle: ButtonStyle {
    var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        AppleTVSelectBody(configuration: configuration, isHighlighted: isHighlighted)
    }
}

/// Focus style spécialement conçu pour les bannières vitrines héroïques tvOS (`AwardWinnerHeroCard`).
/// Résout les régressions de physique et de mise à l'échelle (Standards 5 & 10 d'Emil Kowalski) :
/// - Une surface massive (>1700pt de large) ne doit jamais subir un scale de 1.08x (+146pt !),
///   qui déborde des bords de l'écran et vient heurter le menu supérieur.
/// - Échelle d'élévation contenue à 1.018x (+32pt total de largeur, +4.8pt de hauteur).
/// - 3D Parallax mesuré : inclinaison limitée à 1.2° max (au lieu de 6.5°) pour éliminer la projection zénithale.
/// - Ombre d'élévation cinématographique et anneau blanc/or éclatant au focus.
/// - Press dip à 0.985x préservant la masse visuelle de la grande surface.
struct HeroBannerFocusStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Radius.card * 1.5
    var onFocus: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        HeroBannerFocusBody(configuration: configuration, cornerRadius: cornerRadius, onFocus: onFocus)
    }
}

private struct HeroBannerFocusBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let onFocus: (() -> Void)?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tilt: (x: Double, y: Double) {
        if isFocused && !reduceMotion {
            return (RemoteTiltModel.shared.x, RemoteTiltModel.shared.y)
        }
        return (0, 0)
    }

    private var isTouching: Bool {
        isFocused && !reduceMotion && RemoteTiltModel.shared.isTouching
    }

    var body: some View {
        let currentTilt = tilt
        // Inclinaison 3D subtile de 1.2° max adaptée à l'inertie visuelle d'une grande bannière
        let pitchDegrees = -currentTilt.y * 1.2
        let yawDegrees = currentTilt.x * 1.2

        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.white : Color.clear,
                        lineWidth: isFocused ? 2.5 : 0
                    )
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.Gradients.specularSheen)
                        .offset(x: CGFloat(currentTilt.x * 8), y: CGFloat(-currentTilt.y * 4))
                        .opacity(0.75)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(
                Theme.Motion.scale(
                    focused: isFocused,
                    pressed: configuration.isPressed,
                    focusScale: 1.018,
                    reduceMotion: reduceMotion
                )
            )
            .rotation3DEffect(.degrees(pitchDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.85)
            .rotation3DEffect(.degrees(yawDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.85)
            .shadow(
                color: Color.black.opacity(isFocused ? 0.55 : 0.20),
                radius: isFocused ? (configuration.isPressed ? 16 : 28) : 10,
                x: CGFloat(currentTilt.x * 4),
                y: isFocused ? (configuration.isPressed ? 8 : 14) : 4
            )
            .shadow(
                color: Color(hex: "#FFD700").opacity(isFocused ? 0.28 : 0),
                radius: isFocused ? 22 : 0,
                x: 0,
                y: 0
            )
            .animation(
                isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: currentTilt.x
            )
            .animation(
                isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: currentTilt.y
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .zIndex(isFocused ? 1 : 0)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    onFocus?()
                } else {
                    RemoteTiltModel.shared.settle()
                }
            }
    }
}

private struct AppleTVSelectBody: View {
    let configuration: ButtonStyleConfiguration
    let isHighlighted: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : (isHighlighted ? Theme.Palette.textPrimary : Theme.Palette.textSecondary))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background {
                if isFocused {
                    Capsule().fill(Color.white)
                } else if isHighlighted {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        }
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
            }
            .overlay {
                if isFocused {
                    Capsule()
                        .fill(Theme.Gradients.specularSheen)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(
                Theme.Motion.scale(
                    focused: isFocused,
                    pressed: configuration.isPressed,
                    focusScale: 1.06,
                    reduceMotion: reduceMotion
                )
            )
            .shadow(
                color: Color.black.opacity(isFocused ? 0.45 : 0),
                radius: isFocused ? 16 : 0,
                y: isFocused ? 8 : 0
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
