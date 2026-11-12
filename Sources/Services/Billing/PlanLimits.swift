import Foundation

/// Loge household plan. Source of truth lives on the Worker account row; the app caches the last known value.
public enum LogePlan: String, Codable, Sendable, CaseIterable {
    case free
    case pro
    case ultra
}

/// Hard caps for a plan (spec 2026-11-12-loge-tiers-design).
public struct PlanLimits: Equatable, Sendable {
    public let maxProfiles: Int
    public let maxAddons: Int
    public let maxTVSessions: Int
    public let maxBrowserSessions: Int
    public let cloudSync: Bool
    public let canRenameDevices: Bool

    public static func forPlan(_ plan: LogePlan) -> PlanLimits {
        switch plan {
        case .free:
            PlanLimits(
                maxProfiles: 1,
                maxAddons: 1,
                maxTVSessions: 1,
                maxBrowserSessions: 1,
                cloudSync: false,
                canRenameDevices: false
            )
        case .pro:
            PlanLimits(
                maxProfiles: 3,
                maxAddons: 5,
                maxTVSessions: 2,
                maxBrowserSessions: 1,
                cloudSync: true,
                canRenameDevices: true
            )
        case .ultra:
            PlanLimits(
                maxProfiles: 6,
                maxAddons: 20,
                maxTVSessions: 4,
                maxBrowserSessions: 2,
                cloudSync: true,
                canRenameDevices: true
            )
        }
    }

    public func canAddProfile(currentCount: Int) -> Bool { currentCount < maxProfiles }
    public func canAddAddon(currentCount: Int) -> Bool { currentCount < maxAddons }
    public func canOpenTVSession(activeCount: Int) -> Bool { activeCount < maxTVSessions }
    public func canOpenBrowserSession(activeCount: Int) -> Bool { activeCount < maxBrowserSessions }

    /// How many oldest sessions of a kind to revoke so that opening one more stays within the cap.
    public func sessionsToRevokeBeforeOpen(activeCount: Int, kind: SessionKind) -> Int {
        let cap = kind == .tv ? maxTVSessions : maxBrowserSessions
        let overflow = activeCount + 1 - cap
        return Swift.max(0, overflow)
    }
}

public enum SessionKind: String, Codable, Sendable {
    case tv
    case browser
}
