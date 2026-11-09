import Foundation

public enum StremioError: LocalizedError, Equatable {
    case invalidURL
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Adresse invalide."
        case .badStatus(let code): return "Le serveur a répondu avec l'erreur \(code)."
        }
    }
}

/// Network boundary for Cinemeta and stream addons; stubbed in tests.
public protocol StremioProviding: Sendable {
    func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem]
    func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem]
    func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail
    /// Queries every addon in parallel; a failing addon is skipped, not fatal.
    func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem]
}

public struct StremioService: StremioProviding {
    private let cinemetaBase = "https://v3-cinemeta.strem.io"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem] {
        let extra = genre.map { "/genre=\(Self.encodePathComponent($0))" } ?? ""
        let response: CatalogResponse = try await get("\(cinemetaBase)/catalog/\(type.rawValue)/top\(extra).json")
        return response.metas
    }

    public func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: CatalogResponse = try await get(
            "\(cinemetaBase)/catalog/\(type.rawValue)/top/search=\(Self.encodePathComponent(trimmed)).json"
        )
        return response.metas
    }

    public func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail {
        let response: MetaDetailResponse = try await get("\(cinemetaBase)/meta/\(type.rawValue)/\(id).json")
        return response.meta
    }

    public func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem] {
        await withTaskGroup(of: (Int, [StreamItem]).self) { group in
            for (index, base) in addonBaseURLs.enumerated() {
                group.addTask {
                    let response: StreamsResponse? = try? await get("\(base)/stream/\(type.rawValue)/\(id).json", timeout: 15)
                    return (index, response?.streams ?? [])
                }
            }
            var byAddon: [(Int, [StreamItem])] = []
            for await result in group { byAddon.append(result) }
            // Keep the user's addon order so it acts as a tie-breaker in ranking.
            return byAddon.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    private func get<T: Decodable>(_ endpoint: String, timeout: TimeInterval = 20) async throws -> T {
        guard let url = URL(string: endpoint) else { throw StremioError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func encodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
