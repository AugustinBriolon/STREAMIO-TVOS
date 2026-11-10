import SwiftUI

/// Left navigation rail without any background: icons float over the content in the screen margin and
/// their names slide in while the rail has focus. (The system sidebar of tvOS 26 draws a glass panel and a
/// disc behind every icon and offers no way to remove them: ADR 0010.)
///
/// States are told apart by shape, weight and brightness, never by a box:
/// - selected: filled icon, bold white name, red mark;
/// - focused: white, slightly enlarged (the cursor);
/// - other: outline icon, medium weight, dimmed.
struct NavRail: View {
    let selected: AppTab
    /// The Profils entry is named after the active profile.
    let profileName: String
    let focus: FocusState<AppTab?>.Binding
    let onSelect: (AppTab) -> Void

    private var expanded: Bool { focus.wrappedValue != nil }

    var body: some View {
        // The section spans the full height, so moving left from a card at any height lands here and the
        // focus engine picks the nearest item (a column of six icons alone missed most rows).
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button { onSelect(tab) } label: {
                        RailLabel(tab: tab, title: tab == .profiles ? profileName : tab.title, isSelected: tab == selected, expanded: expanded)
                    }
                    .buttonStyle(RailItemStyle(isSelected: tab == selected))
                    .focused(focus, equals: tab)
                    .accessibilityLabel(tab == .profiles ? profileName : tab.title)
                    .accessibilityAddTraits(tab == selected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .focusSection()
        .animation(Theme.Motion.panel, value: expanded)
    }
}

private struct RailLabel: View {
    let tab: AppTab
    let title: String
    let isSelected: Bool
    let expanded: Bool

    /// Names take no width while collapsed, so a rail item never overlaps the first card of a row:
    /// the focus engine would otherwise treat it as a candidate for up/down moves in the content.
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: tab.symbol)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 30, weight: isSelected ? .bold : .regular))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
            Text(title)
                .font(.system(size: 28, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .frame(width: expanded ? 220 : 0, alignment: .leading)
                .opacity(expanded ? 1 : 0)
                .clipped()
        }
    }
}

/// No background of any kind.
private struct RailItemStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RailItemBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct RailItemBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Brightness ladder: cursor > selected > others. Others stay clearly dimmer than the selected one.
    private var brightness: Double {
        if isFocused { return 1 }
        return isSelected ? 1 : 0.42
    }

    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(brightness))
            .shadow(color: .black.opacity(0.6), radius: 6) // legibility over bright artwork, not a background
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.accent)
                    .frame(width: 5, height: 30)
                    .scaleEffect(y: isSelected ? 1 : 0.2)
                    .offset(x: -16)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(reduceMotion ? 1 : (isFocused ? 1.1 : (configuration.isPressed ? 0.96 : 1)), anchor: .leading)
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.focus, value: isSelected)
    }
}
