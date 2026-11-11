import SwiftUI

/// Badge discret et élégant pour marquer les sorties cinéma et les lauréats de palmarès.
struct DiscoveryBadge: View {
    let text: String
    var isAward: Bool = false
    var isCinema: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if isCinema {
                Circle()
                    .fill(Color(red: 235 / 255, green: 87 / 255, blue: 87 / 255))
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .font(Theme.Typography.caption)
                .fontWeight(.bold)
                .foregroundStyle(isAward ? Color(red: 255 / 255, green: 215 / 255, blue: 0 / 255) : Theme.Palette.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.badge)
                .fill(isAward ? Color.black.opacity(0.75) : Color.black.opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.badge)
                        .strokeBorder(
                            isAward ? Color(red: 255 / 255, green: 215 / 255, blue: 0 / 255).opacity(0.4) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
    }
}

/// Carte poster enrichie d'un badge contextuel (ex: "En salle" ou "Palme d'Or").
struct BadgedPosterCard: View {
    let item: MediaItem
    var badge: String? = nil
    var isAward: Bool = false
    var isCinema: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PosterCard(item: item)
            if let badge {
                DiscoveryBadge(text: badge, isAward: isAward, isCinema: isCinema)
                    .padding(Theme.Spacing.xs)
            }
        }
    }
}
