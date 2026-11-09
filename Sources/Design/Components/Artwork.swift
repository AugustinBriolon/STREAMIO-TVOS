import SwiftUI

/// Remote image filling its frame, with a neutral placeholder while loading or on failure.
struct RemoteImage: View {
    let url: URL?
    var placeholderSymbol = "film"

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.Palette.surface
                    if case .failure = phase {
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }
}

/// Title artwork (logo) with a text fallback when the logo is missing.
struct LogoTitle: View {
    let name: String
    let logoURL: URL?
    var maxSize = Theme.Layout.logoSize
    var font = Theme.Typography.billboardTitle

    var body: some View {
        AsyncImage(url: logoURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height, alignment: .bottomLeading)
                    // Thin light halo keeps dark logos readable on dark backdrops.
                    .shadow(color: .white.opacity(0.35), radius: 1)
                    .shadow(color: .black.opacity(0.6), radius: 12)
            } else if case .empty = phase, logoURL != nil {
                Color.clear.frame(width: maxSize.width, height: maxSize.height / 2)
            } else {
                Text(name)
                    .font(font)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.7), radius: 10, y: 4)
            }
        }
        .accessibilityLabel(name)
    }
}

/// Full-bleed backdrop with the bottom and leading scrims that keep text readable.
struct BackdropView: View {
    let url: URL?

    var body: some View {
        RemoteImage(url: url)
            .overlay {
                LinearGradient(colors: [.clear, Theme.Palette.canvas.opacity(0.7), Theme.Palette.canvas],
                               startPoint: .center, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(colors: [Theme.Palette.canvas.opacity(0.9), .clear],
                               startPoint: .leading, endPoint: UnitPoint(x: 0.65, y: 0.5))
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
