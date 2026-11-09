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
///
/// Cheap by construction (this was the biggest frame-drop source when it cross-faded two full
/// scrims-and-all layers): the previous image stays opaque underneath, the new one fades in on top
/// as the only blended layer, and the scrims are baked into the images. A new image is only shown
/// once decoded, so the fade never starts on a blank layer.
struct DynamicBackdrop: View {
    /// The backdrop reads the model itself, so a focus change re-renders only this view and not the
    /// whole page (rebuilding every shelf made each change a visible hitch on the Apple TV HD).
    let model: BackdropModel
    /// Shown while nothing is focused (the page's featured title).
    var fallback: MediaItem?

    private var item: MediaItem? { model.item ?? fallback }

    @State private var base: UIImage?
    @State private var top: UIImage?
    @State private var topOpacity = 0.0
    @State private var loading: Task<Void, Never>?

    /// Scrims are baked into the image (see `ImagePipeline.backdrop`).
    private static let dimming: CGFloat = 0.3

    var body: some View {
        ZStack {
            Theme.Palette.canvas
            if let base { Image(uiImage: base).resizable().scaledToFill() }
            if let top { Image(uiImage: top).resizable().scaledToFill().opacity(topOpacity) }
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: item?.backgroundURL) { await show(item?.backgroundURL) }
    }

    private func show(_ url: URL?) async {
        guard let url else {
            base = nil
            top = nil
            return
        }
        guard let image = await ImagePipeline.shared.backdrop(for: url, dimming: Self.dimming), !Task.isCancelled else { return }
        guard base != nil else {
            base = image
            return
        }
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
