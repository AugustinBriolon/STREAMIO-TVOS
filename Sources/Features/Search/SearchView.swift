import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()
    @Binding var path: NavigationPath
    /// Reports whether the root screen is showing (no title page pushed).
    @Binding var atRoot: Bool

    init(path: Binding<NavigationPath> = .constant(NavigationPath()), atRoot: Binding<Bool> = .constant(true)) {
        _path = path
        _atRoot = atRoot
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        results
                            .transition(.opacity)
                    }
                    .padding(.vertical, Theme.Spacing.l)
                    .animation(Theme.Motion.fade, value: model.state)
                }
                .scrollIndicators(.hidden)
            }
            .opensRailOnExit()
            .searchable(text: $model.query, prompt: "Films, séries…")
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
            .navigationDestination(for: CastMember.self) { PersonDetailView(member: $0) }
        }
        .task { await model.loadSuggestions() }
        .onChange(of: path.count) { _, count in atRoot = count == 0 }
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

/// Wrapping grid of posters with a title, shared by Search.
struct PosterGrid: View {
    let title: String?
    let items: [MediaItem]
    /// Called when a poster gains focus (pages use it to follow the focused title).
    var onFocus: ((MediaItem?) -> Void)?

    private let columns = [GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let title {
                Text(title).font(Theme.Typography.rowTitle)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
                ForEach(items) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }
                        .buttonStyle(CardFocusStyle(onFocus: { onFocus?(item) }))
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .focusSection()
    }
}
