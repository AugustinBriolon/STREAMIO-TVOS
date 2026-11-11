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
/// Loaded through `ImagePipeline` like every other image: decoded off the main thread at display
/// size and kept in the memory cache, so a logo seen once appears at once the next time.
struct LogoTitle: View {
    let name: String
    let logoURL: URL?
    var maxSize = Theme.Layout.logoSize
    var font = Theme.Typography.billboardTitle

    @State private var logo: UIImage?
    @State private var failed = false

    private var maxPixel: CGFloat { maxSize.width * Theme.pixelScale }
    private var cached: UIImage? { logoURL.flatMap { ImagePipeline.shared.cached($0, maxPixel: maxPixel) } }

    var body: some View {
        Group {
            if let logo = logo ?? cached {
                Image(uiImage: logo).resizable().scaledToFit()
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height, alignment: .bottomLeading)
                    // Thin light halo keeps dark logos readable on dark backdrops.
                    .shadow(color: .white.opacity(0.35), radius: 1)
                    .shadow(color: .black.opacity(0.6), radius: 12)
            } else if logoURL != nil, !failed {
                // Holds the logo's place while it loads, so the text below does not jump.
                Color.clear.frame(width: maxSize.width, height: maxSize.height / 2)
            } else {
                Text(name)
                    .font(font)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.7), radius: 10, y: 4)
            }
        }
        .accessibilityLabel(name)
        .task(id: logoURL) { await load() }
    }

    private func load() async {
        logo = nil
        failed = false
        guard let logoURL, cached == nil else { return }
        let loaded = await ImagePipeline.shared.image(for: logoURL, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(Theme.Motion.fade) { logo = loaded }
        } else {
            failed = true
        }
    }
}
