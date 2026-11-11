import Foundation

/// Storage shared by the app and the Top Shelf extension (ADR 0015). Compiled into both targets.
public enum AppGroup {
    public static let id = "group.com.h6245.vortxtv"

    /// Falls back to the standard defaults when the group is unavailable (unit tests, unsigned builds).
    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// UserDefaults keys. Library data is namespaced by profile so each profile has its own list and progress.
public enum StorageKey {
    public static let profiles = "profiles.v1"
    public static let activeProfile = "profiles.active.v1"
    /// Profiles deleted on this device, with the deletion date, until the account has been told (ADR 0023).
    public static let deletedProfiles = "profiles.deleted.v1"
    /// True while the only profile is the one created at first launch and nobody has used it yet.
    public static let untouchedDefaultProfile = "profiles.untouchedDefault.v1"

    public static func myList(_ profileID: UUID) -> String { "library.\(profileID.uuidString).myList.v1" }
    public static func progress(_ profileID: UUID) -> String { "library.\(profileID.uuidString).progress.v1" }
    public static func myListTimestamps(_ profileID: UUID) -> String { "library.\(profileID.uuidString).myListTimestamps.v1" }
    public static func deletedMyList(_ profileID: UUID) -> String { "library.\(profileID.uuidString).deletedMyList.v1" }
    public static func deletedProgress(_ profileID: UUID) -> String { "library.\(profileID.uuidString).deletedProgress.v1" }

    /// Keys used before profiles existed (ADR 0004), stored in the standard defaults.
    public static let legacyMyList = "library.myList.v1"
    public static let legacyProgress = "library.progress.v1"
}
