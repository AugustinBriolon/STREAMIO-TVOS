import SwiftUI

/// Full-screen player: libVLC video surface with a 10-foot transport overlay.
/// Remote: click = play/pause, left/right = -10/+10 s, down = track buttons, Menu = hide controls then close.
struct PlayerView: View {
    let session: PlaybackSession
    @State private var controller: PlayerController
    @State private var controlsVisible = true
    @State private var lastInteraction = Date()
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case surface, tracks }
    private var surfaceFocused: Bool { focus == .surface || focus == nil }

    init(session: PlaybackSession, playback: PlaybackCoordinator) {
        self.session = session
        _controller = State(initialValue: PlayerController(playback: playback))
    }

    private var engine: VLCPlayerEngine { controller.engine }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(view: engine.videoView).ignoresSafeArea()

            Button(action: { engine.togglePlayPause(); interact() }) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(SurfaceButtonStyle())
            .focused($focus, equals: .surface)
            .onMoveCommand(perform: handleMove)
            .ignoresSafeArea()

            if engine.phase == .opening {
                StateView(kind: .loading(controller.candidateIndex == 0
                    ? "Chargement de la vidéo…"
                    : "Source illisible, essai de la source \(controller.candidateIndex + 1)…"))
            }
            if controlsVisible || engine.phase == .paused {
                controls.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .onAppear {
            controller.load(session)
            focus = .surface
        }
        .onChange(of: session.id) { controller.load(session) }
        .onPlayPauseCommand { engine.togglePlayPause(); interact() }
        .onExitCommand {
            if controlsVisible && !surfaceFocused {
                controlsVisible = false
                focus = .surface
            } else {
                controller.close()
            }
        }
        .task(id: lastInteraction) {
            try? await Task.sleep(for: .seconds(5))
            if engine.phase == .playing && surfaceFocused { controlsVisible = false }
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: engine.seek(by: -10)
        case .right: engine.seek(by: 10)
        // The surface covers the whole screen, so the focus engine never finds the buttons "below" it.
        case .down where controlsVisible: focus = .tracks
        default: break
        }
        interact()
    }

    private func interact() {
        controlsVisible = true
        lastInteraction = Date()
    }

    // MARK: Overlay

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(session.item.name).font(Theme.Typography.rowTitle)
                if let subtitle = session.subtitle {
                    Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: engine.phase == .paused ? "play.fill" : "pause.fill").font(.system(size: 28))
                ProgressBar(fraction: engine.duration > 0 ? engine.currentTime / engine.duration : 0)
                Text("-" + Self.format(max(engine.duration - engine.currentTime, 0)))
                    .font(Theme.Typography.meta)
            }
            HStack(spacing: Theme.Spacing.m) {
                trackMenu("Audio", symbol: "speaker.wave.2", tracks: engine.audioTracks,
                          selected: engine.selectedAudioID, allowsOff: false) { engine.selectAudio($0) }
                    .focused($focus, equals: .tracks)
                trackMenu("Sous-titres", symbol: "captions.bubble", tracks: engine.subtitleTracks,
                          selected: engine.selectedSubtitleID, allowsOff: true) { engine.selectSubtitle($0) }
                if controller.showsNextEpisode, let next = controller.nextEpisode {
                    Button("Épisode suivant · \(next.code)", systemImage: "forward.end.fill") { controller.playNextEpisode() }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                }
            }
            .focusSection()
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.xl)
        .background {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func trackMenu(_ title: String, symbol: String, tracks: [MediaTrack], selected: Int32,
                           allowsOff: Bool, select: @escaping (Int32) -> Void) -> some View {
        Menu {
            if allowsOff {
                Button { select(-1) } label: { trackLabel("Désactivés", isSelected: selected < 0) }
            }
            ForEach(tracks.filter { $0.id >= 0 }) { track in
                Button { select(track.id) } label: { trackLabel(track.name, isSelected: track.id == selected) }
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(tracks.filter { $0.id >= 0 }.isEmpty)
    }

    @ViewBuilder
    private func trackLabel(_ name: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// The invisible full-screen button that receives remote clicks; it draws nothing on focus.
private struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
