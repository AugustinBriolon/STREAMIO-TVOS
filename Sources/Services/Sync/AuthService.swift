import Foundation
import Observation
import Security
import UIKit

/// How this Apple TV names itself in the account's device list.
public struct DeviceIdentity: Sendable, Equatable {
    public let name: String
    public let model: String

    @MainActor public static var current: DeviceIdentity {
        DeviceIdentity(name: UIDevice.current.name, model: modelName(forIdentifier: hardwareIdentifier))
    }

    /// "AppleTV14,1" and the like.
    static var hardwareIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Marketing name for the hardware identifiers tvOS 18 runs on; unknown ones are shown as they are.
    static func modelName(forIdentifier identifier: String) -> String {
        switch identifier {
        case "AppleTV5,3": "Apple TV HD"
        case "AppleTV6,2": "Apple TV 4K"
        case "AppleTV11,1": "Apple TV 4K (2e génération)"
        case "AppleTV14,1": "Apple TV 4K (3e génération)"
        case "x86_64", "arm64": "Simulateur"
        default: identifier.hasPrefix("AppleTV") ? "Apple TV" : identifier
        }
    }
}

/// A device signed in to the account (`GET /api/devices`).
public struct DeviceSession: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let model: String?
    public let lastSeenAtMs: Double?
    public let isCurrent: Bool

    public var lastSeen: Date? { lastSeenAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

/// Service d'authentification pour Loge sur tvOS.
/// Supporte le Device Flow (Jumelage par QR Code) et la connexion directe par identifiants (Email + Mot de passe).
@MainActor
@Observable
public final class AuthService {
    public static let shared = AuthService()

    /// URL de base de l'API Cloudflare Worker (modifiable dans les préférences ou build)
    public var apiBaseURL: String {
        get {
            // Ignore stremiotv.apiBaseURL: an old override can hit a worker whose JWT_SECRET
            // no longer matches and looks like a mid-session revoke.
            UserDefaults.standard.string(forKey: "loge.apiBaseURL") ?? defaultBaseURL
        }
        set { UserDefaults.standard.set(newValue, forKey: "loge.apiBaseURL") }
    }
    public let defaultBaseURL = "https://loge-api.stremiotv-home.workers.dev"

    public private(set) var token: String?
    public private(set) var accountEmail: String?
    public var isAuthenticated: Bool { token != nil }

    /// "Continuer sans compte" was chosen: the welcome screen stops offering to sign in at launch.
    public private(set) var welcomeDismissed: Bool
    /// This device was signed out from the account (web device list): the welcome screen says so.
    public private(set) var wasSignedOutRemotely = false
    public var showsWelcome: Bool { !isAuthenticated && !welcomeDismissed }

    /// Devices signed in to the account, for Settings. Empty until `refreshDevices()`.
    public private(set) var devices: [DeviceSession] = []

    // État de l'appairage en cours
    public private(set) var activePairingCode: String?
    public private(set) var activePairingURL: String?
    public private(set) var isPollingPairing = false
    public private(set) var pairingError: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private let keychainService = "com.h6245.loge.auth"

    public init() {
        let dismissed = UserDefaults.standard.object(forKey: Self.welcomeDismissedKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.welcomeDismissedKey)
            : UserDefaults.standard.bool(forKey: "stremiotv.welcomeDismissed")
        self.welcomeDismissed = dismissed
        let migratedToken = loadFromKeychain(key: "jwt-token") == nil
        self.token = loadFromKeychain(key: "jwt-token")
            ?? loadFromKeychain(key: "jwt-token", service: Self.legacyKeychainService)
        self.accountEmail = loadFromKeychain(key: "account-email")
            ?? loadFromKeychain(key: "account-email", service: Self.legacyKeychainService)
        // Move a vortxtv keychain JWT into Loge's service, then drop the legacy copy so a later
        // clearCredentials cannot resurrect it and bounce the device on the next launch.
        if migratedToken, let token {
            saveToKeychain(key: "jwt-token", value: token)
            if let accountEmail { saveToKeychain(key: "account-email", value: accountEmail) }
        }
        deleteFromKeychain(key: "jwt-token", service: Self.legacyKeychainService)
        deleteFromKeychain(key: "account-email", service: Self.legacyKeychainService)
    }

    private static let welcomeDismissedKey = "loge.welcomeDismissed"
    private static let legacyKeychainService = "com.h6245.vortxtv.auth"

    public func dismissWelcome() {
        welcomeDismissed = true
        wasSignedOutRemotely = false
        UserDefaults.standard.set(true, forKey: Self.welcomeDismissedKey)
    }

    /// The account rejected this device's token. Local profiles and history stay; only the link to the
    /// account goes, and the welcome screen offers to sign in again.
    public func handleRevokedSession() {
        clearCredentials()
        devices = []
        wasSignedOutRemotely = true
        welcomeDismissed = false
        UserDefaults.standard.set(false, forKey: Self.welcomeDismissedKey)
    }

    public func refreshDevices() async {
        guard let token, let url = URL(string: "\(apiBaseURL)/api/devices") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let identity = DeviceIdentity.current
        req.setValue(identity.name, forHTTPHeaderField: "X-Device-Name")
        req.setValue(identity.model, forHTTPHeaderField: "X-Device-Model")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let status = (response as? HTTPURLResponse)?.statusCode else { return }
        if status == 401 {
            handleRevokedSession()
            return
        }
        struct Payload: Decodable {
            let devices: [DeviceSession]
            let token: String?
        }
        if status == 200, let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            if let newToken = payload.token {
                adoptUpgradedToken(newToken)
            }
            devices = payload.devices
        }
    }

    // MARK: - Connexion Directe (Email + Password)

    public func login(email: String, password: String) async throws {
        guard let url = URL(string: "\(apiBaseURL)/api/auth/login") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: credentialsBody(email: email, password: password))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if http.statusCode != 200 {
            let errorMsg = json?["error"] as? String ?? "Erreur de connexion (\(http.statusCode))"
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        if let token = json?["token"] as? String, let email = json?["email"] as? String {
            setAuthenticated(token: token, email: email)
        }
    }

    public func register(email: String, password: String) async throws {
        guard let url = URL(string: "\(apiBaseURL)/api/auth/register") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: credentialsBody(email: email, password: password))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if http.statusCode != 200 {
            let errorMsg = json?["error"] as? String ?? "Erreur de création de compte (\(http.statusCode))"
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        if let token = json?["token"] as? String, let email = json?["email"] as? String {
            setAuthenticated(token: token, email: email)
        }
    }

    /// Credentials plus this device's name and model, so the account's device list can show it.
    private func credentialsBody(email: String, password: String) -> [String: String] {
        let device = DeviceIdentity.current
        return [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "deviceName": device.name,
            "deviceModel": device.model
        ]
    }

    // MARK: - Device Flow (Jumelage par QR Code)

    public func startPairingSession() async {
        stopPairingSession()
        pairingError = nil

        guard let url = URL(string: "\(apiBaseURL)/api/device/code") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceName": DeviceIdentity.current.name])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? String,
                  let verifyUrl = json["verifyUrl"] as? String else {
                pairingError = "Impossible de générer le code d'appairage."
                return
            }

            self.activePairingCode = code
            self.activePairingURL = verifyUrl
            self.isPollingPairing = true
            startPolling(code: code)
        } catch {
            self.pairingError = "Connexion au serveur impossible. Vérifiez l'accès internet."
        }
    }

    public func stopPairingSession() {
        pollTask?.cancel()
        pollTask = nil
        isPollingPairing = false
        activePairingCode = nil
        activePairingURL = nil
    }

    private func startPolling(code: String) {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard let self, self.isPollingPairing else { break }

                guard let url = URL(string: "\(self.apiBaseURL)/api/device/poll") else { break }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let device = DeviceIdentity.current
                req.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "code": code, "deviceName": device.name, "deviceModel": device.model
                ])

                if let (data, response) = try? await URLSession.shared.data(for: req),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {

                    if status == "authorized",
                       let token = json["token"] as? String,
                       let email = json["email"] as? String {
                        self.setAuthenticated(token: token, email: email)
                        self.stopPairingSession()
                        break
                    } else if status == "expired" {
                        self.pairingError = "Le code a expiré. Veuillez en générer un nouveau."
                        self.stopPairingSession()
                        break
                    }
                }
            }
        }
    }

    // MARK: - Déconnexion

    /// Signs out here and, best effort, closes this device's session so it leaves the account's device list.
    public func logout() {
        if let token, let url = URL(string: "\(apiBaseURL)/api/auth/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
        clearCredentials()
        devices = []
    }

    private func clearCredentials() {
        self.token = nil
        self.accountEmail = nil
        deleteFromKeychain(key: "jwt-token")
        deleteFromKeychain(key: "account-email")
        deleteFromKeychain(key: "jwt-token", service: Self.legacyKeychainService)
        deleteFromKeychain(key: "account-email", service: Self.legacyKeychainService)
        stopPairingSession()
    }

    private func setAuthenticated(token: String, email: String) {
        wasSignedOutRemotely = false
        self.token = token
        self.accountEmail = email
        saveToKeychain(key: "jwt-token", value: token)
        saveToKeychain(key: "account-email", value: email)
        deleteFromKeychain(key: "jwt-token", service: Self.legacyKeychainService)
        deleteFromKeychain(key: "account-email", service: Self.legacyKeychainService)
    }

    /// Legacy tokens (no session id) get replaced when the API mints a device session.
    public func adoptUpgradedToken(_ token: String) {
        guard !token.isEmpty, token != self.token else { return }
        self.token = token
        saveToKeychain(key: "jwt-token", value: token)
        deleteFromKeychain(key: "jwt-token", service: Self.legacyKeychainService)
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteFromKeychain(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String, service: String? = nil) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String, service: String? = nil) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
