import SwiftUI

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

    var body: some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused && showsRing ? 4 : 0)
            }
            .scaleEffect(isFocused ? Theme.Motion.focusScale : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 18, y: 10)
            .animation(Theme.Motion.focus, value: isFocused)
            .zIndex(isFocused ? 1 : 0)
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus?() }
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
            .scaleEffect(isFocused ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 12, y: 6)
            .animation(Theme.Motion.focus, value: isFocused)
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

    var body: some View {
        configuration.label
            .font(Theme.Typography.caption.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .foregroundStyle(isFocused ? Color.black : Theme.Palette.textPrimary)
            .background {
                Capsule().fill(isFocused ? Color.white : (isSelected ? Theme.Palette.surfaceRaised : Color.clear))
            }
            .overlay { Capsule().strokeBorder(Theme.Palette.textTertiary, lineWidth: isSelected || isFocused ? 0 : 1) }
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(Theme.Motion.focus, value: isFocused)
    }
}
