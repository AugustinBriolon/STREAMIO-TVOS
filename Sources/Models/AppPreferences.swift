import Foundation
import Observation

/// Mode de gestion des sous-titres au démarrage de la lecture.
public enum SubtitlePreferenceMode: String, CaseIterable, Codable, Sendable {
    /// Sous-titres complets si l'audio n'est pas dans la langue préférée ; sous-titres forcés uniquement si l'audio est dans la langue préférée.
    case auto = "auto"
    /// Active systématiquement les sous-titres dans la langue préférée.
    case alwaysOn = "alwaysOn"
    /// Aucun sous-titre activé au démarrage de la lecture.
    case off = "off"

    public var title: String {
        switch self {
        case .auto: return "Automatique"
        case .alwaysOn: return "Toujours activé"
        case .off: return "Désactivé"
        }
    }
}

/// Langues courantes supportées pour les préférences et les métadonnées.
public struct SupportedLanguage: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public static let all: [SupportedLanguage] = [
        SupportedLanguage(code: "fr", name: "Français"),
        SupportedLanguage(code: "en", name: "English (Anglais)"),
        SupportedLanguage(code: "es", name: "Español (Espagnol)"),
        SupportedLanguage(code: "de", name: "Deutsch (Allemand)"),
        SupportedLanguage(code: "it", name: "Italiano (Italien)"),
        SupportedLanguage(code: "pt", name: "Português (Portugais)"),
        SupportedLanguage(code: "ja", name: "日本語 (Japonais)"),
    ]

    public static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code.uppercased()
    }
}

/// Préférences de l'application (langue des métadonnées, audio, sous-titres, clés de services).
/// Persisté dans AppGroup.defaults pour être accessible dans toute l'application.
@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    private enum Keys {
        static let metadataLanguage = "app.preferences.metadataLanguage"
        static let preferredAudioLanguage = "app.preferences.preferredAudioLanguage"
        static let subtitleMode = "app.preferences.subtitleMode"
        static let preferredSubtitleLanguage = "app.preferences.preferredSubtitleLanguage"
        static let tmdbApiKey = "app.preferences.tmdbApiKey"
        static let showWatchProviders = "app.preferences.showWatchProviders"
    }

    /// Clé API TMDB (v3) injectée au build via `Config/Secrets.xcconfig` → Info.plist (`TMDBApiKey`).
    public nonisolated static var tmdbApiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "TMDBApiKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private let defaults: UserDefaults

    public var metadataLanguage: String {
        didSet { defaults.set(metadataLanguage, forKey: Keys.metadataLanguage) }
    }

    public var preferredAudioLanguage: String {
        didSet { defaults.set(preferredAudioLanguage, forKey: Keys.preferredAudioLanguage) }
    }

    public var subtitleMode: SubtitlePreferenceMode {
        didSet { defaults.set(subtitleMode.rawValue, forKey: Keys.subtitleMode) }
    }

    public var preferredSubtitleLanguage: String {
        didSet { defaults.set(preferredSubtitleLanguage, forKey: Keys.preferredSubtitleLanguage) }
    }

    /// Extension façade : logos « Disponible sur » (JustWatch/TMDB) sur la fiche titre.
    public var showWatchProviders: Bool {
        didSet { defaults.set(showWatchProviders, forKey: Keys.showWatchProviders) }
    }

    public var effectiveTMDBKey: String {
        Self.tmdbApiKey
    }

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.metadataLanguage = defaults.string(forKey: Keys.metadataLanguage) ?? "fr"
        self.preferredAudioLanguage = defaults.string(forKey: Keys.preferredAudioLanguage) ?? "fr"
        if let rawMode = defaults.string(forKey: Keys.subtitleMode),
           let mode = SubtitlePreferenceMode(rawValue: rawMode) {
            self.subtitleMode = mode
        } else {
            self.subtitleMode = .auto
        }
        self.preferredSubtitleLanguage = defaults.string(forKey: Keys.preferredSubtitleLanguage) ?? "fr"
        if defaults.object(forKey: Keys.showWatchProviders) == nil {
            self.showWatchProviders = true
        } else {
            self.showWatchProviders = defaults.bool(forKey: Keys.showWatchProviders)
        }
    }
}
