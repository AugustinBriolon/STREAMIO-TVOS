import SwiftUI

/// Tuile de marque interactive en verre dépoli pour les Plateformes de streaming et Studios.
/// Affiche uniquement le logo officiel de la plateforme, centré et sublimé sans texte parasite.
struct BrandHubCard: View {
    let hub: BrandHub
    var size = Theme.Card.brandHubSize

    private var accentColor: Color {
        Color(hex: hub.accentColorHex)
    }

    var body: some View {
        ZStack {
            // Fond en verre sombre avec halo lumineux subtil de la couleur de la marque
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.85))

            RadialGradient(
                colors: [
                    accentColor.opacity(0.28),
                    accentColor.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: size.width * 0.75
            )

            // Logo officiel centré
            if let logoURL = hub.logoURL {
                if hub.category == .platform {
                    // Les plateformes ont une icône carrée/squircle officielle 332x332
                    RemoteImage(url: logoURL, maxPixel: 240, showsPlaceholder: false, contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
                } else {
                    // Studios / networks: logos TMDB souvent larges ou noirs sur alpha — plateau clair + fit.
                    RemoteImage(url: logoURL, maxPixel: 400, showsPlaceholder: false, contentMode: .fit)
                        .padding(Theme.Spacing.s)
                        .frame(maxWidth: size.width - Theme.Spacing.l, maxHeight: size.height - Theme.Spacing.l)
                        .padding(Theme.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
                }
            } else {
                // Fallback avec symbole SF Symbol si absence d'image
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: hub.systemSymbol)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(hub.name)
                        .font(Theme.Typography.cardTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hub.name)
    }
}
