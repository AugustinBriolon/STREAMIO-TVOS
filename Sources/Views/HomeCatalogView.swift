import SwiftUI

public struct CatalogShelf: Identifiable {
    public let id = UUID()
    public let title: String
    public let genre: String?
    public var items: [MediaItem]
}

public struct HomeCatalogView: View {
    public let type: String
    public let title: String
    
    @StateObject private var service = StremioService.shared
    @State private var shelves: [CatalogShelf] = []
    @State private var isLoading = true
    @State private var spotlightItem: MediaItem?
    @State private var selectedItem: MediaItem?
    
    public init(type: String, title: String) {
        self.type = type
        self.title = title
    }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                
                // Dynamic Hero Backdrop
                if let bg = spotlightItem?.backgroundURL ?? spotlightItem?.posterURL {
                    AsyncImage(url: bg) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 600)
                                .clipped()
                                .opacity(0.35)
                                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                        }
                    }
                    .frame(height: 600)
                    .ignoresSafeArea()
                    
                    // Cinematic gradient masks
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.1),
                            Color.black.opacity(0.6),
                            Color.black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 620)
                    .ignoresSafeArea()
                    
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.8),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(maxWidth: 800, maxHeight: 620)
                    .ignoresSafeArea()
                }
                
                if isLoading {
                    VStack(spacing: 20) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.6)
                        Text("Chargement du catalogue...")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shelves.isEmpty || shelves.allSatisfy({ $0.items.isEmpty }) {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "film.stack")
                            .font(.system(size: 64))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("Catalogue indisponible")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("Vérifiez votre connexion réseau.")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 36) {
                            // Spotlight Hero Section
                            if let spot = spotlightItem {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(spot.name)
                                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.8), radius: 10, y: 4)
                                        .lineLimit(2)
                                        .padding(.top, 40)
                                    
                                    HStack(spacing: 12) {
                                        if let rating = spot.imdbRating, !rating.isEmpty, rating != "0" {
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.yellow)
                                                    .font(.system(size: 12))
                                                Text(rating)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .monospacedDigit()
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                        }
                                        
                                        if let year = spot.year, !year.isEmpty {
                                            Text(year)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        
                                        if let genres = spot.genres, !genres.isEmpty {
                                            Text("•")
                                                .foregroundColor(.gray)
                                            Text(genres.prefix(3).joined(separator: ", "))
                                                .font(.system(size: 16))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    
                                    if let desc = spot.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.system(size: 18, weight: .regular))
                                            .foregroundColor(.white.opacity(0.85))
                                            .lineSpacing(4)
                                            .lineLimit(3)
                                            .frame(maxWidth: 900, alignment: .leading)
                                            .shadow(color: .black.opacity(0.8), radius: 8, y: 2)
                                    }
                                    
                                    HStack(spacing: 20) {
                                        Button {
                                            selectedItem = spot
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text("Voir les détails")
                                                    .font(.system(size: 18, weight: .bold))
                                            }
                                            .padding(.horizontal, 28)
                                            .padding(.vertical, 14)
                                            .background(Color.white)
                                            .foregroundColor(.black)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 8)
                                }
                                .padding(.horizontal, 54)
                                .frame(height: 380, alignment: .bottomLeading)
                            }
                            
                            // Shelves Rows
                            ForEach(shelves) { shelf in
                                if !shelf.items.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text(shelf.title)
                                            .font(.system(size: 26, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 54)
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 28) {
                                                ForEach(shelf.items) { item in
                                                    MediaCardView(item: item) {
                                                        selectedItem = item
                                                    } onFocusChange: { focused in
                                                        if focused {
                                                            withAnimation(.easeOut(duration: 0.25)) {
                                                                spotlightItem = item
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 54)
                                            .padding(.vertical, 14)
                                        }
                                    }
                                }
                            }
                            
                            Spacer().frame(height: 60)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
        .task {
            await loadCatalogs()
        }
    }
    
    private func loadCatalogs() async {
        isLoading = true
        var loadedShelves: [CatalogShelf] = []
        
        let popular = await service.fetchCatalog(type: type)
        loadedShelves.append(CatalogShelf(title: "Tendances populaires", genre: nil, items: popular))
        
        if spotlightItem == nil, let first = popular.first {
            spotlightItem = first
        }
        
        let genreNames: [String]
        if type == "movie" {
            genreNames = ["Action", "Science Fiction", "Comedy", "Animation", "Horror"]
        } else {
            genreNames = ["Drama", "Comedy", "Animation", "Crime", "Action"]
        }
        
        for g in genreNames {
            let items = await service.fetchCatalog(type: type, genre: g)
            if !items.isEmpty {
                let displayTitle: String
                switch g {
                case "Science Fiction": displayTitle = "Science-Fiction"
                case "Comedy": displayTitle = "Comédies"
                case "Animation": displayTitle = "Animation"
                case "Horror": displayTitle = "Frissons & Horreur"
                case "Drama": displayTitle = "Drames captivants"
                case "Crime": displayTitle = "Policiers & Mystères"
                default: displayTitle = g
                }
                loadedShelves.append(CatalogShelf(title: displayTitle, genre: g, items: items))
            }
        }
        
        self.shelves = loadedShelves
        self.isLoading = false
    }
}