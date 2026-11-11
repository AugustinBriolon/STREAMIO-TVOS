import SwiftUI

/// Left navigation rail designed for tvOS: compact floating icon badges that reveal titles
/// when expanded, with native Apple TV focus mechanics, 48x48 icon-anchored highlights,
/// and local boundary resistance.
struct NavRail: View {
    let selected: AppTab
    let profileName: String
    let profileAvatar: ProfileAvatar?
    let isAtRoot: (AppTab) -> Bool
    let focus: FocusState<AppTab?>.Binding
    let onSelect: (AppTab) -> Void
    var onExitToPage: (() -> Void)? = nil

    private var expanded: Bool { focus.wrappedValue != nil }
    @State private var bounceOffset: CGFloat = 0
    @Namespace private var railNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        selected: AppTab,
        profileName: String,
        profileAvatar: ProfileAvatar? = nil,
        isAtRoot: @escaping (AppTab) -> Bool = { _ in true },
        focus: FocusState<AppTab?>.Binding,
        onSelect: @escaping (AppTab) -> Void,
        onExitToPage: (() -> Void)? = nil
    ) {
        self.selected = selected
        self.profileName = profileName
        self.profileAvatar = profileAvatar
        self.isAtRoot = isAtRoot
        self.focus = focus
        self.onSelect = onSelect
        self.onExitToPage = onExitToPage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 32)

            // Section 1: Main media categories
            tabButton(for: .home)
            tabButton(for: .movies)
            tabButton(for: .series)
            tabButton(for: .myList)

            // Hairline breathing separator (constant 36pt width, never overflows)
            Rectangle()
                .fill(Color.white.opacity(expanded ? 0.12 : 0.06))
                .frame(width: 36, height: 1)
                .padding(.vertical, 4)
                .padding(.leading, 6)

            // Section 2: Utilities & Discovery
            tabButton(for: .search)
            tabButton(for: .settings)

            // Hairline breathing separator
            Rectangle()
                .fill(Color.white.opacity(expanded ? 0.12 : 0.06))
                .frame(width: 36, height: 1)
                .padding(.vertical, 4)
                .padding(.leading, 6)

            // Section 3: Profile Identity Anchor
            tabButton(for: .profiles)

            Spacer(minLength: 32)
        }
        .offset(y: bounceOffset)
        .frame(maxHeight: .infinity)
        .focusSection()
        .animation(Theme.Motion.panel, value: expanded)
    }

    @ViewBuilder
    private func tabButton(for tab: AppTab) -> some View {
        let isCurrent = tab == selected
        let atRoot = isAtRoot(tab)
        let isRootActive = isCurrent && atRoot
        let isSubpageActive = isCurrent && !atRoot

        Button {
            onSelect(tab)
        } label: {
            RailIconBadge(
                tab: tab,
                title: tab == .profiles ? profileName : tab.title,
                avatar: tab == .profiles ? profileAvatar : nil,
                isRootActive: isRootActive,
                isSubpageActive: isSubpageActive,
                expanded: expanded,
                railNamespace: railNamespace
            )
        }
        .buttonStyle(RailIconButtonStyle())
        .focused(focus, equals: tab)
        // Local Apple HIG boundary handling: clamp terminal items without global side-effects
        .onMoveCommand { direction in
            if direction == .down && tab == .profiles {
                triggerBounce(offset: 4)
            } else if direction == .up && tab == .home {
                triggerBounce(offset: -4)
            }
        }
        .accessibilityLabel(tab == .profiles ? profileName : (isSubpageActive ? "Retour à \(tab.title)" : tab.title))
        .accessibilityAddTraits(isRootActive ? .isSelected : [])
    }

    private func triggerBounce(offset: CGFloat) {
        guard !reduceMotion else { return }
        bounceOffset = offset
        withAnimation(Animation.spring(duration: 0.22, bounce: 0.28)) {
            bounceOffset = 0
        }
    }
}

// MARK: - Icon-Anchored Badge (Strict 48x48 geometry, title projected as non-intrusive overlay)

private struct RailIconBadge: View {
    let tab: AppTab
    let title: String
    let avatar: ProfileAvatar?
    let isRootActive: Bool
    let isSubpageActive: Bool
    let expanded: Bool
    let railNamespace: Namespace.ID
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            // Optical resting highlight: strictly bounded to the 48x48 icon disc
            if isRootActive {
                Circle()
                    .fill(Color.white.opacity(isFocused ? 0.22 : 0.12))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(isFocused ? 0.38 : 0.20), lineWidth: 1.2)
                    }
            } else if isFocused {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1.2)
                    }
            }

            // Core glyph or user profile picture
            if tab == .profiles, let avatar {
                ProfileAvatarView(avatar: avatar, size: 30)
            } else {
                Image(systemName: tab.symbol)
                    .symbolVariant(isRootActive ? .fill : .none)
                    .font(.system(size: 24, weight: isRootActive ? .bold : .medium))
                    .foregroundStyle(isFocused ? .white : (isRootActive ? .white : .white.opacity(0.48)))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 48, height: 48)
        .overlay(alignment: .leading) {
            // Projected title: never modifies the button's layout footprint
            if expanded {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 26, weight: isRootActive ? .bold : .medium))
                        .foregroundStyle(isFocused ? .white : (isRootActive ? .white : .white.opacity(0.60)))
                        .lineLimit(1)
                        .fixedSize()

                    if isSubpageActive {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .bold))
                            Text("Retour")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    }
                }
                .offset(x: 58)
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    )
                )
            }
        }
    }
}

// MARK: - Button Style (Centric scale, no wide background spill)

private struct RailIconButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                Theme.Motion.scale(
                    focused: isFocused,
                    pressed: configuration.isPressed,
                    focusScale: 1.08,
                    reduceMotion: reduceMotion
                ),
                anchor: .center
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
