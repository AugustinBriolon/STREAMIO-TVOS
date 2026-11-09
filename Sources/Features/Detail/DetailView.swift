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

    private var resume: PlaybackProgress? { library.resumeEntry(forTitle: model.item.id) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                switch model.state {
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await model.loadIfNeeded(resumeSeason: resume?.video?.season) } })
                        .frame(height: 400)
                case .loaded:
                    if model.item.type == .series { episodesSection }
                    if !model.similar.isEmpty {
                        ShelfRow("Titres similaires", items: model.similar) { item in
                            NavigationLink(value: item) { PosterCard(item: item) }
                                .buttonStyle(CardFocusStyle())
                        }
                    }
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.Palette.canvas)
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

            MyListButton(isInMyList: library.isInMyList(model.item.id)) {
                library.toggleMyList(model.summary)
            }

            if model.item.type == .movie {
                Button("Choisir une source", systemImage: "list.bullet") {
                    sourcePicker = SourcePickerTarget(video: nil, videoID: model.item.id, title: model.summary.name)
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.top, Theme.Spacing.s)
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
