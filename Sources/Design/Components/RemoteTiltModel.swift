import GameController
import Observation
import SwiftUI

/// Tracks micro-movements on the Siri Remote touch surface / clickpad while browsing,
/// powering the 3D parallax tilt effect on focused cards (the signature Apple TV physical feel).
@MainActor
@Observable
final class RemoteTiltModel {
    static let shared = RemoteTiltModel()

    private(set) var x: Double = 0
    private(set) var y: Double = 0
    private(set) var isTouching = false

    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var connectObserver: NSObjectProtocol?

    init() {
        start()
    }

    func start() {
        GCController.controllers().forEach(attach)
        if connectObserver == nil {
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
    }

    func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        pad.reportsAbsoluteDpadValues = true
        pad.allowsRotation = false
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handle(x: Double(x), y: Double(y)) }
        }
    }

    func handle(x: Double, y: Double) {
        resetTask?.cancel()
        if abs(x) > 0.015 || abs(y) > 0.015 {
            self.x = max(-1.0, min(1.0, x))
            self.y = max(-1.0, min(1.0, y))
            self.isTouching = true

            // When user lifts thumb, microGamepad might cease sending events:
            // smoothly settle back to neutral after a short idle timeout.
            resetTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self?.settle()
            }
        } else {
            settle()
        }
    }

    func settle() {
        resetTask?.cancel()
        self.x = 0
        self.y = 0
        self.isTouching = false
    }
}
