import SwiftUI

/// Accueil / Films / Séries: billboard followed by personal and catalog rows.
struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback

    init(scope: MediaType?) {
        _model = State(initialValue: HomeViewModel(scope: scope))
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Palette.canvas)
                .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            StateView(kind: .loading("Chargement du catalogue…"))
        case .failed(let message):
            StateView(kind: .error(message) { Task { await model.load() } })
        case .loaded:
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let billboard = model.billboard {
                        BillboardView(
                            item: billboard,
                            playTitle: library.resumeEntry(forTitle: billboard.id) == nil ? "Lecture" : "Reprendre",
                            isInMyList: library.isInMyList(billboard.id),
                            onPlay: { Task { await playback.play(item: billboard) } },
                            onToggleMyList: { library.toggleMyList(billboard) }
                        )
                    }
                    rows
                }
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private var rows: some View {
        let resumable = library.continueWatching(type: model.scope)
        if !resumable.isEmpty {
            ShelfRow("Reprendre la lecture", items: resumable) { entry in
                Button { Task { await playback.play(item: entry.item, video: entry.video) } } label: {
                    LandscapeCard(
                        imageURL: entry.video?.thumbnailURL ?? entry.item.backgroundURL,
                        title: entry.item.name,
                        subtitle: entry.video.map { "\($0.code) · \($0.cleanName ?? "")" },
                        progress: entry.fraction
                    )
                }
                .buttonStyle(CardFocusStyle())
            }
        }

        let myList = library.myList.filter { model.scope == nil || $0.type == model.scope }
        if !myList.isEmpty {
            posterRow("Ma liste", items: myList)
        }

        if !model.top10.isEmpty {
            ShelfRow(model.top10Title, items: Array(model.top10.enumerated()), id: \.element.id) { entry in
                NavigationLink(value: entry.element) {
                    Top10Card(rank: entry.offset + 1, item: entry.element)
                }
                .buttonStyle(CardFocusStyle(showsRing: false))
            }
        }

        ForEach(model.shelves) { shelf in
            posterRow(shelf.title, items: shelf.items)
        }
    }

    private func posterRow(_ title: String, items: [MediaItem]) -> some View {
        ShelfRow(title, items: items) { item in
            NavigationLink(value: item) { PosterCard(item: item) }
                .buttonStyle(CardFocusStyle())
        }
    }
}
