import SwiftUI

/// Page détaillée pour une saga / franchise cinématographique (ex: Star Wars, Harry Potter, Dune).
struct SagaDetailView: View {
    let initialSaga: SagaCollection
    @State private var saga: SagaCollection
    @State private var state: LoadState = .idle
    private let service: StremioProviding

    private let columns = [
        GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)
    ]

    init(saga: SagaCollection, service: StremioProviding = StremioService()) {
        self.initialSaga = saga
        self._saga = State(initialValue: saga)
        self.service = service
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroHeader
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.top, Theme.Spacing.xl)

                switch state {
                case .idle, .loading:
                    StateView(kind: .loading("Chargement des films de la saga…"))
                        .frame(height: 360)
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await load() } })
                        .frame(height: 360)
                case .loaded:
                    partsGrid
                        .padding(.horizontal, Theme.Spacing.gutter)
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()
                if let backdropURL = saga.backdropURL {
                    RemoteImage(url: backdropURL, maxPixel: 1920)
                        .blur(radius: 40)
                        .opacity(0.25)
                        .ignoresSafeArea()
                }
            }
        )
        .task { await load() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text("SAGA & UNIVERS")
                    .font(Theme.Typography.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(Theme.Palette.accent.opacity(0.18))
                            .overlay {
                                Capsule().strokeBorder(Theme.Palette.accent.opacity(0.3), lineWidth: 1)
                            }
                    }

                Text("\(saga.parts.count > 0 ? saga.parts.count : saga.partsCount) volets")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Text(saga.name)
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(Theme.Palette.textPrimary)

            if let overview = saga.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
                    .lineLimit(4)
            }
        }
    }

    private var partsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Les films par ordre de sortie")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.cardGap) {
                ForEach(saga.parts) { movie in
                    SagaMovieCard(movie: movie)
                }
            }
        }
    }

    private func load() async {
        if !saga.parts.isEmpty {
            state = .loaded
            return
        }

        state = .loading
        let lang = AppPreferences.shared.metadataLanguage
        if let fullSaga = await service.fetchCollection(collectionID: saga.tmdbCollectionID, language: lang) {
            self.saga = fullSaga
            state = .loaded
        } else {
            state = .failed("Impossible de charger les films de la saga.")
        }
    }
}

/// Carte de film de saga reprenant exactement le design de `FilmographyCard` (fiche d'acteur) :
/// Le bouton et l'effet de focus s'appliquent EXCLUSIVEMENT à l'affiche (`PosterCard`).
/// Les textes (titre et date de sortie) sont disposés en dessous sans être englobés dans l'anneau de focus.
private struct SagaMovieCard: View {
    let movie: MediaItem
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            NavigationLink(value: movie) {
                PosterCard(item: movie)
            }
            .buttonStyle(CardFocusStyle())
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 3) {
                Text(movie.name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)

                if let year = movie.releaseInfo, !year.isEmpty {
                    Text(year)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: Theme.Card.posterSize.width, alignment: .leading)
        }
    }
}
