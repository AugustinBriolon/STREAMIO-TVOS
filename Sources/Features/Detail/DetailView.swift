import SwiftUI

/// Title page: hero, actions, seasons/episodes and similar titles.
struct DetailView: View {
    @State private var model: DetailViewModel
    @State private var sourcePicker: SourcePickerTarget?
    @State private var pickedStream: (target: SourcePickerTarget, stream: StreamItem)?
    @State private var preferences = AppPreferences.shared
    @Environment(AddonStore.self) private var addons
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: String?
    @State private var playOrigin: String?
    /// Turns true on first appearance; coming back from a pushed page does not replay the entrance.
    @State private var heroShown = false

    init(item: MediaItem) {
        _model = State(initialValue: DetailViewModel(item: item))
    }

    private var resume: PlaybackProgress? {
        library.resumeEntry(forTitle: model.summary.id, aliases: model.idAliases)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                switch model.state {
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await model.loadIfNeeded(resumeSeason: resume?.video?.season) } })
                        .frame(height: 400)
                        .transition(.opacity)
                case .loaded:
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        if !model.distinctions.isEmpty { awardsSection }
                        if model.item.type == .series { episodesSection }
                        if !model.castMembers.isEmpty {
                            ShelfRow("Distribution", items: model.castMembers) { member in
                                NavigationLink(value: member) {
                                    CastCard(member: member)
                                }
                                .buttonStyle(PlainFocusStyle())
                            }
                        }
                        if !model.similar.isEmpty {
                            ShelfRow("Titres similaires", items: model.similar) { item in
                                NavigationLink(value: item) { PosterCard(item: item) }
                                    .buttonStyle(CardFocusStyle())
                            }
                        }
                    }
                    .transition(.opacity)
                case .idle, .loading:
                    ShelfSkeleton(cardSize: model.item.type == .series ? Theme.Card.episodeSize : Theme.Card.posterSize)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .animation(Theme.Motion.fade, value: model.state)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.Palette.canvas)
        .navigationDestination(for: CastMember.self) { member in
            PersonDetailView(member: member)
        }
        .task { await model.loadIfNeeded(resumeSeason: resume?.video?.season) }
        .task(id: "\(model.state == .loaded)-\(addons.activeURLs.joined(separator: ","))") {
            guard model.state == .loaded else { return }
            await model.checkAvailability(addons: addons.activeURLs, targetVideoID: resume?.video?.id, device: .current)
        }
        .restoresFocusAfterPlayback($focused, to: playOrigin)
        .sheet(item: $sourcePicker, onDismiss: playPickedStream) { target in
            StreamsView(
                type: model.item.type,
                videoID: target.videoID,
                title: target.title,
                initialStreams: model.prefetchedStreams(for: target.videoID)
            ) { stream in
                pickedStream = (target, stream)
            }
        }
    }

    // MARK: Hero

    /// Hero = décision de lecture : identité, méta, pitch court, reprise, CTA, statut sources.
    private var hero: some View {
        let item = model.summary
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            LogoTitle(name: item.name, logoURL: item.logoURL)
                .stagedEntrance(0, shown: heroShown, reduceMotion: reduceMotion)
            MetaLine(rating: item.displayRating, components: item.metaComponents)
                .stagedEntrance(1, shown: heroShown, reduceMotion: reduceMotion)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
                    .stagedEntrance(1, shown: heroShown, reduceMotion: reduceMotion)
            }
            if let resume, resume.position > 0 {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressBar(fraction: resume.fraction).frame(width: 300)
                    if let remaining = resume.remainingLabel {
                        Text(remaining).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            if preferences.showWatchProviders,
               let providers = model.detail?.watchProviders,
               !providers.isEmpty {
                watchProvidersSection(providers)
            }
            actions
                .stagedEntrance(2, shown: heroShown, reduceMotion: reduceMotion)
            availabilityNotice
        }
        .onAppear { heroShown = true }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.billboardHeight, alignment: .bottomLeading)
        // Fixed height + pinned backdrop URL: avoid layout jump when secondary metadata arrives below.
        .background(alignment: .top) {
            BakedBackdrop(url: model.backdropURL, dimming: 0.3)
                .frame(height: Theme.Layout.backdropHeight)
                .ignoresSafeArea()
        }
        .focusSection()
    }

    /// Façade SVOD : tuiles verre sombre alignées BrandHub (pas de pastilles blanches).
    private func watchProvidersSection(_ providers: [WatchProvider]) -> some View {
        let shown = Array(providers.prefix(4))
        let tile: CGFloat = 44
        let radius: CGFloat = 11
        return HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("Disponible sur")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(shown) { provider in
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color(white: 0.12).opacity(0.9))
                        RemoteImage(url: provider.logoURL, maxPixel: 80, showsPlaceholder: false, contentMode: .fit)
                            .padding(7)
                    }
                    .frame(width: tile, height: tile)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .accessibilityLabel(provider.name)
                }
                if providers.count > shown.count {
                    Text("+\(providers.count - shown.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isUnavailable: Bool {
        switch model.availability {
        case .unavailable, .noAddons: true
        default: false
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(resume?.resumeButtonTitle ?? model.primaryPlayTitle, systemImage: "play.fill") {
                if isUnavailable && model.item.type == .movie {
                    sourcePicker = SourcePickerTarget(video: nil, videoID: model.summary.id, title: model.summary.name)
                } else {
                    playOrigin = "play"
                    Task { await playback.play(item: model.summary, video: resume?.video, episodes: model.detail?.videos) }
                }
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .focused($focused, equals: "play")

            MyListButton(isInMyList: library.isInMyList(anyOf: model.idAliases)) {
                library.toggleMyList(model.summary, aliases: model.idAliases)
            }

            if model.item.type == .movie {
                Button("Choisir une source", systemImage: "list.bullet") {
                    sourcePicker = SourcePickerTarget(video: nil, videoID: model.summary.id, title: model.summary.name)
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var availabilityDotColor: Color {
        switch model.availability {
        case .idle, .checking: Theme.Palette.textTertiary
        case .available: Theme.Palette.match
        case .unavailable, .noAddons: Theme.Palette.accent
        }
    }

    private var availabilityLabel: String {
        switch model.availability {
        case .idle, .checking:
            "Vérification des sources…"
        case .available(let playableCount, _):
            "\(playableCount) source\(playableCount > 1 ? "s" : "") disponible\(playableCount > 1 ? "s" : "")"
        case .unavailable(let notices, let totalCount):
            unavailableSummary(notices: notices, totalCount: totalCount)
        case .noAddons:
            "Bande-annonce indisponible — ajoutez un add-on pour lire"
        }
    }

    private var availabilityNotice: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(availabilityDotColor)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .frame(width: 10, height: 10)
            Text(availabilityLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .animation(reduceMotion ? nil : Theme.Motion.fade, value: model.availability)
    }

    private func unavailableSummary(notices: [String], totalCount: Int) -> String {
        if let first = notices.first {
            return "Aucune source lisible — \(first)"
        }
        if totalCount > 0 {
            return "Aucune source compatible (\(totalCount) filtrée\(totalCount > 1 ? "s" : ""))"
        }
        return "Aucune source disponible"
    }

    // MARK: Distinctions

    private var awardsSection: some View {
        ShelfRow("Distinctions", items: model.distinctions) { distinction in
            AwardDistinctionCard(distinction: distinction)
        }
    }

    // MARK: Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if model.seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(model.seasons, id: \.self) { season in
                            Button(DetailViewModel.seasonLabel(season)) { model.selectedSeason = season }
                                .buttonStyle(ChipButtonStyle(isSelected: model.selectedSeason == season))
                        }
                    }
                    .padding(.leading, Theme.Spacing.gutter)
                    .padding(.trailing, Theme.Spacing.gutter + 90)
                    .padding(.vertical, Theme.Spacing.m)
                }
                .scrollIndicators(.hidden)
                .padding(.trailing, -90)
                .horizontalEdgeFade()
                .focusSection()
            }
            ShelfRow("Épisodes", items: model.episodesInSelectedSeason) { episode in
                episodeCard(episode)
            }
        }
    }

    private func episodeCard(_ episode: VideoItem) -> some View {
        let progress = library.progress(for: episode.id)
        let watched = progress?.isFinished == true
        // The focused card grows 8 pt downwards: the overview must sit clear of it.
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                playOrigin = "episode-\(episode.id)"
                Task { await playback.play(item: model.summary, video: episode, episodes: model.episodes) }
            } label: {
                LandscapeCard(
                    imageURL: episode.thumbnailURL ?? model.summary.backgroundURL,
                    title: "\(episode.episodeNumber). \(episode.cleanName ?? "Épisode \(episode.episodeNumber)")",
                    subtitle: watched ? "Vu" : nil,
                    progress: watched ? nil : progress.map(\.fraction),
                    size: Theme.Card.episodeSize
                )
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, Theme.Palette.accent)
                            .padding(Theme.Spacing.s)
                    }
                }
            }
            .buttonStyle(CardFocusStyle())
            .focused($focused, equals: "episode-\(episode.id)")
            .contextMenu {
                Button("Choisir une source", systemImage: "list.bullet") {
                    sourcePicker = SourcePickerTarget(video: episode, videoID: episode.id, title: "\(model.summary.name) · \(episode.code)")
                }
            }
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(2)
                    .frame(width: Theme.Card.episodeSize.width, alignment: .leading)
            }
        }
    }

    private func playPickedStream() {
        guard let picked = pickedStream else { return }
        pickedStream = nil
        Task {
            await playback.play(item: model.summary, video: picked.target.video, episodes: model.detail?.videos, preferred: picked.stream)
        }
    }
}

struct SourcePickerTarget: Identifiable {
    let video: VideoItem?
    let videoID: String
    let title: String
    var id: String { videoID }
}

private struct AwardDistinctionCard: View {
    let distinction: AwardDistinction
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(distinction.won ? Theme.Palette.rating : Theme.Palette.surfaceRaised)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: distinction.won ? "trophy.fill" : "sparkles")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text(distinction.won
                     ? "\(distinction.shortCeremonyLabel) \(String(distinction.year))"
                     : "Nominé · \(distinction.shortCeremonyLabel) \(String(distinction.year))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(distinction.category)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(width: 340, height: 100, alignment: .leading)
        .background(isFocused ? Theme.Palette.surfaceRaised : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused ? 2 : 0)
        }
        .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: false, focusScale: 1.04, reduceMotion: reduceMotion))
        .animation(Theme.Motion.focus, value: isFocused)
        .focusable()
        .focused($isFocused)
    }
}
