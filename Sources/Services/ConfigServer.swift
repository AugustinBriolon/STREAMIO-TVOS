import Foundation
import Network

@MainActor
public final class ConfigServer: ObservableObject {
    public static let shared = ConfigServer()
    
    @Published public var serverURLString: String = ""
    @Published public var isRunning: Bool = false
    
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8080
    
    private init() {}
    
    public func start() {
        guard listener == nil else { return }
        
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: port)
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        let ip = self?.getWiFiAddress() ?? "127.0.0.1"
                        self?.serverURLString = "http://\(ip):8080"
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("Erreur NWListener: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            Task { @MainActor in
                self?.processRequest(request, connection: connection)
            }
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        if request.contains("POST /save") {
            if let bodyRange = request.range(of: "\r\n\r\n") {
                let body = String(request[bodyRange.upperBound...])
                let pairs = body.components(separatedBy: "&")
                for pair in pairs {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count == 2, parts[0] == "addon_url" {
                        let raw = parts[1].removingPercentEncoding ?? parts[1]
                        if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StremioService.shared.addAddonURL(raw)
                        }
                    }
                }
            }
            sendRedirect(to: "/", connection: connection)
            return
        }
        
        if request.contains("GET /delete?url=") {
            if let startRange = request.range(of: "GET /delete?url=") {
                let rest = request[startRange.upperBound...]
                if let endRange = rest.range(of: " ") {
                    let encodedURL = String(rest[..<endRange.lowerBound])
                    if let decodedURL = encodedURL.removingPercentEncoding {
                        StremioService.shared.removeAddonURL(decodedURL)
                    }
                }
            }
            sendRedirect(to: "/", connection: connection)
            return
        }
        
        let addons = StremioService.shared.configuredAddonURLs
        var addonsHTML = ""
        if addons.isEmpty {
            addonsHTML = "<p style='color:#94a3b8;font-style:italic;'>Aucun addon configuré pour l'instant.</p>"
        } else {
            addonsHTML = "<ul style='list-style:none;padding:0;margin:0;'>"
            for addon in addons {
                let encoded = addon.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? addon
                addonsHTML += """
                <li style='display:flex;align-items:center;justify-content:space-between;background:#0f172a;padding:12px 16px;border-radius:10px;margin-bottom:10px;border:1px solid #334155;'>
                    <span style='word-break:break-all;font-size:14px;color:#e2e8f0;margin-right:12px;'>\(addon)</span>
                    <a href='/delete?url=\(encoded)' style='color:#ef4444;text-decoration:none;font-weight:bold;font-size:13px;padding:6px 12px;background:#ef444420;border-radius:6px;'>Supprimer</a>
                </li>
                """
            }
            addonsHTML += "</ul>"
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Gestion des Addons Stremio TV</title>
        <style>
        body{font-family:system-ui;background:#0f172a;color:#f8fafc;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:20px;}
        .card{background:#1e293b;padding:32px;border-radius:20px;max-width:580px;width:100%;box-shadow:0 10px 40px rgba(0,0,0,0.6);}
        h1{font-size:24px;margin-bottom:8px;color:#38bdf8;}
        h2{font-size:18px;margin-top:28px;margin-bottom:12px;color:#cbd5e1;}
        p{color:#94a3b8;font-size:15px;line-height:1.5;}
        input[type=text]{width:100%;box-sizing:border-box;padding:14px;background:#0f172a;border:1px solid #334155;border-radius:10px;color:#fff;font-size:15px;margin-top:8px;}
        input[type=text]:focus{outline:none;border-color:#38bdf8;}
        button{background:#38bdf8;color:#0f172a;font-weight:bold;border:none;padding:14px 24px;border-radius:10px;font-size:16px;cursor:pointer;margin-top:16px;width:100%;}
        button:hover{background:#0284c7;}
        .hint{background:#0284c720;border-left:4px solid #38bdf8;padding:12px;border-radius:6px;margin-top:24px;font-size:13px;color:#bae6fd;}
        </style></head>
        <body>
        <div class="card">
        <h1>Addons Stremio Apple TV</h1>
        <p>Gérez vos addons de flux vidéo en direct (Torrentio, Lumio, etc.) :</p>
        
        <h2>Addons actifs (\(addons.count))</h2>
        \(addonsHTML)
        
        <h2>Ajouter un nouvel Addon</h2>
        <form method="POST" action="/save">
        <input type="text" name="addon_url" placeholder="https://torrentio.strem.fun/.../manifest.json" required>
        <button type="submit">+ Ajouter à l'Apple TV</button>
        </form>
        <div class="hint">💡 <strong>Astuce :</strong> Vous pouvez ajouter plusieurs addons à la fois. Lors de la lecture d'un film ou d'une série, l'Apple TV interroge tous vos addons en même temps et regroupe tous les flux disponibles !</div>
        </div>
        </body></html>
        """
        sendHTTPResponse(html: html, connection: connection)
    }
    
    private func sendRedirect(to url: String, connection: NWConnection) {
        let response = "HTTP/1.1 303 See Other\r\nLocation: \(url)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
    
    private func sendHTTPResponse(html: String, connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
    
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
