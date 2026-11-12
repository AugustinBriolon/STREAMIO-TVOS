import Foundation

/// Free explore mode: no personal (non-default) addons → YouTube trailer fallback.
/// Once the user adds stream addons, their sources win and the trailer is never injected.
enum PlaybackSourcePolicy {
    static func hasPersonalAddons(_ addonURLs: [String]) -> Bool {
        addonURLs.contains { !AddonStore.isDefaultAddonURL($0) }
    }

    static func streams(addonURLs: [String], fromAddons: [StreamItem], trailer: StreamItem?) -> [StreamItem] {
        streams(addonURLs: addonURLs, fromAddons: fromAddons, trailers: trailer.map { [$0] } ?? [])
    }

    static func streams(addonURLs: [String], fromAddons: [StreamItem], trailers: [StreamItem]) -> [StreamItem] {
        if hasPersonalAddons(addonURLs) {
            return fromAddons
        }
        return fromAddons + trailers
    }
}
