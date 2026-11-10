import SwiftUI

extension AvatarColor {
    var color: Color {
        switch self {
        case .red: return Color(red: 0.90, green: 0.20, blue: 0.22)
        case .orange: return Color(red: 0.98, green: 0.55, blue: 0.15)
        case .yellow: return Color(red: 0.97, green: 0.78, blue: 0.20)
        case .green: return Color(red: 0.25, green: 0.76, blue: 0.45)
        case .teal: return Color(red: 0.18, green: 0.70, blue: 0.74)
        case .blue: return Color(red: 0.25, green: 0.52, blue: 0.95)
        case .purple: return Color(red: 0.58, green: 0.38, blue: 0.92)
        case .pink: return Color(red: 0.95, green: 0.38, blue: 0.62)
        }
    }
}

/// A profile's avatar: a colored disc with a symbol. Pure: size and avatar in, picture out.
struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    var size: CGFloat = 180

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [avatar.color.color, avatar.color.color.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: avatar.symbol.rawValue)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Focus for avatar buttons: a white ring and a slight enlargement, like the cards.
struct AvatarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AvatarButtonBody(configuration: configuration)
    }
}

private struct AvatarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (isFocused ? Theme.Motion.focusScale : (configuration.isPressed ? 0.96 : 1)))
            .animation(Theme.Motion.focus, value: isFocused)
    }
}
