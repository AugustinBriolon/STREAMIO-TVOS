import Foundation

/// What the Top Shelf shows for the active profile: its "Reprendre la lecture" entries (ADR 0015).
/// Pure and Foundation-only so the app can test it and the extension can use it.
struct TopShelfEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let progress: Double
    let link: URL

    /// The Top Shelf shows at most this many items.
    static let limit = 10

    /// Active profile's unfinished titles, newest first, one entry per title.
    static func load(defaults: UserDefaults) -> [TopShelfEntry] {
        guard let idString = defaults.string(forKey: StorageKey.activeProfile), let profileID = UUID(uuidString: idString),
              let data = defaults.data(forKey: StorageKey.progress(profileID)),
              let entries = try? JSONDecoder().decode([PlaybackProgress].self, from: data) else { return [] }
        return make(from: entries)
    }

    static func make(from entries: [PlaybackProgress]) -> [TopShelfEntry] {
        let latestPerTitle = Dictionary(grouping: entries, by: \.item.id).compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        return latestPerTitle
            .filter { !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { entry in
                TopShelfEntry(
                    id: entry.id,
                    title: entry.item.name,
                    subtitle: entry.video.map { "\($0.code) · \($0.cleanName ?? "Épisode \($0.episodeNumber)")" },
                    imageURL: entry.video?.thumbnailURL ?? entry.item.backgroundURL ?? entry.item.posterURL,
                    progress: entry.fraction,
                    link: TopShelfLink.play(entry.id)
                )
            }
    }
}

/// `stremiotv://play?id=<movie id or episode id>`: resumes that entry in the active profile.
enum TopShelfLink {
    static let scheme = "stremiotv"

    static func play(_ progressID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "play"
        components.queryItems = [URLQueryItem(name: "id", value: progressID)]
        return components.url!
    }

    /// The entry id of a play link, nil for anything else.
    static func progressID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "play",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty else { return nil }
        return id
    }
}
