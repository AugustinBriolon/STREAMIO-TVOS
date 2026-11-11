import SwiftUI

/// Title page: hero, actions, seasons/episodes and similar titles.
struct DetailView: View {
    @State private var model: DetailViewModel
    @State private var sourcePicker: SourcePickerTarget?
    @State private var pickedStream: (target: SourcePickerTarget, stream: StreamItem)?
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @FocusState private var focused: String?
    @State private var playOrigin: String?

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
                        if !model.distinctions.isEmpty { awardsSection }
                    }
                    .transition(.opacity)
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
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
        .restoresFocusAfterPlayback($focused, to: playOrigin)
        .sheet(item: $sourcePicker, onDismiss: playPickedStream) { target in
            StreamsView(type: model.item.type, videoID: target.videoID, title: target.title) { stream in
                pickedStream = (target, stream)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let item = model.summary
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            LogoTitle(name: item.name, logoURL: item.logoURL)
            MetaLine(rating: item.displayRating, components: item.metaComponents)
            if !model.distinctions.isEmpty {
                heroDistinctionStrip
            }
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(4)
                    .frame(maxWidth: Theme.Layout.synopsisWidth, alignment: .leading)
            }
            credits
            if let resume, resume.position > 0 {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressBar(fraction: resume.fraction).frame(width: 300)
                    if let remaining = resume.remainingLabel {
                        Text(remaining).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            actions
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.billboardHeight, alignment: .bottomLeading)
        .background { BackdropView(url: item.backgroundURL).ignoresSafeArea() }
        .focusSection()
    }

    @ViewBuilder
    private var credits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if let cast = model.castLine { creditLine("Avec", cast) }
            if let director = model.directorLine { creditLine("Réalisation", director) }
        }
    }

    private func creditLine(_ label: String, _ value: String) -> some View {
        (Text("\(label) : ").foregroundStyle(Theme.Palette.textTertiary) + Text(value).foregroundStyle(Theme.Palette.textSecondary))
            .font(Theme.Typography.caption)
            .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(resume?.resumeButtonTitle ?? "Lecture", systemImage: "play.fill") {
                playOrigin = "play"
                Task { await playback.play(item: model.summary, video: resume?.video, episodes: model.detail?.videos) }
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

    // MARK: Distinctions

    @ViewBuilder
    private var heroDistinctionStrip: some View {
        if let primary = model.distinctions.first {
            let extra = model.distinctions.count - 1
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(primary.won ? Theme.Palette.rating : Theme.Palette.surfaceRaised)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: primary.won ? "trophy.fill" : "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }

                HStack(spacing: 6) {
                    Text(primary.won
                         ? "\(primary.shortCeremonyLabel) \(String(primary.year))"
                         : "Nominé · \(primary.shortCeremonyLabel) \(String(primary.year))")
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text("· \(primary.category)")
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)

                    if extra > 0 {
                        Text("· +\(extra)")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .font(Theme.Typography.meta)
            }
        }
    }

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
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
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
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
        .frame(width: 310, height: 84, alignment: .leading)
        .background(isFocused ? Theme.Palette.surfaceRaised : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.focusRing, lineWidth: isFocused ? 2 : 0)
        }
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(Theme.Motion.focus, value: isFocused)
        .focusable()
        .focused($isFocused)
    }
}
