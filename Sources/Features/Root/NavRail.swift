import SwiftUI

/// Left navigation rail without any background: icons float over the content in the screen margin and
/// their names slide in while the rail has focus. (The system sidebar of tvOS 26 draws a glass panel and a
/// disc behind every icon and offers no way to remove them: ADR 0010.)
struct NavRail: View {
    let selected: AppTab
    let focus: FocusState<AppTab?>.Binding
    let onSelect: (AppTab) -> Void

    private var expanded: Bool { focus.wrappedValue != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { onSelect(tab) } label: {
                    RailLabel(tab: tab, expanded: expanded)
                }
                .buttonStyle(RailItemStyle(isSelected: tab == selected))
                .focused(focus, equals: tab)
                .accessibilityLabel(tab.title)
            }
        }
        .focusSection()
        .animation(Theme.Motion.panel, value: expanded)
    }
}

private struct RailLabel: View {
    let tab: AppTab
    let expanded: Bool

    /// Names take no width while collapsed, so a rail item never overlaps the first card of a row:
    /// the focus engine would otherwise treat it as a candidate for up/down moves in the content.
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: tab.symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 44, height: 44)
            Text(tab.title)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
                .frame(width: expanded ? 220 : 0, alignment: .leading)
                .opacity(expanded ? 1 : 0)
                .clipped()
        }
    }
}

/// No background of any kind. Focus: full white and a slight enlargement. Selected: white plus a red mark.
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

    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(isFocused ? 1 : (isSelected ? 0.95 : 0.5)))
            .shadow(color: .black.opacity(0.6), radius: 6) // legibility over bright artwork, not a background
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.accent)
                    .frame(width: 4, height: 26)
                    .offset(x: -14)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(reduceMotion ? 1 : (isFocused ? 1.08 : (configuration.isPressed ? 0.96 : 1)), anchor: .leading)
            .animation(Theme.Motion.focus, value: isFocused)
    }
}
