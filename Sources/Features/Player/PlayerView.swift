import SwiftUI

/// Full-screen player: libVLC video surface with a 10-foot transport overlay.
/// Remote: click = play/pause (or confirm a scrub), left/right = scrub preview (accelerates),
/// circle on the clickpad ring = fast scrub, down = Audio / Sous-titres, Menu = cancel scrub, hide controls, close.
struct PlayerView: View {
    let session: PlaybackSession
    @State private var controller: PlayerController
    @State private var thumbnails = ThumbnailProvider()
    @State private var scrubber = Scrubber()
    @State private var ring: RemoteRingInput?
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

            Button(action: primaryAction) {
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
            if controlsVisible || scrubber.isActive {
                controls.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .onAppear {
            controller.load(session)
            focus = .surface
            ring = RemoteRingInput { radians in jog(radians) }
        }
        .onDisappear { ring?.stop() }
        .onChange(of: session.id) {
            _ = scrubber.cancel()
            controller.load(session)
        }
        .onChange(of: engine.currentURL) { thumbnails.reset(url: engine.currentURL) }
        // Build the preview grid once playback is stable, so it never competes with startup buffering.
        .onChange(of: engine.playedSeconds >= 20) { _, stable in
            if stable { thumbnails.startPrefetch(duration: engine.duration, around: engine.currentTime) }
        }
        .onPlayPauseCommand(perform: primaryAction)
        .onExitCommand(perform: handleExit)
        .task(id: lastInteraction) {
            // A newer interaction cancels this task: it must not hide anything then.
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if engine.phase == .playing && surfaceFocused && !scrubber.isActive { controlsVisible = false }
        }
    }

    // MARK: Remote

    private func primaryAction() {
        if let target = scrubber.commit() {
            engine.seek(to: target)
            engine.play()
        } else {
            engine.togglePlayPause()
        }
        interact()
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .right:
            // Circling the ring also emits arrow moves; the jog already handles that gesture.
            guard ring?.isRotating != true else { return }
            scrub { $0.step(forward: direction == .right, current: engine.currentTime, duration: engine.duration) }
        case .down:
            // A swipe down means "go to the buttons": abandon any seek preview that the same gesture started.
            if scrubber.isActive {
                _ = scrubber.cancel()
                engine.play()
            }
            // The surface covers the whole screen, so the focus engine never finds the buttons "below" it.
            // The buttons may not exist yet (controls hidden): show them first, focus after layout.
            controlsVisible = true
            lastInteraction = Date()
            Task { @MainActor in
                await Task.yield()
                focus = .tracks
            }
        default:
            interact()
        }
    }

    private func jog(_ radians: Double) {
        guard surfaceFocused, engine.duration > 0, engine.phase == .playing || engine.phase == .paused else { return }
        scrub { $0.jog(radians: radians, current: engine.currentTime, duration: engine.duration) }
    }

    private func scrub(_ change: (inout Scrubber) -> Void) {
        guard engine.duration > 0 else { return }
        if !scrubber.isActive {
            engine.pause()
            thumbnails.startPrefetch(duration: engine.duration, around: engine.currentTime)
        }
        change(&scrubber)
        thumbnails.request(time: scrubber.position, duration: engine.duration)
        interact()
    }

    /// Menu peels one layer: cancel a seek, else hide visible controls, else close the player.
    private func handleExit() {
        if scrubber.isActive {
            _ = scrubber.cancel()
            engine.play()
            interact()
        } else if controlsVisible {
            controlsVisible = false
            focus = .surface
        } else {
            controller.close()
        }
    }

    private func interact() {
        controlsVisible = true
        lastInteraction = Date()
    }

    // MARK: Overlay

    private var displayedTime: Double { scrubber.isActive ? scrubber.position : engine.currentTime }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(session.item.name).font(Theme.Typography.rowTitle)
                if let subtitle = session.subtitle {
                    Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            ScrubBar(
                playedFraction: engine.duration > 0 ? engine.currentTime / engine.duration : 0,
                headFraction: engine.duration > 0 ? displayedTime / engine.duration : 0,
                isScrubbing: scrubber.isActive,
                preview: thumbnails.image,
                headLabel: Self.format(displayedTime)
            )
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: engine.phase == .paused && !scrubber.isActive ? "play.fill" : "pause.fill")
                    .font(.system(size: 26))
                Text("\(Self.format(displayedTime)) / \(Self.format(engine.duration))")
                    .font(Theme.Typography.meta)
                Spacer()
                Text("-" + Self.format(max(engine.duration - displayedTime, 0)))
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
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
            .opacity(scrubber.isActive ? 0 : 1)
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
        let total = Int(max(seconds, 0))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// Progress track with a scrub head; while scrubbing, a frame preview and timestamp float above the head.
private struct ScrubBar: View {
    let playedFraction: Double
    let headFraction: Double
    let isScrubbing: Bool
    let preview: CGImage?
    let headLabel: String

    private static let previewSize = CGSize(width: 384, height: 216)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let headX = width * min(max(headFraction, 0), 1)
            ZStack(alignment: .bottomLeading) {
                Capsule().fill(Theme.Palette.track).frame(height: 6)
                Capsule().fill(Theme.Palette.accent)
                    .frame(width: width * min(max(playedFraction, 0), 1), height: 6)
                Circle().fill(Theme.Palette.accent)
                    .frame(width: isScrubbing ? 26 : 16, height: isScrubbing ? 26 : 16)
                    .offset(x: headX - (isScrubbing ? 13 : 8), y: isScrubbing ? 10 : 5)
                if isScrubbing {
                    previewCard
                        .offset(x: min(max(headX - Self.previewSize.width / 2, 0), width - Self.previewSize.width),
                                y: -30)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: isScrubbing ? Self.previewSize.height + 90 : 26)
        .animation(Theme.Motion.focus, value: isScrubbing)
    }

    private var previewCard: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Color.black
                if let preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(.white, lineWidth: 3) }
            Text(headLabel)
                .font(Theme.Typography.rowTitle.monospacedDigit())
                .shadow(color: .black, radius: 6)
        }
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
