import SwiftUI

/// Full-bleed hero: backdrop, logo, meta line, synopsis and the three primary actions.
struct BillboardView: View {
    let item: MediaItem
    let playTitle: String
    let isInMyList: Bool
    let onPlay: () -> Void
    let onToggleMyList: () -> Void
    let playFocus: FocusState<String?>.Binding
    /// Called when any billboard button gets focus, so the page backdrop returns to this title.
    let onFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            LogoTitle(name: item.name, logoURL: item.logoURL)
            MetaLine(rating: item.displayRating, components: item.metaComponents)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button(playTitle, systemImage: "play.fill", action: onPlay)
                    .buttonStyle(PillButtonStyle(kind: .primary, onFocus: onFocus))
                    .focused(playFocus, equals: "billboard")
                NavigationLink(value: item) {
                    Label("Plus d'infos", systemImage: "info.circle")
                }
                .buttonStyle(PillButtonStyle(onFocus: onFocus))
                MyListButton(isInMyList: isInMyList, action: onToggleMyList, onFocus: onFocus)
            }
            .padding(.top, Theme.Spacing.s)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.billboardHeight, alignment: .bottomLeading)
        .focusSection()
    }
}

/// "+ Ma liste" / "✓ Ma liste" toggle.
struct MyListButton: View {
    let isInMyList: Bool
    let action: () -> Void
    var onFocus: (() -> Void)?

    var body: some View {
        Button(action: action) {
            Label("Ma liste", systemImage: isInMyList ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PillButtonStyle(onFocus: onFocus))
        .accessibilityValue(isInMyList ? "Ajouté" : "Non ajouté")
    }
}
