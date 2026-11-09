import Foundation
import Network
import Observation

/// LAN web server that lets a phone or computer manage addon URLs. Runs only while Settings is visible.
@MainActor
@Observable
public final class ConfigServer {
    public private(set) var serverURLString = ""
    public private(set) var isRunning = false
    public var pin: String { portal.pin }

    @ObservationIgnored private let portal: ConfigPortal
    @ObservationIgnored private var listener: NWListener?
    private static let port: NWEndpoint.Port = 8080

    public init(addons: AddonStore) {
        portal = ConfigPortal(addons: addons)
    }

    public func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: Self.port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.serve(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.update(state) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func update(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            serverURLString = "http://\(Self.wifiAddress() ?? "apple-tv.local"):\(Self.port.rawValue)"
        case .failed, .cancelled:
            isRunning = false
            listener = nil
        default:
            break
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    /// Reads until a full request (headers + Content-Length body) is buffered.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: HTTPRequestParser.maxRequestSize) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                let accumulated = buffer + (data ?? Data())
                switch HTTPRequestParser.parse(accumulated) {
                case .complete(let request):
                    self.send(self.portal.handle(request), on: connection)
                case .invalid:
                    self.send(.html("Requête invalide", status: 400), on: connection)
                case .incomplete where error == nil && !isComplete:
                    self.receive(on: connection, buffer: accumulated)
                case .incomplete:
                    connection.cancel()
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  ["en0", "en1"].contains(String(cString: interface.ifa_name)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: host)
            if String(cString: interface.ifa_name) == "en0" { break }
        }
        return address
    }
}
