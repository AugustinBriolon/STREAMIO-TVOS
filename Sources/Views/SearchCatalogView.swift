import SwiftUI

public struct SearchCatalogView: View {
    @StateObject private var service = StremioService.shared
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var selectedItem: MediaItem?
    
    private let columns = [
        GridItem(.adaptive(minimum: 250), spacing: 32)
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                        TextField("Rechercher un film ou une série...", text: $query)
                            .font(.system(size: 24))
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
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(14)
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
                    
                    if isSearching {
                        Spacer()
                        ProgressView("Recherche en cours...")
                            .scaleEffect(1.5)
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        Text("Aucun résultat pour \"\(query)\"")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                        Spacer()
                    } else if results.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 54))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Tapez le titre d'un film ou d'une série")
                                .font(.system(size: 22))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(results) { item in
                                    MediaCardView(item: item) {
                                        selectedItem = item
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
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
