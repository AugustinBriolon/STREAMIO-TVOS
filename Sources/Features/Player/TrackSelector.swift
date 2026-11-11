import Foundation

/// An audio or subtitle track as exposed by the playback engine (index -1 means "off").
struct MediaTrack: Identifiable, Hashable, Sendable {
    let id: Int32
    let name: String
}

/// Picks default audio and subtitle tracks from embedded track names, the way a French viewer expects:
/// French audio (VFF before VFQ, light codecs before DTS/TrueHD, never commentary/audio description);
/// with French audio only forced subtitles, otherwise full French subtitles (text before PGS bitmaps).
enum TrackSelector {
    static func preferredAudio(_ tracks: [MediaTrack], language: String = "fr") -> MediaTrack? {
        tracks.filter { $0.id >= 0 }.max { audioScore($0, language) < audioScore($1, language) }
    }

    static func preferredSubtitle(
        _ tracks: [MediaTrack],
        audio: MediaTrack?,
        mode: SubtitlePreferenceMode = .auto,
        language: String = "fr",
        audioLanguage: String = "fr"
    ) -> MediaTrack? {
        guard mode != .off else { return nil }

        let candidates = tracks.filter { $0.id >= 0 && matchesLanguage($0.name, language) && !isExtra($0.name) }
        guard !candidates.isEmpty else { return nil }

        if mode == .alwaysOn {
            let full = candidates.filter { !isForced($0.name) }
            return (full.isEmpty ? candidates : full).max { subtitleScore($0) < subtitleScore($1) }
        }

        // Mode .auto : sous-titres forcés si audio dans la langue préférée, sous-titres complets sinon.
        let audioInPreferred = audio.map { matchesLanguage($0.name, audioLanguage) } ?? false
        if audioInPreferred {
            return candidates.filter { isForced($0.name) }.max { subtitleScore($0) < subtitleScore($1) }
        }
        let full = candidates.filter { !isForced($0.name) }
        return (full.isEmpty ? candidates : full).max { subtitleScore($0) < subtitleScore($1) }
    }

    // MARK: Scoring

    private static func audioScore(_ track: MediaTrack, _ language: String) -> Int {
        let name = track.name
        var score = 0
        if matchesLanguage(name, language) { score += 1000 }
        if isExtra(name) { score -= 2000 }
        if contains(name, #"\bVFF\b|\bVF2?\b|France|European|\(fr-FR\)"#) { score += 50 }
        if contains(name, #"\bVFQ\b|Canad|Québ|Queb"#) { score -= 50 }
        // Software DTS/TrueHD decoding is costly on Apple TV HD; Dolby Digital variants are decoded natively.
        if contains(name, #"E-?AC-?3|DDP|Dolby Digital|\bAC-?3\b|\bDD\b|AAC"#) { score += 20 }
        if contains(name, #"\bDTS|TrueHD"#) { score -= 20 }
        // Earlier tracks win ties: muxers put the main track first.
        return score * 100 - Int(track.id)
    }

    private static func subtitleScore(_ track: MediaTrack) -> Int {
        var score = 0
        if contains(track.name, #"\bSRT\b|SubRip|\bText\b"#) { score += 20 }
        if contains(track.name, #"\bPGS\b|HDMV"#) { score -= 20 }
        if contains(track.name, #"\bSDH\b|\bCC\b|malentendant"#) { score -= 10 }
        if contains(track.name, #"\bVFF\b|France|European"#) { score += 5 }
        if contains(track.name, #"\bVFQ\b|Canad"#) { score -= 5 }
        return score * 100 - Int(track.id)
    }

    private static let languageKeywords: [String: String] = [
        "fr": #"\bfr(e|a)?\b|french|fran[cç]ais|\bVF[FQI2]?\b|truefrench"#,
        "en": #"\ben(g)?\b|english|anglais|\bVO\b"#,
        "es": #"\bes(p)?\b|spanish|español|castellano"#,
        "de": #"\bde(u|ger)?\b|german|deutsch"#,
        "it": #"\bit(a)?\b|italian|italiano"#,
        "pt": #"\bpt|por(t)?\b|portuguese|portugu[eê]s"#,
        "ja": #"\bja(p)?\b|japanese|japonais"#,
    ]

    static func matchesLanguage(_ name: String, _ language: String) -> Bool {
        contains(name, languageKeywords[language] ?? "\\b\(language)\\b")
    }

    private static func isForced(_ name: String) -> Bool { contains(name, #"forc"#) }

    private static func isExtra(_ name: String) -> Bool {
        contains(name, #"comment|audio ?description|\bAD\b|\(AD\)"#)
    }

    private static func contains(_ name: String, _ pattern: String) -> Bool {
        name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
