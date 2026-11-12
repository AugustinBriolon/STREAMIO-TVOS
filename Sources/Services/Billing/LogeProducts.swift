import Foundation

/// App Store product identifiers (must match ASC).
public enum LogeProductID: String, CaseIterable, Sendable {
    case proMonthly = "loge.pro.monthly"
    case proYearly = "loge.pro.yearly"
    case ultraMonthly = "loge.ultra.monthly"
    case ultraYearly = "loge.ultra.yearly"
    case ultraLifetime = "loge.ultra.lifetime"

    public var plan: LogePlan {
        switch self {
        case .proMonthly, .proYearly: .pro
        case .ultraMonthly, .ultraYearly, .ultraLifetime: .ultra
        }
    }

    public var isSubscription: Bool {
        self != .ultraLifetime
    }

    public var displayTitle: String {
        switch self {
        case .proMonthly: "Pro — mensuel"
        case .proYearly: "Pro — annuel"
        case .ultraMonthly: "Ultra — mensuel"
        case .ultraYearly: "Ultra — annuel"
        case .ultraLifetime: "Ultra — à vie"
        }
    }

    public static var allIDs: [String] { allCases.map(\.rawValue) }

    public static func plan(forProductID id: String) -> LogePlan? {
        LogeProductID(rawValue: id)?.plan
    }
}
