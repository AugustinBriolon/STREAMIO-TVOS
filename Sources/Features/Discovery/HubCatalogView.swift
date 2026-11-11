import SwiftUI

/// Page de catalogue dédiée pour un Studio ou une Plateforme de streaming.
struct HubCatalogView: View {
    let hub: BrandHub
    @State private var items: [MediaItem] = []
    @State private var state: LoadState = .idle
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
                    StateView(kind: .error(message) { Task { await load() } })
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
        .task { await load() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            // Logo officiel de la marque avec cadre en verre
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.85))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.35), lineWidth: 2)
                    }

                if let logoURL = hub.logoURL {
                    if hub.category == .platform {
                        RemoteImage(url: logoURL, maxPixel: 300)
                            .scaledToFit()
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    } else {
                        RemoteImage(url: logoURL, maxPixel: 400)
                            .scaledToFit()
                            .frame(maxWidth: 120, maxHeight: 100)
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
                HStack(spacing: Theme.Spacing.s) {
                    Text(hub.name)
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text(hub.type == .movie ? "FILMS" : "SÉRIES")
                        .font(Theme.Typography.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(accentColor.opacity(0.18))
                                .overlay {
                                    Capsule().strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                                }
                        }
                }

                Text(hub.subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)

                if case .loaded = state {
                    Text("\(items.count) titres disponibles")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.cardGap) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCard(item: item)
                }
                .buttonStyle(CardFocusStyle())
            }
        }
    }

    private func load() async {
        guard state == .idle else { return }
        state = .loading
        let lang = AppPreferences.shared.metadataLanguage

        switch hub.querySource {
        case .company(let companyID):
            items = await service.fetchByCompany(companyID: companyID, language: lang)
        case .network(let networkID):
            items = await service.fetchByNetwork(networkID: networkID, language: lang)
        case .watchProvider(let providerID, let region):
            items = await service.fetchByWatchProvider(type: hub.type, providerID: providerID, language: lang, region: region)
        }

        state = .loaded
    }
}
