import SwiftUI

public struct MediaDetailView: View {
    public let item: MediaItem
    
    @StateObject private var service = StremioService.shared
    @State private var detail: MediaDetail?
    @State private var isLoading = true
    @State private var selectedSeason = 1
    @State private var streamTarget: StreamTarget?
    
    @FocusState private var focusedButton: String?
    
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
            
            // Background Backdrop
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
            
            // Gradient Overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.85),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.6)
                    Text("Chargement des informations...")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 36) {
                        // Header: Poster + Info
                        HStack(alignment: .top, spacing: 52) {
                            // Poster
                            AsyncImage(url: detail?.posterURL ?? item.posterURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.white.opacity(0.05)
                                }
                            }
                            .frame(width: 320, height: 480)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.7), radius: 25, x: 0, y: 15)
                            
                            // Right Details
                            VStack(alignment: .leading, spacing: 18) {
                                Text(detail?.name ?? item.name)
                                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                
                                // Badges Row
                                HStack(spacing: 12) {
                                    if let rating = detail?.imdbRating ?? item.imdbRating, !rating.isEmpty, rating != "0" {
                                        HStack(spacing: 5) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.yellow)
                                            Text(rating)
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.ultraThinMaterial)
                                        .background(Color.yellow.opacity(0.12))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.yellow.opacity(0.3), lineWidth: 0.5))
                                    }
                                    
                                    if let year = detail?.year ?? item.year, !year.isEmpty {
                                        Text(year)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                    }
                                    
                                    if let runtime = detail?.runtime, !runtime.isEmpty {
                                        Text(runtime)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.75))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                    }
                                    
                                    if let genres = detail?.genres ?? item.genres, !genres.isEmpty {
                                        ForEach(genres.prefix(2), id: \.self) { g in
                                            Text(g)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.7))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.white.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                
                                // Synopsis
                                if let desc = detail?.description ?? item.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineSpacing(6)
                                        .lineLimit(5)
                                        .padding(.top, 4)
                                }
                                
                                // Cast & Directors
                                if let cast = detail?.cast, !cast.isEmpty {
                                    HStack(spacing: 8) {
                                        Text("Avec :")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.gray)
                                        Text(cast.prefix(4).joined(separator: ", "))
                                            .font(.system(size: 15))
                                            .foregroundColor(.white.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                }
                                
                                // Primary Action Button (for movies)
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
                                                .font(.system(size: 20, weight: .bold))
                                            Text("Choisir une source & Regarder")
                                                .font(.system(size: 20, weight: .bold))
                                        }
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 16)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .padding(.top, 12)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 64)
                        .padding(.top, 48)
                        
                        // Series Section: Seasons & Episodes
                        if item.type == "series" && !seasons.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Saisons")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 64)
                                
                                // Seasons horizontal pills
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(seasons, id: \.self) { s in
                                            Button {
                                                selectedSeason = s
                                            } label: {
                                                Text("Saison \(s)")
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundColor(selectedSeason == s ? .black : .white)
                                                    .padding(.horizontal, 22)
                                                    .padding(.vertical, 10)
                                                    .background(selectedSeason == s ? Color.white : Color.white.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 64)
                                }
                                
                                Text("Épisodes")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 64)
                                    .padding(.top, 12)
                                
                                // Episodes List
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredEpisodes) { ep in
                                        EpisodeRowView(episode: ep, seriesName: detail?.name ?? item.name) {
                                            streamTarget = StreamTarget(
                                                id: ep.id,
                                                type: "series",
                                                title: "\(detail?.name ?? item.name) - \(ep.displayTitle)"
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 64)
                            }
                            .padding(.top, 16)
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

private struct EpisodeRowView: View {
    let episode: VideoItem
    let seriesName: String
    let onSelect: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 24) {
                // Episode thumbnail
                ZStack {
                    if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.06)
                            }
                        }
                    } else {
                        Color.white.opacity(0.06)
                    }
                    
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(isFocused ? 0.95 : 0.6))
                }
                .frame(width: 200, height: 112)
                .cornerRadius(10)
                .clipped()
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.displayTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineSpacing(3)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.trailing, 8)
            }
            .padding(14)
            .background(isFocused ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white.opacity(0.8) : Color.white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
    }
}