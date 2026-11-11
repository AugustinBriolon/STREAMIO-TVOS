import SwiftUI

/// Placeholder for a `ShelfRow` that is still loading. Same geometry as the real row, so nothing jumps
/// when the content arrives. Static on purpose: a shimmer loops for the whole load and costs frames
/// on the Apple TV HD.
struct ShelfSkeleton: View {
    var cardSize = Theme.Card.posterSize

    private static let titleSize = CGSize(width: 320, height: 30)
    private static let cardCount = 9

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SkeletonBlock(size: Self.titleSize, radius: Theme.Radius.badge)
            // An overlay, so the over-wide row of cards never widens the page (it is clipped instead).
            Color.clear
                .frame(height: cardSize.height)
                .overlay(alignment: .leading) {
                    HStack(spacing: Theme.Spacing.cardGap) {
                        ForEach(0..<Self.cardCount, id: \.self) { _ in
                            SkeletonBlock(size: cardSize, radius: Theme.Radius.card)
                        }
                    }
                }
            .padding(.top, Theme.Spacing.l + Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl + Theme.Spacing.xxs)
        }
        .padding(.leading, Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Placeholder for a catalog page (billboard text block, then shelves).
struct CatalogSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Spacer(minLength: 0)
                SkeletonBlock(size: CGSize(width: 520, height: 120), radius: Theme.Radius.card)
                SkeletonBlock(size: CGSize(width: 420, height: 24), radius: Theme.Radius.badge)
                SkeletonBlock(size: CGSize(width: Theme.Layout.synopsisWidth, height: 84), radius: Theme.Radius.badge)
                SkeletonBlock(size: CGSize(width: 560, height: 62), radius: Theme.Radius.button)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.billboardHeight, alignment: .bottomLeading)

            ShelfSkeleton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement()
        .accessibilityLabel("Chargement du catalogue")
    }
}

private struct SkeletonBlock: View {
    let size: CGSize
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.Palette.surface)
            .frame(width: size.width, height: size.height)
    }
}
