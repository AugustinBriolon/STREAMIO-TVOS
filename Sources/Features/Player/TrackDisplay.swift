import Foundation

/// Formatage lisible et localisé en français des pistes audio et sous-titres exposées par VLC/MKV.
/// Corrige les noms tronqués du type "Track 4" ou "European" en conservant/traduisant la langue réelle.
enum TrackDisplay {
    private static let languageMap: [String: String] = [
        "french": "Français", "fre": "Français", "fra": "Français", "fr": "Français",
        "english": "Anglais", "eng": "Anglais", "en": "Anglais",
        "spanish": "Espagnol", "spa": "Espagnol", "es": "Espagnol", "castilian": "Espagnol",
        "portuguese": "Portugais", "por": "Portugais", "pt": "Portugais",
        "german": "Allemand", "ger": "Allemand", "deu": "Allemand", "de": "Allemand",
        "italian": "Italien", "ita": "Italien", "it": "Italien",
        "japanese": "Japonais", "jpn": "Japonais", "ja": "Japonais",
        "korean": "Coréen", "kor": "Coréen", "ko": "Coréen",
        "dutch": "Néerlandais", "dut": "Néerlandais", "nld": "Néerlandais", "nl": "Néerlandais",
        "polish": "Polonais", "pol": "Polonais", "pl": "Polonais",
        "russian": "Russe", "rus": "Russe", "ru": "Russe",
        "arabic": "Arabe", "ara": "Arabe", "ar": "Arabe",
        "chinese": "Chinois", "chi": "Chinois", "zho": "Chinois", "zh": "Chinois",
        "turkish": "Turc", "tur": "Turc", "tr": "Turc",
        "swedish": "Suédois", "swe": "Suédois", "sv": "Suédois",
        "norwegian": "Norvégien", "nor": "Norvégien", "no": "Norvégien",
        "danish": "Danois", "dan": "Danois", "da": "Danois",
        "finnish": "Finnois", "fin": "Finnois", "fi": "Finnois",
        "greek": "Grec", "gre": "Grec", "ell": "Grec", "el": "Grec",
        "czech": "Tchèque", "cze": "Tchèque", "ces": "Tchèque", "cs": "Tchèque",
        "hungarian": "Hongrois", "hun": "Hongrois", "hu": "Hongrois",
        "romanian": "Roumain", "rum": "Roumain", "ron": "Roumain", "ro": "Roumain",
        "hindi": "Hindi", "hin": "Hindi", "hi": "Hindi",
        "thai": "Thaï", "tha": "Thaï", "th": "Thaï",
        "vietnamese": "Vietnamien", "vie": "Vietnamien", "vi": "Vietnamien",
        "hebrew": "Hébreu", "heb": "Hébreu", "he": "Hébreu",
        "ukrainian": "Ukrainien", "ukr": "Ukrainien", "uk": "Ukrainien",
    ]

    /// Traduit un code ISO ou nom anglais de langue en libellé français propre.
    static func localizedLanguageName(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.lowercased() != "und", cleaned.lowercased() != "undetermined" else { return nil }
        if let mapped = languageMap[cleaned.lowercased()] {
            return mapped
        }
        if let localized = Locale(identifier: "fr_FR").localizedString(forLanguageCode: cleaned) {
            return localized.prefix(1).uppercased() + localized.dropFirst()
        }
        return cleaned
    }

    /// Transforme une piste brute VLC (ex: "Track 4 - [French]", "European - [Spanish]", "DTS-HD - Français @ 3584 kb/s - [French]")
    /// en titre lisible sans jamais perdre l'information de langue.
    static func title(_ name: String) -> String {
        // 1. Extraire la langue entre crochets en fin de chaîne si présente : "... - [French]"
        var bracketLanguage: String?
        var base = name
        if let range = name.range(of: #"\s*-\s*\[([^\]]+)\]\s*$"#, options: .regularExpression) {
            let suffix = String(name[range])
            if let open = suffix.firstIndex(of: "["), let close = suffix.lastIndex(of: "]"), open < close {
                let rawLang = String(suffix[suffix.index(after: open)..<close])
                bracketLanguage = localizedLanguageName(rawLang)
            }
            base = String(name[..<range.lowerBound])
        }

        // 2. Nettoyer les bitrates ("@ 3584 kb/s") et espaces superflus
        base = base
            .replacingOccurrences(of: #"\s*@\s*[0-9.,]+\s*[kKmM]?[bB](?:/s|ps)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Traduire les qualificatifs génériques/régionaux courants lorsqu'ils apparaissent seuls
        let lower = base.lowercased()
        let isGenericTrack = lower.range(of: #"^track\s+\d+$"#, options: .regularExpression) != nil
        let regionalQualifiers: [(pattern: String, replacement: String)] = [
            (#"^european$"#, "Européen"),
            (#"^latin\s*american$"#, "Amérique latine"),
            (#"^forced$"#, "Forcés"),
            (#"^full$"#, "Complets"),
            (#"^subtitles?$"#, "Complets"),
            (#"^sdh$"#, "SDH"),
            (#"^cc$"#, "Sous-titres codés"),
            (#"^hearing\s*impaired$"#, "Malentendants"),
        ]

        var matchedQualifier: String?
        for item in regionalQualifiers {
            if lower.range(of: item.pattern, options: .regularExpression) != nil {
                matchedQualifier = item.replacement
                break
            }
        }

        if let lang = bracketLanguage {
            if isGenericTrack {
                let trackNum = base.replacingOccurrences(of: #"(?i)track\s+"#, with: "", options: .regularExpression)
                return "\(lang) · Piste \(trackNum)"
            }
            if let qual = matchedQualifier {
                return "\(lang) (\(qual))"
            }
            if base.isEmpty {
                return lang
            }
            // Vérifier si `base` contient déjà le nom de la langue (en français ou en anglais)
            let alreadyContainsLang = lower.contains(lang.lowercased())
                || (languageMap.first { $0.value == lang && lower.contains($0.key) } != nil)
            if alreadyContainsLang {
                return base
            }
            return "\(lang) — \(base)"
        }

        // Sans crochets [Lang] : nettoyer "Track X" -> "Piste X" et "European" -> "Européen"
        if isGenericTrack {
            let trackNum = base.replacingOccurrences(of: #"(?i)track\s+"#, with: "", options: .regularExpression)
            return "Piste \(trackNum)"
        }
        if let qual = matchedQualifier {
            return qual
        }
        return base.isEmpty ? name : base
    }
}
