import SwiftUI

/// Page de catalogue dédiée pour un Studio ou une Plateforme de streaming.
struct HubCatalogView: View {
    let hub: BrandHub
    @State private var items: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var page = 0
    @State private var totalPages = 1
    @State private var isLoadingMore = false
    private let service: StremioProviding

    private let columns = [
        GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)
    ]

    init(hub: BrandHub, service: StremioProviding = StremioService()) {
        self.hub = hub
        self.service = service
    }

    private var accentColor: Color {
        Color(hex: hub.accentColorHex)
    }

    private var hasMore: Bool { page < totalPages }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headerSection
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.top, Theme.Spacing.xl)

                switch state {
                case .idle, .loading:
                    StateView(kind: .loading("Chargement de la sélection \(hub.name)…"))
                        .frame(height: 400)
                case .failed(let message):
                    StateView(kind: .error(message) { Task { await loadInitial() } })
                        .frame(height: 400)
                case .loaded:
                    if items.isEmpty {
                        StateView(kind: .empty(
                            symbol: "film",
                            title: "Aucun titre",
                            message: "Aucun contenu disponible pour le moment."
                        ))
                        .frame(height: 400)
                    } else {
                        gridSection
                            .padding(.horizontal, Theme.Spacing.gutter)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [accentColor.opacity(0.18), accentColor.opacity(0.04), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 900
                )
                .ignoresSafeArea()
            }
        )
        .task { await loadInitial() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.85))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.35), lineWidth: 2)
                    }

                if let logoURL = hub.logoURL {
                    if hub.category == .platform {
                        RemoteImage(url: logoURL, maxPixel: 300, showsPlaceholder: false, contentMode: .fit)
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    } else {
                        RemoteImage(url: logoURL, maxPixel: 400, showsPlaceholder: false, contentMode: .fit)
                            .padding(Theme.Spacing.s)
                            .frame(maxWidth: 112, maxHeight: 88)
                            .padding(Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.92))
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    }
                } else {
                    Image(systemName: hub.systemSymbol)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(accentColor)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(hub.name)
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(hub.subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.cardGap) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: item) {
                    PosterCard(item: item)
                }
                .buttonStyle(CardFocusStyle())
                .onAppear {
                    if index >= items.count - 6 {
                        Task { await loadMore() }
                    }
                }
            }
        }
    }

    private func loadInitial() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading
        page = 0
        totalPages = 1
        items = []
        await appendPage(1)
        state = .loaded
    }

    private func loadMore() async {
        guard state == .loaded, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        await appendPage(page + 1)
        isLoadingMore = false
    }

    private func appendPage(_ next: Int) async {
        let lang = AppPreferences.shared.metadataLanguage
        let result: DiscoverPage
        switch hub.querySource {
        case .company(let companyID):
            result = await service.fetchByCompany(companyID: companyID, language: lang, page: next)
        case .network(let networkID):
            result = await service.fetchByNetwork(networkID: networkID, language: lang, page: next)
        case .watchProvider(let providerID, let region):
            result = await service.fetchByWatchProvider(
                type: hub.type,
                providerID: providerID,
                language: lang,
                region: region,
                page: next
            )
        }
        page = result.page
        totalPages = result.totalPages
        var seen = Set(items.map(\.id))
        for item in result.items where seen.insert(item.id).inserted {
            items.append(item)
        }
    }
}
