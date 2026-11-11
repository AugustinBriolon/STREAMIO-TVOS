import SwiftUI

/// Shown between the click on "Lecture" and the player opening: the title's own artwork instead of a
/// black veil, so the wait reads as the start of playback and not as an interruption.
struct ResolvingView: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BakedBackdrop(url: item.backgroundURL, dimming: 0.35)
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                LogoTitle(name: item.name, logoURL: item.logoURL)
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView()
                    Text("Recherche du meilleur flux…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter + Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl * 2)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }
}
