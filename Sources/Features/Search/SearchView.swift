import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    results
                }
                .padding(.vertical, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Palette.canvas)
            .searchable(text: $model.query, prompt: "Films, séries…")
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
        .task { await model.loadSuggestions() }
    }

    @ViewBuilder
    private var results: some View {
        if model.trimmedQuery.isEmpty {
            if !model.suggestions.isEmpty { PosterGrid(title: "Recherches populaires", items: model.suggestions) }
        } else {
            switch model.state {
            case .loading where !model.hasResults, .idle:
                StateView(kind: .loading("Recherche de « \(model.trimmedQuery) »…")).frame(height: 400)
            case .failed(let message):
                StateView(kind: .error(message) { model.query = model.query + "" }).frame(height: 500)
            default:
                if model.hasResults {
                    if !model.movies.isEmpty { PosterGrid(title: "Films", items: model.movies) }
                    if !model.series.isEmpty { PosterGrid(title: "Séries", items: model.series) }
                } else {
                    StateView(kind: .empty(
                        symbol: "magnifyingglass",
                        title: "Aucun résultat pour « \(model.trimmedQuery) »",
                        message: "Vérifiez l'orthographe ou essayez un autre titre."
                    ))
                    .frame(height: 500)
                }
            }
        }
    }
}

/// Wrapping grid of posters with a title, shared by Search and Ma liste.
struct PosterGrid: View {
    let title: String?
    let items: [MediaItem]

    private let columns = [GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let title {
                Text(title).font(Theme.Typography.rowTitle)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
                ForEach(items) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }
                        .buttonStyle(CardFocusStyle())
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .focusSection()
    }
}
