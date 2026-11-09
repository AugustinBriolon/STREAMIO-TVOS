import SwiftUI

/// Remote image filling its frame, loaded and downsampled off the main thread (see `ImagePipeline`).
struct RemoteImage: View {
    let url: URL?
    /// Longest side, in pixels, the image is decoded to. Callers pass the displayed size times the screen scale.
    var maxPixel: CGFloat = 800
    var placeholderSymbol = "film"
    /// Backdrops draw their own base layer: no placeholder tint while loading.
    var showsPlaceholder = true

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if showsPlaceholder { Theme.Palette.surface }
            if let image = image ?? cachedImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed, showsPlaceholder {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .task(id: url) { await load() }
    }

    private var cachedImage: UIImage? {
        url.flatMap { ImagePipeline.shared.cached($0, maxPixel: maxPixel) }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if cachedImage != nil { return }
        failed = false
        let loaded = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(Theme.Motion.fade) { image = loaded }
        } else {
            failed = true
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

/// Scrims drawn over a backdrop: bottom and leading gradients keep text and rows readable.
struct BackdropScrim: View {
    /// Extra black layer so cards drawn over the backdrop stay readable (list pages).
    var dimming: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [.clear, Theme.Palette.canvas.opacity(0.7), Theme.Palette.canvas],
                           startPoint: .center, endPoint: .bottom)
            LinearGradient(colors: [Theme.Palette.canvas.opacity(0.9), .clear],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.65, y: 0.5))
            Color.black.opacity(dimming)
        }
        .allowsHitTesting(false)
    }
}

/// Full-bleed backdrop with the scrims that keep text readable.
struct BackdropView: View {
    let url: URL?
    var dimming: Double = 0

    var body: some View {
        RemoteImage(url: url, maxPixel: 1280, showsPlaceholder: false)
            .overlay { BackdropScrim(dimming: dimming) }
            .clipped()
            .accessibilityHidden(true)
    }
}
