import SwiftUI

public struct SearchCatalogView: View {
    @StateObject private var service = StremioService.shared
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var selectedItem: MediaItem?
    @State private var filter: SearchFilter = .all
    
    private enum SearchFilter: String, CaseIterable {
        case all = "Tout"
        case movie = "Films"
        case series = "Séries"
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: 28)
    ]
    
    private var filteredResults: [MediaItem] {
        switch filter {
        case .all:
            return results
        case .movie:
            return results.filter { $0.type == "movie" }
        case .series:
            return results.filter { $0.type == "series" }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Search Bar
                    HStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.gray)
                        
                        TextField("Rechercher un film ou une série...", text: $query)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .onSubmit {
                                performSearch()
                            }
                        
                        if !query.isEmpty {
                            Button {
                                query = ""
                                results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 54)
                    .padding(.top, 28)
                    
                    // Filter Pills
                    if !results.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(SearchFilter.allCases, id: \.self) { f in
                                Button {
                                    filter = f
                                } label: {
                                    Text(f.rawValue)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(filter == f ? .black : .white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(filter == f ? Color.white : Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            Text("\(filteredResults.count) résultats")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 54)
                    }
                    
                    if isSearching {
                        Spacer()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.6)
                            Text("Recherche de \"\(query)\"...")
                                .font(.system(size: 19))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        VStack(spacing: 14) {
                            Image(systemName: "questionmark.folder")
                                .font(.system(size: 54))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Aucun résultat pour \"\(query)\"")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Vérifiez l'orthographe ou essayez un autre mot-clé.")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else if results.isEmpty {
                        Spacer()
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 58))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("Explorez des milliers de films et séries")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Entrez un titre dans la barre de recherche ci-dessus.")
                                .font(.system(size: 17))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 36) {
                                ForEach(filteredResults) { item in
                                    MediaCardView(item: item) {
                                        selectedItem = item
                                    }
                                }
                            }
                            .padding(.horizontal, 54)
                            .padding(.bottom, 64)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
    }
    
    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        Task {
            async let movies = service.searchCatalog(type: "movie", query: query)
            async let series = service.searchCatalog(type: "series", query: query)
            let combined = await (movies + series)
            results = combined
            isSearching = false
        }
    }
}