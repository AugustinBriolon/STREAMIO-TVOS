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
    @State private var panel: TrackColumn?
    @FocusState private var focus: PlayerFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let controlsBandHeight: CGFloat = 170
    /// Strict: while the track panel or a button has focus the player must neither hide the controls
    /// nor react to remote touches.
    private var surfaceFocused: Bool { focus == .surface }
    private var isOverlayVisible: Bool { controlsVisible || scrubber.isActive }

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
            .disabled(panel != nil)
            .onMoveCommand(perform: handleMove)
            // Without this the full-screen surface also sits "below" the buttons and steals their focus.
            .padding(.bottom, isOverlayVisible ? Self.controlsBandHeight : 0)
            .transaction { $0.animation = nil }
            .ignoresSafeArea()

            if engine.phase == .opening {
                StateView(kind: .loading(controller.candidateIndex == 0
                    ? "Chargement de la vidéo…"
                    : "Source illisible, essai de la source \(controller.candidateIndex + 1)…"))
            }

            // Top HUD: title & metadata sliding smoothly to/from top edge
            ZStack(alignment: .topLeading) {
                if isOverlayVisible {
                    topOverlay
                        .transition(topTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(isOverlayVisible)

            // Bottom HUD: scrub bar, timestamp & transport buttons sliding to/from bottom edge
            ZStack(alignment: .bottomLeading) {
                if isOverlayVisible {
                    bottomOverlay
                        .transition(bottomTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(isOverlayVisible)

            if panel != nil {
                TrackPanelView(engine: engine, focus: $focus)
                    .padding(.leading, Theme.Spacing.gutter)
                    .padding(.bottom, Self.controlsBandHeight + Theme.Spacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.panel, value: panel)
        .animation(overlayAnimation, value: isOverlayVisible)
        .onAppear {
            controller.load(session)
            focus = .surface
            ring = RemoteRingInput { radians in jog(radians) }
        }
        .onDisappear {
            ring?.stop()
            RemoteTiltModel.shared.start()
        }
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
                focus = .audioButton
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
        if panel != nil {
            closePanel()
        } else if scrubber.isActive {
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

    private func openPanel(_ column: TrackColumn) {
        panel = column
        controlsVisible = true
        let tracks = column == .audio ? engine.audioTracks : engine.subtitleTracks
        let selected = column == .audio ? engine.selectedAudioID : engine.selectedSubtitleID
        // Subtitles can be off (-1); audio falls back to its first track.
        let target = tracks.contains { $0.id == selected } || (column == .subtitles && selected < 0)
            ? selected : tracks.first { $0.id >= 0 }?.id ?? -1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focus = column == .audio ? .audioTrack(target) : .subtitleTrack(target)
        }
    }

    private func closePanel() {
        let back: PlayerFocus = panel == .subtitles ? .subtitleButton : .audioButton
        panel = nil
        focus = back
    }

    private func interact() {
        controlsVisible = true
        lastInteraction = Date()
    }

    // MARK: Overlay

    private var displayedTime: Double { scrubber.isActive ? scrubber.position : engine.currentTime }

    // MARK: Overlay Components

    @ViewBuilder
    private var topOverlay: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(session.item.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let subtitle = session.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0.0),
                    .init(color: .black.opacity(0.40), location: 0.6),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.top, .horizontal])
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
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
                Button("Audio", systemImage: "speaker.wave.2") { openPanel(.audio) }
                    .buttonStyle(PillButtonStyle())
                    .focused($focus, equals: .audioButton)
                    .disabled(!hasSelectableTracks(engine.audioTracks))
                Button("Sous-titres", systemImage: "captions.bubble") { openPanel(.subtitles) }
                    .buttonStyle(PillButtonStyle())
                    .focused($focus, equals: .subtitleButton)
                    .disabled(!hasSelectableTracks(engine.subtitleTracks))
                if controller.showsNextEpisode, let next = controller.nextEpisode {
                    Button("Épisode suivant · \(next.code)", systemImage: "forward.end.fill") { controller.playNextEpisode() }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                }
            }
            .focusSection()
            .opacity(scrubber.isActive ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.xl)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.40), location: 0.4),
                    .init(color: .black.opacity(0.90), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .allowsHitTesting(false)
        }
    }

    private var topTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .top).combined(with: .opacity)
    }

    private var bottomTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    private var overlayAnimation: Animation {
        if reduceMotion {
            return Theme.Motion.fade
        }
        return isOverlayVisible ? Theme.Motion.overlayEntrance : Theme.Motion.overlayExit
    }

    private func hasSelectableTracks(_ tracks: [MediaTrack]) -> Bool {
        tracks.contains { $0.id >= 0 }
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
                    .frame(width: 16, height: 16)
                    .scaleEffect(isScrubbing ? 1.625 : 1.0)
                    .offset(x: headX - 8, y: 5)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottomLeading) {
                if isScrubbing {
                    previewCard
                        .offset(
                            x: min(max(headX - Self.previewSize.width / 2, 0), width - Self.previewSize.width),
                            y: -40
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .frame(height: 26)
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
