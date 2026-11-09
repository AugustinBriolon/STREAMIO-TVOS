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

/// Full-screen page background that cross-fades to the backdrop of `item`.
struct DynamicBackdrop: View {
    let item: MediaItem?

    var body: some View {
        ZStack {
            Theme.Palette.canvas
            if let item {
                BackdropView(url: item.backgroundURL, dimming: 0.3)
                    .id(item.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: item?.id)
        .ignoresSafeArea()
    }
}
