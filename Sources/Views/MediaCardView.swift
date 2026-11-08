import SwiftUI

public struct MediaCardView: View {
    public let item: MediaItem
    public let onSelect: () -> Void
    
    @FocusState private var isFocused: Bool
    
    public init(item: MediaItem, onSelect: @escaping () -> Void) {
        self.item = item
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: item.posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.3)
                                .overlay(
                                    Image(systemName: "film")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 250, height: 375)
                    .clipped()
                    .cornerRadius(12)
                    
                    if let rating = item.imdbRating, !rating.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.yellow)
                            Text(rating)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .padding(8)
                    }
                }
                
                Text(item.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let year = item.year {
                    Text(year)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 250)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}
