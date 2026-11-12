import Observation
import SwiftUI

enum SourceFilter: String, CaseIterable, Identifiable {
    case playableOnly
    case all

    var id: String { rawValue }
}

@MainActor
@Observable
final class StreamsViewModel {
    private(set) var streams: [StreamItem] = []
    private(set) var state: LoadState = .idle
    var filter: SourceFilter = .playableOnly

    @ObservationIgnored private let service: StremioProviding

    init(service: StremioProviding = StremioService(), initialStreams: [StreamItem]? = nil) {
        self.service = service
        if let initialStreams {
            self.streams = initialStreams
            self.state = .loaded
        }
    }

    var playableCount: Int { streams.filter(\.isPlayable).count }

    var displayedStreams: [StreamItem] {
        switch filter {
        case .playableOnly: streams.filter(\.isPlayable)
        case .all: streams
        }
    }

    var noticeSummary: String? {
        var seen = Set<String>()
        let notices = streams.filter(\.isNotice)
            .map(\.fullDescription)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return notices.isEmpty ? nil : notices.joined(separator: "\n")
    }

    func load(type: MediaType, videoID: String, addons: [String], forceRefresh: Bool = false) async {
        if !forceRefresh && state == .loaded { return }
        state = .loading
        let fetched = await service.fetchStreams(type: type, id: videoID, addonBaseURLs: addons)
        streams = StreamRanker.rank(fetched, device: .current)
        state = .loaded
    }
}

/// Manual source picker, ranked best first; filters to playable sources by default with an option to inspect all entries.
struct StreamsView: View {
    let type: MediaType
    let videoID: String
    let title: String
    let onSelect: (StreamItem) -> Void

    @State private var model: StreamsViewModel
    @Environment(AddonStore.self) private var addons
    @Environment(\.dismiss) private var dismiss

    init(
        type: MediaType,
        videoID: String,
        title: String,
        initialStreams: [StreamItem]? = nil,
        onSelect: @escaping (StreamItem) -> Void
    ) {
        self.type = type
        self.videoID = videoID
        self.title = title
        self.onSelect = onSelect
        _model = State(initialValue: StreamsViewModel(initialStreams: initialStreams))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Sources disponibles").font(Theme.Typography.pageTitle).tracking(Theme.Typography.displayTracking)
                    Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer(minLength: 0)

                if model.state == .loaded && !model.streams.isEmpty {
                    filterBar
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)

            switch model.state {
            case .idle, .loading:
                StateView(kind: .loading("Interrogation de vos addons…"))
            case .loaded where model.streams.isEmpty:
                StateView(kind: .empty(
                    symbol: "antenna.radiowaves.left.and.right.slash",
                    title: "Aucune source trouvée",
                    message: addons.activeURLs.isEmpty
                        ? "Aucune bande-annonce trouvée. Ajoutez un addon dans Réglages pour d'autres sources."
                        : "Vos addons n'ont renvoyé aucun flux pour ce contenu."
                ))
            case .loaded where model.displayedStreams.isEmpty:
                VStack(spacing: Theme.Spacing.l) {
                    StateView(kind: .empty(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "Aucune source lisible",
                        message: filteredEmptyMessage
                    ))
                    Button("Afficher toutes les entrées (\(model.streams.count))", systemImage: "eye") {
                        model.filter = .all
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(model.displayedStreams) { stream in
                            Button {
                                onSelect(stream)
                                dismiss()
                            } label: {
                                StreamRow(stream: stream)
                            }
                            .buttonStyle(CardFocusStyle(showsRing: true, focusScale: Theme.Motion.rowFocusScale, maxTiltDegrees: 0))
                            .disabled(!stream.isPlayable)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.vertical, Theme.Spacing.m)
                }
            }
        }
        .padding(.top, Theme.Spacing.xl)
        .background(Theme.Palette.canvas)
        .task { await model.load(type: type, videoID: videoID, addons: addons.activeURLs) }
    }

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            filterButton(.playableOnly, label: "Lisibles (\(model.playableCount))")
            filterButton(.all, label: "Toutes (\(model.streams.count))")
            Button {
                Task { await model.load(type: type, videoID: videoID, addons: addons.activeURLs, forceRefresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("Actualiser les sources")
        }
    }

    private func filterButton(_ target: SourceFilter, label: String) -> some View {
        Button(label) {
            model.filter = target
        }
        .buttonStyle(PillButtonStyle(kind: model.filter == target ? .primary : .secondary))
    }

    private var filteredEmptyMessage: String {
        if let notice = model.noticeSummary {
            return "\(notice)\n\nAjustez les filtres de vos add-ons (langue, qualité, cache Debrid) pour débloquer la lecture."
        }
        return "\(model.streams.count) source(s) trouvée(s), mais aucune n'est lisible directement sur Apple TV (torrents non-Debrid ou format incompatible)."
    }
}

private struct StreamRow: View {
    let stream: StreamItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Tag(
                text: stream.isNotice ? "INFO" : stream.quality.label,
                color: stream.isNotice
                    ? Theme.Palette.surfaceRaised
                    : (stream.quality == .uhd ? Theme.Palette.accent : Theme.Palette.surfaceRaised)
            )
            .frame(width: 90)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(stream.isNotice ? stream.fullDescription : stream.parsedTitle)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(stream.isNotice ? 4 : 1)

                if stream.isNotice {
                    Text(stream.providerName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    HStack(spacing: Theme.Spacing.s) {
                        if stream.isDebrid { Tag(text: "DEBRID", color: Theme.Palette.match.opacity(0.35)) }
                        if let hdr = stream.hdrBadge { Tag(text: hdr) }
                        if let audio = stream.audioBadge { Tag(text: audio) }
                        Text([stream.providerName, stream.sizeInfo, stream.seedersInfo.map { "\($0) seeders" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        if stream.isHEVC { Tag(text: "HEVC") }
                    }
                }

                if let reason = stream.unplayableReason {
                    Text(reason)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(stream.isNotice ? Theme.Palette.textTertiary : Theme.Palette.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .opacity(stream.isPlayable ? 1 : 0.55)
    }
}
