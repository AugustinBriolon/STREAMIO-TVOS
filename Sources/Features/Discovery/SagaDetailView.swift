import SwiftUI

/// Saga page: the saga's own artwork as a hero, then its films numbered in release order.
/// Each curated saga carries an accent colour (`SagaCollection.curated`) used for the title rule
/// and the film numbers; other collections use plain white.
struct SagaDetailView: View {
    @State private var saga: SagaCollection
    @State private var state: LoadState = .idle
    private let service: StremioProviding

    private let columns = [
        GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap, alignment: .top)
    ]

    init(saga: SagaCollection, service: StremioProviding = StremioService()) {
        self._saga = State(initialValue: saga)
        self.service = service
    }

    private var accent: Color {
        saga.accentColorHex.map { Color(hex: $0) } ?? Theme.Palette.textPrimary
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                switch state {
                case .idle, .loading:
                    ShelfSkeleton()
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await load() } })
                        .frame(height: 360)
                case .loaded:
                    films.padding(.horizontal, Theme.Spacing.gutter)
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.Palette.canvas)
        .task { await load() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            Capsule().fill(accent).frame(width: 72, height: 6)
                .accessibilityHidden(true)
            Text(saga.displayName)
                .font(Theme.Typography.billboardTitle)
                .tracking(Theme.Typography.displayTracking)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
            Text(summaryLine)
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.Palette.textSecondary)
            if let overview = saga.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.sagaHeroHeight, alignment: .bottomLeading)
        .background(alignment: .top) {
            BakedBackdrop(url: saga.backdropURL, dimming: 0.3)
                .frame(height: Theme.Layout.backdropHeight)
                .ignoresSafeArea()
        }
    }

    private var summaryLine: String {
        let count = saga.parts.isEmpty ? saga.partsCount : saga.parts.count
        return ["\(count) film\(count > 1 ? "s" : "")", saga.yearSpan].compactMap { $0 }.joined(separator: " · ")
    }

    private var films: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(Array(saga.parts.enumerated()), id: \.element.id) { index, movie in
                SagaMovieCard(number: index + 1, movie: movie, accent: accent)
            }
        }
        .focusSection()
    }

    private func load() async {
        if !saga.parts.isEmpty {
            state = .loaded
            return
        }
        state = .loading
        let language = AppPreferences.shared.metadataLanguage
        if let full = await service.fetchCollection(collectionID: saga.tmdbCollectionID, language: language) {
            saga = full
            state = .loaded
        } else {
            state = .failed("Impossible de charger les films de la saga.")
        }
    }
}

/// A film of the saga: the poster holds the focus, its number, title and year sit below it.
private struct SagaMovieCard: View {
    let number: Int
    let movie: MediaItem
    let accent: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            NavigationLink(value: movie) {
                PosterCard(item: movie)
            }
            .buttonStyle(CardFocusStyle())
            .focused($isFocused)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("\(number)")
                    .font(Theme.Typography.rowTitle.monospacedDigit())
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(movie.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                        .lineLimit(2)
                    if let year = movie.releaseInfo, !year.isEmpty {
                        Text(year)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            .frame(width: Theme.Card.posterSize.width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Film \(number) : \(movie.name)")
    }
}
