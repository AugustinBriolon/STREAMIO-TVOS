import SwiftUI

/// When the full-screen player closes, tvOS hands focus to the sidebar. This puts it back on the
/// control that started playback, like a streaming app returning you to the title you left.
struct PlaybackFocusRestorer: ViewModifier {
    @Environment(PlaybackCoordinator.self) private var playback
    let focus: FocusState<String?>.Binding
    let origin: String?

    func body(content: Content) -> some View {
        content.onChange(of: playback.session == nil) { _, closed in
            guard closed, let origin else { return }
            Task {
                // Wait for the cover dismissal so the focus engine accepts the request.
                try? await Task.sleep(for: .milliseconds(250))
                focus.wrappedValue = origin
            }
        }
    }
}

extension View {
    func restoresFocusAfterPlayback(_ focus: FocusState<String?>.Binding, to origin: String?) -> some View {
        modifier(PlaybackFocusRestorer(focus: focus, origin: origin))
    }
}
