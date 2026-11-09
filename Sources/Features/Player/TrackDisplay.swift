import Foundation

/// Readable track names: muxers append bitrates and a bracketed language to every title.
enum TrackDisplay {
    /// "DTS-HD Master Audio 5.1 - Français (VFF) @ 3584 kb/s - [French]" -> "DTS-HD Master Audio 5.1 - Français (VFF)".
    static func title(_ name: String) -> String {
        var title = name
            .replacingOccurrences(of: #"\s*@\s*[0-9.,]+\s*[kKmM]?[bB](?:/s|ps)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*\[[^\]]+\]\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = name }
        return title
    }
}
