import Foundation

public enum AvatarColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, teal, blue, purple, pink
}

/// Raw values are SF Symbol names.
public enum AvatarSymbol: String, CaseIterable, Codable, Sendable {
    case face = "face.smiling"
    case star = "star.fill"
    case gamepad = "gamecontroller.fill"
    case popcorn = "popcorn.fill"
    case moon = "moon.stars.fill"
    case bolt = "bolt.fill"
    case heart = "heart.fill"
    case paw = "pawprint.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"
}

public struct ProfileAvatar: Codable, Hashable, Sendable {
    public var color: AvatarColor
    public var symbol: AvatarSymbol

    public init(color: AvatarColor, symbol: AvatarSymbol) {
        self.color = color
        self.symbol = symbol
    }

    /// The first color and symbol not used by `profiles`, so new profiles look different from existing ones.
    public static func suggested(avoiding profiles: [Profile]) -> ProfileAvatar {
        let usedColors = Set(profiles.map(\.avatar.color))
        let usedSymbols = Set(profiles.map(\.avatar.symbol))
        return ProfileAvatar(
            color: AvatarColor.allCases.first { !usedColors.contains($0) } ?? AvatarColor.allCases[profiles.count % AvatarColor.allCases.count],
            symbol: AvatarSymbol.allCases.first { !usedSymbols.contains($0) } ?? AvatarSymbol.allCases[profiles.count % AvatarSymbol.allCases.count]
        )
    }
}

public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var avatar: ProfileAvatar

    public init(id: UUID, name: String, avatar: ProfileAvatar) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }
}
