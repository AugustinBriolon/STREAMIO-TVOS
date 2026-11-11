import SwiftUI

/// Carte d'affiche pour les rangées "Films primés" / "Séries primées" de l'accueil et des onglets.
/// Conforme au focus ring exclusif sur l'affiche : titre et distinction principale restent lisibles en dessous sans déborder.
struct AwardedMediaCard: View {
    let entry: AwardedMediaEntry
    var size: CGSize = Theme.Card.posterSize
    var onFocus: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            NavigationLink(value: entry.item) {
                ZStack(alignment: .topTrailing) {
                    Theme.Palette.surface

                    RemoteImage(url: entry.item.posterURL, maxPixel: size.height * Theme.pixelScale)
                        .frame(width: size.width, height: size.height)

                    Circle()
                        .fill(Theme.Palette.rating)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: Color.black.opacity(0.40), radius: 5, y: 2)
                        .padding(10)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
            }
            .buttonStyle(CardFocusStyle(onFocus: onFocus))
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.item.name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)

                Text("\(entry.primaryDistinction.shortCeremonyLabel) \(String(entry.primaryDistinction.year))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: size.width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.item.name), \(entry.primaryDistinction.shortCeremonyLabel) \(entry.primaryDistinction.year)")
    }
}
