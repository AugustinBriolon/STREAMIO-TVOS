import Foundation
import Observation
import Security

/// Service d'authentification pour StremioTV sur tvOS.
/// Supporte le Device Flow (Jumelage par QR Code) et la connexion directe par identifiants (Email + Mot de passe).
@MainActor
@Observable
public final class AuthService {
    public static let shared = AuthService()

    /// URL de base de l'API Cloudflare Worker (modifiable dans les préférences ou build)
    public var apiBaseURL: String {
        get { UserDefaults.standard.string(forKey: "stremiotv.apiBaseURL") ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "stremiotv.apiBaseURL") }
    }
    public let defaultBaseURL = "https://stremiotv-api.stremiotv-home.workers.dev"

    public private(set) var token: String?
    public private(set) var accountEmail: String?
    public var isAuthenticated: Bool { token != nil }

    // État de l'appairage en cours
    public private(set) var activePairingCode: String?
    public private(set) var activePairingURL: String?
    public private(set) var isPollingPairing = false
    public private(set) var pairingError: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private let keychainService = "com.h6245.vortxtv.auth"

    public init() {
        self.token = loadFromKeychain(key: "jwt-token")
        self.accountEmail = loadFromKeychain(key: "account-email")
    }

    // MARK: - Connexion Directe (Email + Password)

    public func login(email: String, password: String) async throws {
        guard let url = URL(string: "\(apiBaseURL)/api/auth/login") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ])

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
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ])

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

    // MARK: - Device Flow (Jumelage par QR Code)

    public func startPairingSession() async {
        stopPairingSession()
        pairingError = nil

        guard let url = URL(string: "\(apiBaseURL)/api/device/code") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceName": "Apple TV"])

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
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])

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

    public func logout() {
        self.token = nil
        self.accountEmail = nil
        deleteFromKeychain(key: "jwt-token")
        deleteFromKeychain(key: "account-email")
        stopPairingSession()
    }

    private func setAuthenticated(token: String, email: String) {
        self.token = token
        self.accountEmail = email
        saveToKeychain(key: "jwt-token", value: token)
        saveToKeychain(key: "account-email", value: email)
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

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
