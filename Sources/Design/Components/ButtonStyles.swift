import SwiftUI

/// Focus style for custom interactive cards (like circular cast cards) that render their own focus visuals and 3D tilts.
struct PlainFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Card focus: lift (scale, shadow, tilt) with a specular sheen. Artwork carries no ring: the lift
/// reads on an image, and a ring boxes the poster. Cards without artwork (logo tiles, text rows)
/// pass `showsRing: true`, their flat surface needs the outline to read as focused.
/// Top 10 tiles pass `showsSheen: false` so the rank number is not covered.
/// `onFocus` fires when the card gains focus (list pages use it to follow the focused title).
/// Full-width rows pass `Theme.Motion.rowFocusScale` and `maxTiltDegrees: 0`: the card values
/// would push a wide row into the screen margins and visibly distort it.
struct CardFocusStyle: ButtonStyle {
    var showsRing = false
    var showsSheen = true
    var focusScale = Theme.Motion.focusScale
    var maxTiltDegrees = 6.5
    var onFocus: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        CardFocusBody(configuration: configuration, showsRing: showsRing, showsSheen: showsSheen, focusScale: focusScale,
                      maxTiltDegrees: maxTiltDegrees, onFocus: onFocus)
    }
}

private struct CardFocusBody: View {
    let configuration: ButtonStyleConfiguration
    let showsRing: Bool
    let showsSheen: Bool
    let focusScale: CGFloat
    let maxTiltDegrees: Double
    let onFocus: (() -> Void)?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only observe tilt when focused, keeping unfocused cards completely exempt from re-renders.
    private var tilt: (x: Double, y: Double) {
        if isFocused && !reduceMotion && maxTiltDegrees > 0 {
            return (RemoteTiltModel.shared.x, RemoteTiltModel.shared.y)
        }
        return (0, 0)
    }

    private var isTouching: Bool {
        isFocused && !reduceMotion && maxTiltDegrees > 0 && RemoteTiltModel.shared.isTouching
    }

    var body: some View {
        let currentTilt = tilt
        let pitchDegrees = -currentTilt.y * maxTiltDegrees
        let yawDegrees = currentTilt.x * maxTiltDegrees

        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused && showsRing ? 3 : 0)
            }
            .overlay {
                if isFocused && showsSheen {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Gradients.specularSheen)
                        .offset(x: CGFloat(currentTilt.x * 12), y: CGFloat(-currentTilt.y * 8))
                        .opacity(0.85 + abs(currentTilt.x) * 0.25)
                        .allowsHitTesting(false)
                }
            }
            // Flatten clipped artwork before scale/3D — otherwise focus scale squares the corners.
            .compositingGroup()
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, focusScale: focusScale, reduceMotion: reduceMotion))
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
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
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
