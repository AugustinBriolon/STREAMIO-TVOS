import Foundation

@MainActor
public final class StremioService: ObservableObject {
    public static let shared = StremioService()
    
    private let cinemetaBase = "https://v3-cinemeta.strem.io"
    private let storageKey = "user_addon_urls_v2"
    
    @Published public var configuredAddonURLs: [String] {
        didSet {
            UserDefaults.standard.set(configuredAddonURLs, forKey: storageKey)
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            self.configuredAddonURLs = saved
        } else if let legacy = UserDefaults.standard.string(forKey: "user_addon_url"), !legacy.isEmpty {
            self.configuredAddonURLs = [legacy]
        } else {
            self.configuredAddonURLs = []
        }
    }
    
    public func addAddonURL(_ rawURL: String) {
        let clean = cleanURL(rawURL)
        guard !clean.isEmpty else { return }
        if !configuredAddonURLs.contains(clean) {
            configuredAddonURLs.append(clean)
        }
    }
    
    public func removeAddonURL(_ url: String) {
        configuredAddonURLs.removeAll { $0 == url }
    }
    
    public func removeAddon(at offsets: IndexSet) {
        configuredAddonURLs.remove(atOffsets: offsets)
    }
    
    private func cleanURL(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/manifest.json") {
            base = String(base.dropLast("/manifest.json".count))
        }
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        return base
    }
    
    public func fetchCatalog(type: String) async -> [MediaItem] {
        let endpoint = "\(cinemetaBase)/catalog/\(type)/top.json"
        guard let url = URL(string: endpoint) else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
            return decoded.metas
        } catch {
            return []
        }
    }
    
    public func searchCatalog(type: String, query: String) async -> [MediaItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encoded.isEmpty else { return [] }
        let endpoint = "\(cinemetaBase)/catalog/\(type)/top/search=\(encoded).json"
        guard let url = URL(string: endpoint) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
            return decoded.metas
        } catch {
            return []
        }
    }
    
    public func fetchDetails(type: String, id: String) async -> MediaDetail? {
        let endpoint = "\(cinemetaBase)/meta/\(type)/\(id).json"
        guard let url = URL(string: endpoint) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MetaDetailResponse.self, from: data)
            return decoded.meta
        } catch {
            return nil
        }
    }
    
    public func fetchStreams(type: String, id: String) async -> [StreamItem] {
        guard !configuredAddonURLs.isEmpty else { return [] }
        
        return await withTaskGroup(of: [StreamItem].self) { group in
            for addonBase in configuredAddonURLs {
                let endpoint = "\(addonBase)/stream/\(type)/\(id).json"
                guard let url = URL(string: endpoint) else { continue }
                
                group.addTask {
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 12
                        let (data, _) = try await URLSession.shared.data(for: request)
                        let decoded = try JSONDecoder().decode(StreamsResponse.self, from: data)
                        return decoded.streams ?? []
                    } catch {
                        return []
                    }
                }
            }
            
            var allStreams: [StreamItem] = []
            for await streams in group {
                allStreams.append(contentsOf: streams)
            }
            
            return allStreams.sorted { a, b in
                let rank = { (s: StreamItem) -> Int in
                    if s.resolution == "4K" { return 0 }
                    if s.resolution == "1080p" { return 1 }
                    if s.resolution == "720p" { return 2 }
                    return 3
                }
                return rank(a) < rank(b)
            }
        }
    }
}
