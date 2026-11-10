import Foundation

/// Storage shared by the app and the Top Shelf extension (ADR 0015). Compiled into both targets.
enum AppGroup {
    static let id = "group.com.h6245.vortxtv"

    /// Falls back to the standard defaults when the group is unavailable (unit tests, unsigned builds).
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// UserDefaults keys. Library data is namespaced by profile so each profile has its own list and progress.
enum StorageKey {
    static let profiles = "profiles.v1"
    static let activeProfile = "profiles.active.v1"

    static func myList(_ profileID: UUID) -> String { "library.\(profileID.uuidString).myList.v1" }
    static func progress(_ profileID: UUID) -> String { "library.\(profileID.uuidString).progress.v1" }

    /// Keys used before profiles existed (ADR 0004), stored in the standard defaults.
    static let legacyMyList = "library.myList.v1"
    static let legacyProgress = "library.progress.v1"
}
