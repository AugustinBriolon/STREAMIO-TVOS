import Foundation
import Observation

public struct HTTPResponse: Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: String

    public static func html(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/html; charset=utf-8"], body: body)
    }

    public static func redirect(_ location: String, headers extra: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: 303, headers: extra.merging(["Location": location]) { $1 }, body: "")
    }

    public var serialized: Data {
        let reason = [200: "OK", 303: "See Other", 403: "Forbidden", 404: "Not Found", 400: "Bad Request"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        let allHeaders = headers.merging([
            "Content-Length": "\(body.utf8.count)",
            "Connection": "close",
            "Cache-Control": "no-store",
            "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'",
        ]) { current, _ in current }
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        return Data((head + "\r\n" + body).utf8)
    }
}

/// Routing and access control of the LAN configuration page (see ADR 0005).
/// Access requires the PIN displayed on the TV; a session cookie (SameSite=Strict) authorises mutations.
@MainActor
@Observable
public final class ConfigPortal {
    public private(set) var pin: String
    static let maxFailedAttempts = 5

    @ObservationIgnored private let addons: AddonStore
    @ObservationIgnored private let makePIN: () -> String
    @ObservationIgnored private let makeToken: () -> String
    @ObservationIgnored private var sessions = Set<String>()
    @ObservationIgnored private var failedAttempts = 0

    public init(
        addons: AddonStore,
        makePIN: @escaping () -> String = { String(format: "%04d", Int.random(in: 0...9999)) },
        makeToken: @escaping () -> String = { UUID().uuidString + UUID().uuidString }
    ) {
        self.addons = addons
        self.makePIN = makePIN
        self.makeToken = makeToken
        self.pin = makePIN()
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let authenticated = request.cookie("session").map(sessions.contains) ?? false
        switch (request.method, request.path) {
        case ("GET", "/"):
            return .html(authenticated ? managePage() : loginPage())
        case ("POST", "/login"):
            return login(pin: request.formFields["pin"] ?? "")
        case ("POST", "/add"):
            guard authenticated else { return .html(loginPage(error: "Session expirée."), status: 403) }
            let added = addons.add(request.formFields["addon_url"] ?? "")
            return added ? .redirect("/") : .html(managePage(error: "URL invalide : elle doit commencer par https://"), status: 400)
        case ("POST", "/delete"):
            guard authenticated else { return .html(loginPage(error: "Session expirée."), status: 403) }
            if let index = Int(request.formFields["index"] ?? ""), addons.urls.indices.contains(index) {
                addons.remove(addons.urls[index])
            }
            return .redirect("/")
        default:
            return .html(page(body: "<h1>Page introuvable</h1><p><a href='/'>Retour</a></p>"), status: 404)
        }
    }

    private func login(pin candidate: String) -> HTTPResponse {
        guard candidate == pin else {
            failedAttempts += 1
            if failedAttempts >= Self.maxFailedAttempts {
                // Defeats brute force of the 4-digit PIN: a new one is shown on the TV.
                pin = makePIN()
                failedAttempts = 0
            }
            return .html(loginPage(error: "Code incorrect."), status: 403)
        }
        failedAttempts = 0
        let token = makeToken()
        sessions.insert(token)
        return .redirect("/", headers: ["Set-Cookie": "session=\(token); HttpOnly; SameSite=Strict; Path=/"])
    }

    // MARK: Pages

    private func loginPage(error: String? = nil) -> String {
        page(body: """
        <h1>Addons Apple TV</h1>
        <p>Saisissez le code à 4 chiffres affiché dans <strong>Réglages</strong> sur l'Apple TV.</p>
        \(errorBanner(error))
        <form method="POST" action="/login">
        <input type="text" name="pin" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" autocomplete="off" required autofocus>
        <button type="submit">Valider</button>
        </form>
        """)
    }

    private func managePage(error: String? = nil) -> String {
        let rows = addons.urls.enumerated().map { index, url in
            """
            <li><span>\(HTTPRequestParser.htmlEscape(AddonStore.maskedDisplay(url)))</span>
            <form method="POST" action="/delete"><input type="hidden" name="index" value="\(index)">
            <button class="danger" type="submit">Supprimer</button></form></li>
            """
        }.joined()
        let list = rows.isEmpty ? "<p class='muted'>Aucun addon configuré.</p>" : "<ul>\(rows)</ul>"
        return page(body: """
        <h1>Addons Apple TV</h1>
        \(errorBanner(error))
        <h2>Addons actifs (\(addons.urls.count))</h2>
        \(list)
        <h2>Ajouter un addon</h2>
        <form method="POST" action="/add">
        <input type="text" name="addon_url" placeholder="https://…/manifest.json" autocomplete="off" required>
        <button type="submit">Ajouter à l'Apple TV</button>
        </form>
        """)
    }

    private func errorBanner(_ message: String?) -> String {
        message.map { "<p class='error'>\(HTTPRequestParser.htmlEscape($0))</p>" } ?? ""
    }

    private func page(body: String) -> String {
        """
        <!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1"><title>Addons Apple TV</title>
        <style>
        body{font-family:system-ui;background:#141414;color:#fff;margin:0;padding:24px;display:flex;justify-content:center}
        main{max-width:560px;width:100%}h1{font-size:26px}h2{font-size:18px;margin-top:28px;color:#ccc}
        p{color:#aaa;line-height:1.5}.muted{font-style:italic}.error{color:#fff;background:#e5091433;border-left:4px solid #e50914;padding:10px}
        input{width:100%;box-sizing:border-box;padding:14px;background:#222;border:1px solid #444;border-radius:6px;color:#fff;font-size:16px}
        button{background:#e50914;color:#fff;font-weight:700;border:0;padding:14px;border-radius:6px;font-size:16px;width:100%;margin-top:12px}
        ul{list-style:none;padding:0}li{display:flex;gap:12px;align-items:center;justify-content:space-between;background:#222;padding:12px;border-radius:6px;margin-bottom:8px}
        li form button{width:auto;margin:0;padding:8px 12px;background:#333}
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}
