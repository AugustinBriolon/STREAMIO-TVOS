import Foundation
import Observation

public enum PersonFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Tout"
    case movies = "Films"
    case series = "Séries"

    public var id: String { rawValue }
}

@MainActor
@Observable
final class PersonDetailViewModel {
    let member: CastMember
    private(set) var detail: PersonDetail?
    private(set) var state: LoadState = .idle
    var selectedFilter: PersonFilter = .all

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(member: CastMember, service: StremioProviding = StremioService()) {
        self.member = member
        self.service = service
    }

    var name: String { detail?.name ?? member.name }
    var biography: String? { detail?.biography }
    var birthday: String? { detail?.birthday }
    var placeOfBirth: String? { detail?.placeOfBirth }
    var photoURL: URL? { detail?.photoURL ?? member.photoURL }

    var allCredits: [PersonCredit] { detail?.credits ?? [] }

    var movies: [PersonCredit] {
        allCredits.filter { $0.type == .movie }
    }

    var series: [PersonCredit] {
        allCredits.filter { $0.type == .series }
    }

    var filteredCredits: [PersonCredit] {
        switch selectedFilter {
        case .all: return allCredits
        case .movies: return movies
        case .series: return series
        }
    }

    var totalCount: Int { allCredits.count }
    var movieCount: Int { movies.count }
    var seriesCount: Int { series.count }

    func loadIfNeeded() async {
        if state == .idle || state.isFailure {
            loadTask = Task { await load() }
        }
        await loadTask?.value
    }

    private func load() async {
        state = .loading
        guard let personID = Int(member.id) else {
            state = .failed("Identifiant d'acteur invalide")
            return
        }

        let prefs = AppPreferences.shared
        if let personDetail = await service.fetchPerson(personID: personID, language: prefs.metadataLanguage) {
            detail = personDetail
            state = .loaded
        } else {
            state = .failed("Impossible de charger la filmographie de cet acteur.")
        }
    }
}
