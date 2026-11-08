import SwiftUI

public struct MediaCardView: View {
    public let item: MediaItem
    public let width: CGFloat
    public let height: CGFloat
    public let onSelect: () -> Void
    public var onFocusChange: ((Bool) -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    public init(
        item: MediaItem,
        width: CGFloat = 230,
        height: CGFloat = 345,
        onSelect: @escaping () -> Void,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.item = item
        self.width = width
        self.height = height
        self.onSelect = onSelect
        self.onFocusChange = onFocusChange
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    // Poster Image
                    AsyncImage(url: item.posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            ZStack {
                                Color.white.opacity(0.06)
                                Image(systemName: "film")
                                    .font(.system(size: 38))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        default:
                            ZStack {
                                Color.white.opacity(0.04)
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.08),
                                lineWidth: isFocused ? 3 : 1
                            )
                    )
                    
                    // IMDb Rating Pill
                    if let rating = item.imdbRating, !rating.isEmpty, rating != "0" {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.yellow)
                            Text(rating)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .padding(10)
                    }
                }
                .shadow(color: isFocused ? Color.black.opacity(0.7) : Color.black.opacity(0.2),
                        radius: isFocused ? 20 : 6,
                        x: 0,
                        y: isFocused ? 12 : 3)
                
                // Title and Metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(isFocused ? .white : .white.opacity(0.9))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        if let year = item.year, !year.isEmpty {
                            Text(year)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        if let genre = item.genres?.first {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(.gray.opacity(0.6))
                            Text(genre)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isFocused)
        .onChange(of: isFocused) { focused in
            onFocusChange?(focused)
        }
    }
}