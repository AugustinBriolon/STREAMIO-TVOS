import Observation
import SwiftUI

/// Tracks which title the user is looking at on a list page, so the page background can follow it.
/// The change is debounced: scrolling quickly across a row must not load an image per card.
@MainActor
@Observable
final class BackdropModel {
    private(set) var item: MediaItem?

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(delay: Duration = .milliseconds(250)) {
        self.delay = delay
    }

    /// Focus moved to `item`; `nil` means "back to the page's default title".
    func focus(_ item: MediaItem?) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.item = item
        }
    }

    /// Waits for the last `focus` call to apply (tests).
    func settle() async {
        await pending?.value
    }
}

/// Full-screen page background that follows the focused title.
/// The backdrop reads the model itself, so a focus change re-renders only this view and not the
/// whole page (rebuilding every shelf made each change a visible hitch on the Apple TV HD).
struct DynamicBackdrop: View {
    let model: BackdropModel
    /// Shown while nothing is focused (the page's featured title).
    var fallback: MediaItem?

    var body: some View {
        BakedBackdrop(url: (model.item ?? fallback)?.backgroundURL, dimming: 0.3)
            .ignoresSafeArea()
    }
}

/// A backdrop image with the page scrims baked in (see `ImagePipeline.backdrop`), cross-fading when
/// `url` changes.
///
/// Cheap by construction (cross-fading two full scrims-and-all layers was the biggest frame-drop
/// source): the previous image stays opaque underneath, the new one fades in on top as the only
/// blended layer. A new image is only shown once decoded, so the fade never starts on a blank layer.
/// Give it a fixed frame: sized by content that grows while loading, the picture would re-crop.
struct BakedBackdrop: View {
    let url: URL?
    var dimming: CGFloat = 0

    @State private var base: UIImage?
    @State private var top: UIImage?
    @State private var topOpacity = 0.0

    /// Already composed (page visited before): shown at once, without a fade from the canvas.
    private var cached: UIImage? {
        url.flatMap { ImagePipeline.shared.cachedBackdrop($0, dimming: dimming) }
    }

    var body: some View {
        Theme.Palette.canvas
            .overlay {
                if let base = base ?? cached { Image(uiImage: base).resizable().scaledToFill() }
            }
            .overlay {
                if let top { Image(uiImage: top).resizable().scaledToFill().opacity(topOpacity) }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) { await show(url) }
    }

    private func show(_ url: URL?) async {
        guard let url else {
            base = nil
            top = nil
            return
        }
        if base == nil, let cached {
            base = cached
            return
        }
        guard let image = await ImagePipeline.shared.backdrop(for: url, dimming: dimming), !Task.isCancelled else { return }
        // Settle a fade that was still running so we never stack more than two layers.
        if let top { base = top }
        top = image
        topOpacity = 0
        withAnimation(Theme.Motion.fade) {
            topOpacity = 1
        } completion: {
            if top === image {
                base = image
                top = nil
            }
        }
    }
}
