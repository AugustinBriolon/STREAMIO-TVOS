import Foundation
import Testing
@testable import Loge

@MainActor
struct AppPreferencesTests {
    @Test func defaultValuesAreCorrect() {
        let defaults = UserDefaults(suiteName: "tests.preferences.\(UUID().uuidString)")!
        let prefs = AppPreferences(defaults: defaults)

        #expect(prefs.metadataLanguage == "fr")
        #expect(prefs.preferredAudioLanguage == "fr")
        #expect(prefs.subtitleMode == .auto)
        #expect(prefs.preferredSubtitleLanguage == "fr")
        #expect(prefs.showWatchProviders == true)
        #expect(prefs.effectiveTMDBKey == AppPreferences.tmdbApiKey)
    }

    @Test func persistenceSavesAcrossInstances() {
        let suite = "tests.preferences.\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite)!
        let prefs1 = AppPreferences(defaults: defaults1)

        prefs1.metadataLanguage = "es"
        prefs1.preferredAudioLanguage = "en"
        prefs1.subtitleMode = .alwaysOn
        prefs1.preferredSubtitleLanguage = "es"
        prefs1.showWatchProviders = false

        let defaults2 = UserDefaults(suiteName: suite)!
        let prefs2 = AppPreferences(defaults: defaults2)

        #expect(prefs2.metadataLanguage == "es")
        #expect(prefs2.preferredAudioLanguage == "en")
        #expect(prefs2.subtitleMode == .alwaysOn)
        #expect(prefs2.preferredSubtitleLanguage == "es")
        #expect(prefs2.showWatchProviders == false)
    }

    @Test func tmdbLanguageCodeFormatting() {
        #expect(TMDBService.tmdbLanguageCode("fr") == "fr-FR")
        #expect(TMDBService.tmdbLanguageCode("en") == "en-US")
        #expect(TMDBService.tmdbLanguageCode("es") == "es-ES")
        #expect(TMDBService.tmdbLanguageCode("de") == "de-DE")
        #expect(TMDBService.tmdbLanguageCode("it") == "it-IT")
        #expect(TMDBService.tmdbLanguageCode("ja") == "ja-JP")
        #expect(TMDBService.tmdbLanguageCode("pt-BR") == "pt-BR")
    }

    @Test func supportedLanguageHelper() {
        #expect(SupportedLanguage.name(for: "fr") == "Français")
        #expect(SupportedLanguage.name(for: "en").contains("English"))
        #expect(SupportedLanguage.name(for: "unknown") == "UNKNOWN")
    }
}
