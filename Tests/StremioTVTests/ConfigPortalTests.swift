import Foundation
import Testing
@testable import StremioTV

@MainActor
struct ConfigPortalTests {
    let addons = AddonStore(storage: InMemorySecretStorage([]), legacyDefaults: makeDefaults())

    private func makePortal(pins: [String] = ["1234", "5678"]) -> ConfigPortal {
        var queue = pins
        return ConfigPortal(addons: addons, makePIN: { queue.isEmpty ? "0000" : queue.removeFirst() }, makeToken: { "token" })
    }

    private func request(_ method: String, _ path: String, body: String = "", session: String? = nil) -> HTTPRequest {
        var headers = ["content-length": "\(body.utf8.count)"]
        if let session { headers["cookie"] = "session=\(session)" }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    @Test func requiresPINBeforeShowingAddons() {
        let portal = makePortal()
        addons.add("https://secret.example/KEY123")
        let page = portal.handle(request("GET", "/"))
        #expect(page.body.contains("name=\"pin\""))
        #expect(!page.body.contains("secret.example"))
    }

    @Test func loginSetsStrictSessionCookie() {
        let portal = makePortal()
        #expect(portal.handle(request("POST", "/login", body: "pin=0000")).status == 403)
        let response = portal.handle(request("POST", "/login", body: "pin=1234"))
        #expect(response.status == 303)
        #expect(response.headers["Set-Cookie"]?.contains("SameSite=Strict") == true)
        #expect(response.headers["Set-Cookie"]?.contains("HttpOnly") == true)
    }

    @Test func mutationsRequireSession() {
        let portal = makePortal()
        #expect(portal.handle(request("POST", "/add", body: "addon_url=https%3A%2F%2Fa.io")).status == 403)
        #expect(addons.urls.isEmpty)
        _ = portal.handle(request("POST", "/login", body: "pin=1234"))
        #expect(portal.handle(request("POST", "/add", body: "addon_url=https%3A%2F%2Fa.io", session: "token")).status == 303)
        #expect(addons.urls == ["https://a.io"])
    }

    @Test func deleteIsPostOnly() {
        let portal = makePortal()
        addons.add("https://a.io")
        _ = portal.handle(request("POST", "/login", body: "pin=1234"))
        #expect(portal.handle(request("GET", "/delete?url=https://a.io", session: "token")).status == 404)
        #expect(addons.urls.count == 1)
        _ = portal.handle(request("POST", "/delete", body: "index=0", session: "token"))
        #expect(addons.urls.isEmpty)
    }

    @Test func managePageMasksKeysAndEscapesInput() {
        let portal = makePortal()
        addons.add("https://evil.io/<script>KEY")
        _ = portal.handle(request("POST", "/login", body: "pin=1234"))
        let page = portal.handle(request("GET", "/", session: "token")).body
        #expect(!page.contains("<script>"))
        #expect(!page.contains("KEY"))
        #expect(page.contains("evil.io"))
    }

    @Test func rotatesPINAfterRepeatedFailures() {
        let portal = makePortal()
        for _ in 0..<ConfigPortal.maxFailedAttempts {
            _ = portal.handle(request("POST", "/login", body: "pin=9999"))
        }
        #expect(portal.pin == "5678")
        #expect(portal.handle(request("POST", "/login", body: "pin=1234")).status == 403)
    }

    @Test func responsesCarrySecurityHeaders() {
        let raw = String(decoding: HTTPResponse.html("x").serialized, as: UTF8.self)
        #expect(raw.contains("Content-Security-Policy: default-src 'none'"))
        #expect(raw.contains("X-Frame-Options: DENY"))
    }
}
