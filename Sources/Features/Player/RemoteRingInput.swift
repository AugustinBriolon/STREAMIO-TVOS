import GameController

/// Reads raw Siri Remote clickpad touches through GameController and reports ring rotation.
/// SwiftUI only exposes digested left/right moves, which cannot express a circular jog.
@MainActor
final class RemoteRingInput {
    private var tracker = RingTracker()
    private var connectObserver: NSObjectProtocol?
    private let onRotate: (Double) -> Void
    /// Last time the ring produced rotation; arrow moves arriving meanwhile are by-products of the same gesture.
    private(set) var lastRotationAt = Date.distantPast

    init(onRotate: @escaping (Double) -> Void) {
        self.onRotate = onRotate
        GCController.controllers().forEach(attach)
        connectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let controller = note.object as? GCController { self?.attach(controller) }
            }
        }
    }

    func stop() {
        GCController.controllers().forEach { $0.microGamepad?.dpad.valueChangedHandler = nil }
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        connectObserver = nil
    }

    var isRotating: Bool { Date().timeIntervalSince(lastRotationAt) < 0.35 }

    private func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        pad.reportsAbsoluteDpadValues = true
        pad.allowsRotation = false
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handle(x: Double(x), y: Double(y)) }
        }
    }

    private func handle(x: Double, y: Double) {
        guard let radians = tracker.update(x: x, y: y), abs(radians) > 0.001 else { return }
        lastRotationAt = Date()
        onRotate(radians)
    }
}
