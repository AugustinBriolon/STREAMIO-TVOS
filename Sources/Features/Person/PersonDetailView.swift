import SwiftUI

/// Vue détaillée d'un acteur/actrice selon les Human Interface Guidelines tvOS d'Apple :
/// En-tête cinématique avec photo ambient et badges optiques, sélecteur de filtres en capsules glassmorphism,
/// et grille de filmographie réactive avec focus natif Apple TV sur chaque affiche.
struct PersonDetailView: View {
    let member: CastMember
    @State private var model: PersonDetailViewModel

    private let columns = [
        GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)
    ]

    init(member: CastMember) {
        self.member = member
        _model = State(initialValue: PersonDetailViewModel(member: member))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroSection
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.top, Theme.Spacing.xl)

                switch model.state {
                case .idle, .loading:
                    loadingState
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await model.loadIfNeeded() } })
                        .frame(height: 360)
                case .loaded:
                    filmographySection
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()
                // Halo ambient diffus en haut pour enrichir le relief
                RadialGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 700
                )
                .ignoresSafeArea()
            }
        )
        .task { await model.loadIfNeeded() }
        .navigationDestination(for: MediaItem.self) { item in
            DetailView(item: item)
        }
    }

    // MARK: - En-tête Cinématique (Hero)

    private var heroSection: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            portrait
                .frame(width: 210, height: 210)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(model.name)
                    .font(.system(size: 54, weight: .bold, design: .default))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                if let badges = metadataBadges, !badges.isEmpty {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(badges, id: \.text) { badge in
                            HStack(spacing: 6) {
                                Image(systemName: badge.icon)
                                    .font(.system(size: 16, weight: .medium))
                                Text(badge.text)
                                    .font(.system(size: 18, weight: .medium))
                            }
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.07))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                        }
                    }
                }

                if let bio = model.biography, !bio.isEmpty {
                    Text(bio)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(3)
                        .lineSpacing(6)
                        .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var portrait: some View {
        ZStack {
            if let url = model.photoURL {
                RemoteImage(url: url, maxPixel: 210 * Theme.pixelScale)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Text(String(model.name.prefix(1)))
                            .font(.system(size: 80, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
            }

            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
        }
        .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 10)
    }

    private struct MetadataBadge {
        let icon: String
        let text: String
    }

    private var metadataBadges: [MetadataBadge]? {
        var badges: [MetadataBadge] = []
        if let birthday = model.birthday, !birthday.isEmpty {
            badges.append(MetadataBadge(icon: "calendar", text: birthday))
        }
        if let place = model.placeOfBirth, !place.isEmpty {
            badges.append(MetadataBadge(icon: "mappin.and.ellipse", text: place))
        }
        if model.totalCount > 0 {
            badges.append(MetadataBadge(icon: "film.stack", text: "\(model.totalCount) titres"))
        }
        return badges.isEmpty ? nil : badges
    }

    // MARK: - Section Filmographie

    private var filmographySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            filterBar
                .padding(.horizontal, Theme.Spacing.gutter)

            if model.filteredCredits.isEmpty {
                emptyFilterView
            } else {
                creditsGrid
                    .id(model.selectedFilter)
                    .transition(.opacity)
                    .padding(.horizontal, Theme.Spacing.gutter)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            ForEach(PersonFilter.allCases) { filter in
                Button {
                    withAnimation(Theme.Motion.fade) {
                        model.selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(filter.rawValue)
                        Text("(\(count(for: filter)))")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .opacity(0.85)
                    }
                }
                .buttonStyle(ChipButtonStyle(isSelected: model.selectedFilter == filter))
            }

            Spacer()
        }
    }

    private func count(for filter: PersonFilter) -> Int {
        switch filter {
        case .all: return model.totalCount
        case .movies: return model.movieCount
        case .series: return model.seriesCount
        }
    }

    private var emptyFilterView: some View {
        Text("Aucun titre disponible dans cette catégorie.")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.xl)
    }

    private var creditsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(model.filteredCredits) { credit in
                FilmographyCard(credit: credit)
            }
        }
        .focusSection()
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Chargement de la filmographie…")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

/// Carte de filmographie Apple TV :
/// Le bouton et le focus ring sont appliqués EXCLUSIVEMENT sur l'affiche (`PosterCard`).
/// Les textes (titre et rôle/année) sont positionnés proprement en dessous, avec un éclairage optique au focus.
private struct FilmographyCard: View {
    let credit: PersonCredit
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            NavigationLink(value: credit.toMediaItem()) {
                PosterCard(item: credit.toMediaItem())
            }
            .buttonStyle(CardFocusStyle())
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 3) {
                Text(credit.title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let year = credit.releaseYear {
                        Text(year)
                    }
                    if credit.releaseYear != nil && credit.character != nil {
                        Text("•")
                            .font(.system(size: 8))
                    }
                    if let character = credit.character {
                        Text(character)
                            .lineLimit(1)
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
            }
            .frame(width: Theme.Card.posterSize.width, alignment: .leading)
        }
    }
}
