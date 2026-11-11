import Foundation

/// What the Top Shelf shows for the active profile (ADR 0015, 0016): "Reprendre la lecture" first,
/// then "Ma liste" without the titles already being resumed.
/// Pure and Foundation-only so the app can test it and the extension can use it.
struct TopShelfSection: Equatable {
    enum Kind: Equatable { case continueWatching, myList }

    let kind: Kind
    let entries: [TopShelfEntry]

    var title: String {
        switch kind {
        case .continueWatching: return "Reprendre la lecture"
        case .myList: return "Ma liste"
        }
    }

    /// Each section shows at most this many items.
    static let limit = 10

    /// Sections of the active profile; empty when there is nothing to show.
    static func load(defaults: UserDefaults) -> [TopShelfSection] {
        guard let idString = defaults.string(forKey: StorageKey.activeProfile), let profileID = UUID(uuidString: idString) else { return [] }
        let decoder = JSONDecoder()
        let progress = defaults.data(forKey: StorageKey.progress(profileID)).flatMap { try? decoder.decode([PlaybackProgress].self, from: $0) } ?? []
        let myList = defaults.data(forKey: StorageKey.myList(profileID)).flatMap { try? decoder.decode([MediaItem].self, from: $0) } ?? []
        return make(progress: progress, myList: myList)
    }

    static func make(progress: [PlaybackProgress], myList: [MediaItem]) -> [TopShelfSection] {
        // Latest unfinished entry per title, newest first: the same rule as the in-app row.
        let resumable = Dictionary(grouping: progress, by: \.item.id)
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
            .filter { !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
        let resumingIDs = Set(resumable.map(\.item.id))

        let resumeEntries = resumable.map { entry in
            TopShelfEntry(
                id: "resume-\(entry.id)",
                title: [entry.item.name, entry.video.map { "\($0.code) · \($0.cleanName ?? "Épisode \($0.episodeNumber)")" }]
                    .compactMap { $0 }.joined(separator: " · "),
                imageURL: entry.video?.thumbnailURL ?? entry.item.backgroundURL,
                isPoster: false,
                // A queued next episode has no position yet: no bar rather than an empty one.
                progress: entry.position > 0 ? entry.fraction : nil,
                playLink: .resume(entry.id),
                displayLink: .details(entry.item.id)
            )
        }
        let listEntries = myList.filter { !resumingIDs.contains($0.id) }.prefix(limit).map { item in
            TopShelfEntry(
                id: "list-\(item.id)", title: item.name, imageURL: item.posterURL, isPoster: true, progress: nil,
                playLink: .play(item.id), displayLink: .details(item.id)
            )
        }
        return [
            TopShelfSection(kind: .continueWatching, entries: Array(resumeEntries)),
            TopShelfSection(kind: .myList, entries: Array(listEntries)),
        ].filter { !$0.entries.isEmpty }
    }
}

struct TopShelfEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let imageURL: URL?
    /// 2:3 poster, otherwise a 16:9 still.
    let isPoster: Bool
    let progress: Double?
    /// The Play button on the remote.
    let playLink: TopShelfLink
    /// Selecting the item.
    let displayLink: TopShelfLink
}

/// Links from the Top Shelf into the app:
/// `loge://resume?id=<movie or episode id>`, `loge://play?id=<title id>`, `loge://details?id=<title id>`.
enum TopShelfLink: Equatable {
    case resume(String)
    case play(String)
    case details(String)

    static let scheme = "loge"

    private var parts: (host: String, id: String) {
        switch self {
        case .resume(let id): return ("resume", id)
        case .play(let id): return ("play", id)
        case .details(let id): return ("details", id)
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = parts.host
        components.queryItems = [URLQueryItem(name: "id", value: parts.id)]
        return components.url!
    }

    /// Nil for anything that is not one of our links.
    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty else { return nil }
        switch url.host {
        case "resume": self = .resume(id)
        case "play": self = .play(id)
        case "details": self = .details(id)
        default: return nil
        }
    }
}
