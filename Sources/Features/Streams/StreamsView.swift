import Observation
import SwiftUI

@MainActor
@Observable
final class StreamsViewModel {
    private(set) var streams: [StreamItem] = []
    private(set) var state: LoadState = .idle

    @ObservationIgnored private let service: StremioProviding

    init(service: StremioProviding = StremioService()) {
        self.service = service
    }

    func load(type: MediaType, videoID: String, addons: [String]) async {
        state = .loading
        let fetched = await service.fetchStreams(type: type, id: videoID, addonBaseURLs: addons)
        streams = StreamRanker.rank(fetched, maxQuality: PlaybackCoordinator.displayMaxQuality)
        state = .loaded
    }
}

/// Manual source picker, ranked best first; unplayable sources are listed but disabled with a reason.
struct StreamsView: View {
    let type: MediaType
    let videoID: String
    let title: String
    let onSelect: (StreamItem) -> Void

    @State private var model = StreamsViewModel()
    @Environment(AddonStore.self) private var addons
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Sources disponibles").font(Theme.Typography.pageTitle)
                Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.gutter)

            switch model.state {
            case .idle, .loading:
                StateView(kind: .loading("Interrogation de vos addons…"))
            case .loaded where model.streams.isEmpty:
                StateView(kind: .empty(
                    symbol: "antenna.radiowaves.left.and.right.slash",
                    title: "Aucune source trouvée",
                    message: addons.urls.isEmpty
                        ? "Aucun addon n'est configuré. Ajoutez-en un dans Réglages."
                        : "Vos addons n'ont renvoyé aucun flux pour ce contenu."
                ))
            default:
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(model.streams) { stream in
                            Button {
                                onSelect(stream)
                                dismiss()
                            } label: {
                                StreamRow(stream: stream)
                            }
                            .buttonStyle(CardFocusStyle())
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
        .task { await model.load(type: type, videoID: videoID, addons: addons.urls) }
    }
}

private struct StreamRow: View {
    let stream: StreamItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Tag(text: stream.quality.label, color: stream.quality == .uhd ? Theme.Palette.accent : Theme.Palette.surfaceRaised)
                .frame(width: 90)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(stream.parsedTitle).font(Theme.Typography.cardTitle).lineLimit(1)
                HStack(spacing: Theme.Spacing.s) {
                    if stream.isDebrid { Tag(text: "⚡ DEBRID", color: Theme.Palette.match.opacity(0.35)) }
                    if let hdr = stream.hdrBadge { Tag(text: hdr) }
                    if let audio = stream.audioBadge { Tag(text: audio) }
                    Text([stream.providerName, stream.sizeInfo, stream.seedersInfo.map { "👤 \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    if stream.isMatroska { Tag(text: "MKV") }
                }
                if let reason = stream.unplayableReason {
                    Text(reason).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .opacity(stream.isPlayable ? 1 : 0.45)
    }
}
