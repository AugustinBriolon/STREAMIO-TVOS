import SwiftUI

/// Accueil / Films / Séries: billboard followed by personal and catalog rows.
struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @FocusState private var focused: String?
    @State private var lastFocusedToken: String?
    @State private var pendingFocusToken: String?
    @State private var focusRestoreTarget: String?
    @State private var focusRestoreTask: Task<Void, Never>?
    @State private var playOrigin: String?
    @State private var backdrop = BackdropModel()
    @Namespace private var zoomNamespace
    @State private var zoomSource = ZoomSource()

    @Binding private var path: NavigationPath
    /// A title to show on top of this page (Top Shelf link); consumed once pushed.
    @Binding private var linkedTitle: MediaItem?

    init(scope: MediaType?, path: Binding<NavigationPath> = .constant(NavigationPath()), linkedTitle: Binding<MediaItem?> = .constant(nil)) {
        _model = State(initialValue: HomeViewModel(scope: scope))
        _path = path
        _linkedTitle = linkedTitle
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DynamicBackdrop(model: backdrop, fallback: model.billboard)
                // The catalog fades in once loaded instead of replacing the spinner in one frame.
                content
                    .transition(.opacity)
                    .animation(Theme.Motion.fade, value: model.state)
            }
            .opensRailOnExit(when: path.isEmpty)
            .navigationDestination(for: MediaItem.self) {
                DetailView(item: $0).navigationTransition(.zoom(sourceID: zoomSource.id, in: zoomNamespace))
            }
            .navigationDestination(for: CastMember.self) { PersonDetailView(member: $0) }
            .navigationDestination(for: BrandHub.self) { HubCatalogView(hub: $0) }
            .navigationDestination(for: SagaCollection.self) { SagaDetailView(saga: $0) }
        }
        .restoresFocusAfterPlayback($focused, to: playOrigin)
        .task { await model.loadIfNeeded() }
        .onChange(of: focused) { _, newValue in
            if let newValue {
                lastFocusedToken = newValue
            }
        }
        .onChange(of: scopedMyList.map(\.id)) { oldIDs, newIDs in
            guard let last = lastFocusedToken,
                  last.hasPrefix("mylist-") else { return }
            let removedID = String(last.dropFirst(7))
            guard oldIDs.contains(removedID), !newIDs.contains(removedID) else { return }
            let nextID = FocusNeighbor.nearestRemaining(oldIDs: oldIDs, newIDs: newIDs, removedID: removedID)
            let nextToken = nextID.map { "mylist-\($0)" } ?? (model.billboard != nil ? "billboard" : nil)
            guard let nextToken else { return }
            if path.isEmpty {
                restoreFocusSoon(nextToken)
            } else {
                pendingFocusToken = nextToken
            }
        }
        .onChange(of: path.count) { _, count in
            guard count == 0, let nextToken = pendingFocusToken else { return }
            pendingFocusToken = nil
            restoreFocusSoon(nextToken)
        }
        .onChange(of: linkedTitle, initial: true) { _, item in
            guard let item else { return }
            path = NavigationPath([item])
            linkedTitle = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            CatalogSkeleton()
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
                            onPlay: { play(from: "billboard") { await playback.play(item: billboard) } },
                            onToggleMyList: { library.toggleMyList(billboard) },
                            playFocus: $focused,
                            onFocus: { markFocused("billboard", backdropItem: nil) }
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
                Button {
                    play(from: "resume-\(entry.item.id)") { await playback.play(item: entry.item, video: entry.video) }
                } label: {
                    LandscapeCard(
                        imageURL: entry.video?.thumbnailURL ?? entry.item.backgroundURL,
                        title: entry.item.name,
                        subtitle: entry.video.map { "\($0.code) · \($0.cleanName ?? "")" },
                        progress: entry.fraction
                    )
                }
                .buttonStyle(CardFocusStyle(onFocus: { markFocused("resume-\(entry.item.id)", backdropItem: entry.item) }))
                .focused($focused, equals: "resume-\(entry.item.id)")
                // Long press on the clickpad.
                .contextMenu {
                    Button("Retirer de Reprendre la lecture", systemImage: "xmark.circle", role: .destructive) {
                        removeContinueWatching(entry, from: resumable)
                    }
                    Button(library.isInMyList(entry.item.id) ? "Retirer de Ma liste" : "Ajouter à Ma liste",
                           systemImage: library.isInMyList(entry.item.id) ? "checkmark" : "plus") {
                        library.toggleMyList(entry.item)
                    }
                }
            }
        }

        switch model.scope {
        case .movie:
            movieContentRows
        case .series:
            seriesContentRows
        case nil:
            homeContentRows
        }
    }

    @ViewBuilder
    private var movieContentRows: some View {
        if !model.nowPlaying.isEmpty {
            posterRow("Actuellement au cinéma", items: model.nowPlaying)
        }

        hubRow("Plateformes de streaming", hubs: model.moviePlatforms)

        if !model.trendingWeek.isEmpty {
            posterRow("Tendances de la semaine", items: model.trendingWeek)
        }

        if !model.top10.isEmpty {
            top10Row
        }

        if !model.sagas.isEmpty {
            sagaRow("Sagas & Franchises", sagas: model.sagas)
        }

        hubRow("Studios de cinéma", hubs: model.movieStudios)

        if !model.awardedMovies.isEmpty {
            awardedMediaRow("Films primés", entries: model.awardedMovies)
        }

        let myList = scopedMyList
        if !myList.isEmpty {
            myListRow(items: myList)
        }

        ForEach(model.shelves) { shelf in
            posterRow(shelf.title, items: shelf.items)
        }
    }

    @ViewBuilder
    private var seriesContentRows: some View {
        if !model.trendingWeek.isEmpty {
            posterRow("Tendances de la semaine", items: model.trendingWeek)
        }

        hubRow("Plateformes de streaming", hubs: model.seriesPlatforms)

        if !model.top10.isEmpty {
            top10Row
        }

        hubRow("Studios & Chaînes de prestige", hubs: model.seriesNetworks)

        if !model.awardedSeries.isEmpty {
            awardedMediaRow("Séries primées", entries: model.awardedSeries)
        }

        let myList = scopedMyList
        if !myList.isEmpty {
            myListRow(items: myList)
        }

        ForEach(model.shelves) { shelf in
            posterRow(shelf.title, items: shelf.items)
        }
    }

    @ViewBuilder
    private var homeContentRows: some View {
        if !model.top10.isEmpty {
            top10Row
        }

        if !model.trendingWeek.isEmpty {
            posterRow("Tendances de la semaine", items: model.trendingWeek)
        }

        hubRow("Plateformes de streaming", hubs: model.moviePlatforms)

        if !model.nowPlaying.isEmpty {
            posterRow("Actuellement au cinéma", items: model.nowPlaying)
        }

        if !model.sagas.isEmpty {
            sagaRow("Sagas & Franchises", sagas: model.sagas)
        }

        if !model.awardedMovies.isEmpty {
            awardedMediaRow("Films primés", entries: model.awardedMovies)
        }

        if !model.awardedSeries.isEmpty {
            awardedMediaRow("Séries primées", entries: model.awardedSeries)
        }

        let myList = scopedMyList
        if !myList.isEmpty {
            myListRow(items: myList)
        }

        ForEach(model.shelves) { shelf in
            posterRow(shelf.title, items: shelf.items)
        }
    }

    private var top10Row: some View {
        ShelfRow(model.top10Title, items: Array(model.top10.enumerated()), id: \.element.id) { entry in
            NavigationLink(value: entry.element) {
                Top10Card(rank: entry.offset + 1, item: entry.element)
            }
            .buttonStyle(CardFocusStyle(showsSheen: false, onFocus: { backdrop.focus(entry.element) }))
        }
    }

    private func hubRow(_ title: String, hubs: [BrandHub]) -> some View {
        ShelfRow(title, items: hubs) { hub in
            NavigationLink(value: hub) {
                BrandHubCard(hub: hub)
            }
            .buttonStyle(CardFocusStyle(showsRing: true, onFocus: { backdrop.focus(nil) }))
        }
    }

    private var scopedMyList: [MediaItem] {
        guard let scope = model.scope else { return library.myList }
        return library.myList.filter { $0.type == scope }
    }

    private func myListRow(items: [MediaItem]) -> some View {
        ShelfRow("Ma liste", items: items) { item in
            NavigationLink(value: item) { PosterCard(item: item) }
                .buttonStyle(CardFocusStyle(onFocus: { markFocused("mylist-\(item.id)", backdropItem: item) }))
                .focused($focused, equals: "mylist-\(item.id)")
                .contextMenu {
                    Button("Retirer de Ma liste", systemImage: "xmark.circle", role: .destructive) {
                        removeFromMyList(item, in: items)
                    }
                }
        }
    }

    private func markFocused(_ token: String, backdropItem: MediaItem?) {
        backdrop.focus(backdropItem)
        lastFocusedToken = token
        if focusRestoreTarget == token {
            focusRestoreTarget = nil
            focusRestoreTask?.cancel()
        }
    }

    private func removeContinueWatching(_ entry: PlaybackProgress, from resumable: [PlaybackProgress]) {
        let nextID = FocusNeighbor.nearestRemainingID(in: resumable.map(\.item.id), removing: entry.item.id)
        let targetToken = nextID.map { "resume-\($0)" } ?? (model.billboard != nil ? "billboard" : nil)
        lastFocusedToken = nil
        pendingFocusToken = nil
        library.removeFromContinueWatching(titleID: entry.item.id)
        TopShelfRefresher.refresh()
        if let targetToken {
            restoreFocusSoon(targetToken)
        }
    }

    private func removeFromMyList(_ item: MediaItem, in items: [MediaItem]) {
        let nextID = FocusNeighbor.nearestRemainingID(in: items.map(\.id), removing: item.id)
        let targetToken = nextID.map { "mylist-\($0)" } ?? (model.billboard != nil ? "billboard" : nil)
        lastFocusedToken = nil
        pendingFocusToken = nil
        library.toggleMyList(item)
        if let targetToken {
            restoreFocusSoon(targetToken)
        }
    }

    private func restoreFocusSoon(_ targetToken: String) {
        focusRestoreTarget = targetToken
        FocusRestorer.schedule(
            target: targetToken,
            focus: $focused,
            currentTask: &focusRestoreTask,
            isStillPending: { focusRestoreTarget == targetToken },
            onExhausted: { if focusRestoreTarget == targetToken { focusRestoreTarget = nil } }
        )
    }

    private func awardedMediaRow(_ title: String, entries: [AwardedMediaEntry]) -> some View {
        ShelfRow(title, items: entries) { entry in
            AwardedMediaCard(entry: entry, onFocus: { backdrop.focus(entry.item) })
        }
    }

    private func sagaRow(_ title: String, sagas: [SagaCollection]) -> some View {
        ShelfRow(title, items: sagas) { saga in
            NavigationLink(value: saga) {
                SagaCard(saga: saga)
            }
            .buttonStyle(CardFocusStyle(onFocus: { backdrop.focus(saga.backdropItem) }))
        }
    }

    private func play(from origin: String, _ start: @escaping () async -> Void) {
        playOrigin = origin
        Task { await start() }
    }

    private func posterRow(_ title: String, items: [MediaItem]) -> some View {
        ShelfRow(title, items: items) { item in
            let sourceID = "\(title)-\(item.id)"
            NavigationLink(value: item) { PosterCard(item: item) }
                .buttonStyle(CardFocusStyle(onFocus: {
                    backdrop.focus(item)
                    zoomSource.id = sourceID
                }))
                // After CardFocusStyle: source morph must keep the poster radius (before scale it squares corners).
                .matchedTransitionSource(id: sourceID, in: zoomNamespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
        }
    }
}

/// The poster the title page zooms out of: the last focused one. The same title can sit in several
/// rows, so the row is part of the identifier. A plain reference, not observed: writing it on every
/// focus change must not re-render the page.
private final class ZoomSource {
    var id = ""
}
