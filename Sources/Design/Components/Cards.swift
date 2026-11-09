import SwiftUI

/// 2:3 poster. The title is only exposed to accessibility: posters carry their own title art.
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        RemoteImage(url: item.posterURL)
            .frame(width: Theme.Card.posterSize.width, height: Theme.Card.posterSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityLabel(item.name)
    }
}

/// 16:9 backdrop with title, subtitle and optional progress — used for "Reprendre la lecture".
struct LandscapeCard: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    var progress: Double?
    var size = Theme.Card.landscapeSize

    var body: some View {
        RemoteImage(url: imageURL)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title).font(Theme.Typography.cardTitle).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    }
                    if let progress {
                        ProgressBar(fraction: progress).padding(.top, Theme.Spacing.xxs)
                    }
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)
    }
}

/// Top 10 tile: huge outlined rank number with the poster overlapping it.
struct Top10Card: View {
    let rank: Int
    let item: MediaItem

    var body: some View {
        HStack(alignment: .bottom, spacing: -36) {
            Text("\(rank)")
                .font(Theme.Typography.rank)
                .foregroundStyle(Theme.Palette.canvas)
                .shadow(color: Theme.Palette.textSecondary, radius: 0, x: 2, y: 2)
                .shadow(color: Theme.Palette.textSecondary, radius: 0, x: -2, y: -2)
                .shadow(color: Theme.Palette.textSecondary, radius: 0, x: 2, y: -2)
                .shadow(color: Theme.Palette.textSecondary, radius: 0, x: -2, y: 2)
                .offset(y: 34)
                .accessibilityHidden(true)
            PosterCard(item: item)
        }
        .accessibilityLabel("Numéro \(rank) : \(item.name)")
    }
}
