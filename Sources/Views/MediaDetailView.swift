import SwiftUI

public struct MediaDetailView: View {
    public let item: MediaItem
    
    @StateObject private var service = StremioService.shared
    @State private var detail: MediaDetail?
    @State private var isLoading = true
    @State private var selectedSeason = 1
    @State private var streamTarget: StreamTarget?
    
    public init(item: MediaItem) {
        self.item = item
    }
    
    public struct StreamTarget: Identifiable {
        public let id: String
        public let type: String
        public let title: String
    }
    
    private var seasons: [Int] {
        guard let videos = detail?.videos else { return [] }
        let allSeasons = Set(videos.map { $0.season })
        return allSeasons.sorted()
    }
    
    private var filteredEpisodes: [VideoItem] {
        guard let videos = detail?.videos else { return [] }
        return videos.filter { $0.season == selectedSeason }.sorted { $0.episodeNumber < $1.episodeNumber }
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let bg = detail?.backgroundURL ?? item.backgroundURL {
                AsyncImage(url: bg) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .opacity(0.3)
                    }
                }
                .ignoresSafeArea()
            }
            
            LinearGradient(
                colors: [.black.opacity(0.85), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        HStack(alignment: .top, spacing: 48) {
                            AsyncImage(url: detail?.posterURL ?? item.posterURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 320, height: 480)
                            .cornerRadius(16)
                            .shadow(radius: 20)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text(detail?.name ?? item.name)
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 16) {
                                    if let year = detail?.year ?? item.year {
                                        Text(year)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    if let runtime = detail?.runtime {
                                        Text("• \(runtime)")
                                            .font(.system(size: 20))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    if let rating = detail?.imdbRating ?? item.imdbRating {
                                        HStack(spacing: 6) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.yellow)
                                            Text(rating)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(8)
                                    }
                                }
                                
                                if let genres = detail?.genres ?? item.genres, !genres.isEmpty {
                                    Text(genres.joined(separator: " • "))
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                
                                if let desc = detail?.description ?? item.description {
                                    Text(desc)
                                        .font(.system(size: 20))
                                        .foregroundColor(.white.opacity(0.9))
                                        .lineSpacing(6)
                                        .padding(.top, 8)
                                }
                                
                                if item.type == "movie" {
                                    Button {
                                        streamTarget = StreamTarget(
                                            id: item.id,
                                            type: "movie",
                                            title: detail?.name ?? item.name
                                        )
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "play.fill")
                                            Text("Regarder le film")
                                                .font(.system(size: 22, weight: .bold))
                                        }
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 16)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .padding(.top, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 64)
                        .padding(.top, 48)
                        
                        if item.type == "series" && !seasons.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Saisons & Épisodes")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 64)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(seasons, id: \.self) { s in
                                            Button {
                                                selectedSeason = s
                                            } label: {
                                                Text("Saison \(s)")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(selectedSeason == s ? .black : .white)
                                                    .padding(.horizontal, 24)
                                                    .padding(.vertical, 12)
                                                    .background(selectedSeason == s ? Color.white : Color.white.opacity(0.1))
                                                    .cornerRadius(10)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 64)
                                }
                                
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredEpisodes) { ep in
                                        Button {
                                            streamTarget = StreamTarget(
                                                id: ep.id,
                                                type: "series",
                                                title: "\(detail?.name ?? item.name) - \(ep.displayTitle)"
                                            )
                                        } label: {
                                            HStack(spacing: 24) {
                                                if let thumb = ep.thumbnail, let thumbURL = URL(string: thumb) {
                                                    AsyncImage(url: thumbURL) { phase in
                                                        if let image = phase.image {
                                                            image.resizable().scaledToFill()
                                                        } else {
                                                            Color.gray.opacity(0.3)
                                                        }
                                                    }
                                                    .frame(width: 220, height: 124)
                                                    .cornerRadius(8)
                                                    .clipped()
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(ep.displayTitle)
                                                        .font(.system(size: 20, weight: .bold))
                                                        .foregroundColor(.white)
                                                    
                                                    if let overview = ep.overview, !overview.isEmpty {
                                                        Text(overview)
                                                            .font(.system(size: 15))
                                                            .foregroundColor(.gray)
                                                            .lineLimit(3)
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.white)
                                            }
                                            .padding(16)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.horizontal, 64)
                            }
                            .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 64)
                }
            }
        }
        .task {
            detail = await service.fetchDetails(type: item.type, id: item.id)
            if let firstSeason = seasons.first {
                selectedSeason = firstSeason
            }
            isLoading = false
        }
        .sheet(item: $streamTarget) { target in
            StreamsSheetView(type: target.type, id: target.id, mediaTitle: target.title)
        }
    }
}
