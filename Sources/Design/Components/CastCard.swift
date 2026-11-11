import SwiftUI
import GameController

/// Suivi en direct du clickpad tactile (la molette) de la Siri Remote pour l'effet de bascule 3D Apple.
@MainActor
final class TiltMotionManager: ObservableObject {
    @Published var tiltX: CGFloat = 0
    @Published var tiltY: CGFloat = 0
    @Published var isTouching = false

    private var connectObserver: NSObjectProtocol?
    private var isObserving = false

    func start() {
        guard !isObserving else { return }
        isObserving = true
        GCController.controllers().forEach(attach)
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                if let controller = note.object as? GCController { self?.attach(controller) }
            }
        }
    }

    func stop() {
        isObserving = false
        GCController.controllers().forEach { $0.microGamepad?.dpad.valueChangedHandler = nil }
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        connectObserver = nil
        withAnimation(Theme.Motion.focus) {
            tiltX = 0
            tiltY = 0
            isTouching = false
        }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        pad.reportsAbsoluteDpadValues = true
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                self?.handleTouch(x: CGFloat(x), y: CGFloat(y))
            }
        }
    }

    private func handleTouch(x: CGFloat, y: CGFloat) {
        if abs(x) < 0.02 && abs(y) < 0.02 {
            withAnimation(Theme.Motion.focus) {
                tiltX = 0
                tiltY = 0
                isTouching = false
            }
        } else {
            tiltX = min(max(x, -1), 1)
            tiltY = min(max(y, -1), 1)
            isTouching = true
        }
    }
}

/// Carte d'acteur ronde Apple TV avec reflet spéculaire et interaction d'inclinaison 3D à la molette tactile.
public struct CastCard: View {
    public let member: CastMember

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = TiltMotionManager()

    private static let photoDiameter: CGFloat = 150
    private static let cardWidth: CGFloat = 170

    public init(member: CastMember) {
        self.member = member
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            photoContainer
            labels
        }
        .frame(width: Self.cardWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(member.character.map { "\(member.name), rôle de \($0)" } ?? member.name)
        .onChange(of: isFocused, initial: true) { _, focused in
            if focused {
                motion.start()
            } else {
                motion.stop()
            }
        }
        .onDisappear {
            motion.stop()
        }
    }

    // MARK: - Photo & Effet 3D

    private var photoContent: some View {
        ZStack {
            photoView
                .frame(width: Self.photoDiameter, height: Self.photoDiameter)
                .clipShape(Circle())

            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

            if isFocused && !reduceMotion {
                specularHighlight
            }
        }
    }

    private var specularHighlight: some View {
        let currentTiltX = motion.tiltX
        let currentTiltY = motion.tiltY
        return RadialGradient(
            colors: [Color.white.opacity(0.35), Color.clear],
            center: UnitPoint(x: 0.5 + currentTiltX * 0.35, y: 0.5 - currentTiltY * 0.35),
            startRadius: 0,
            endRadius: Self.photoDiameter * 0.65
        )
        .clipShape(Circle())
        .blendMode(.plusLighter)
    }

    private var photoContainer: some View {
        let currentTiltX = reduceMotion ? 0 : motion.tiltX
        let currentTiltY = reduceMotion ? 0 : motion.tiltY
        let scale: CGFloat = reduceMotion ? (isFocused ? 1.06 : 1.0) : (isFocused ? 1.12 : 1.0)

        return photoContent
            .padding(Theme.Spacing.xxs)
            .overlay {
                Circle()
                    .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused ? 4 : 0)
            }
            .rotation3DEffect(
                .degrees(Double(currentTiltX) * 14),
                axis: (x: 0, y: 1, z: 0)
            )
            .rotation3DEffect(
                .degrees(Double(-currentTiltY) * 14),
                axis: (x: 1, y: 0, z: 0)
            )
            .offset(x: currentTiltX * 5, y: -currentTiltY * 5)
            .scaleEffect(scale)
            .shadow(
                color: Color.black.opacity(isFocused ? 0.65 : 0.25),
                radius: isFocused ? 20 : 6,
                x: -currentTiltX * 10,
                y: currentTiltY * 10 + (isFocused ? 14 : 4)
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(
                motion.isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: motion.tiltX
            )
            .animation(
                motion.isTouching
                    ? Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    : Theme.Motion.focus,
                value: motion.tiltY
            )
    }

    @ViewBuilder
    private var photoView: some View {
        if let photoURL = member.photoURL {
            RemoteImage(url: photoURL, maxPixel: Self.photoDiameter * Theme.pixelScale)
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.Palette.surface
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(initials(for: member.name))
                    .font(Theme.Typography.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    // MARK: - Labels

    private var labels: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(member.name)
                .font(Theme.Typography.caption.weight(.bold))
                .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: Self.cardWidth)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined()
    }
}
