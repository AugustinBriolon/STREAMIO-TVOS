import SwiftUI

/// Design tokens. See DESIGN.md for the rationale behind each value.
enum Theme {
    enum Palette {
        static let canvas = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
        static let surface = Color.white.opacity(0.08)
        static let surfaceRaised = Color.white.opacity(0.16)
        static let secondaryButton = Color(white: 0.42).opacity(0.55)
        static let accent = Color(red: 229 / 255, green: 9 / 255, blue: 20 / 255)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.72)
        static let textTertiary = Color.white.opacity(0.48)
        static let rating = Color(red: 245 / 255, green: 197 / 255, blue: 24 / 255)
        static let match = Color(red: 70 / 255, green: 211 / 255, blue: 105 / 255)
        static let focusRing = Color.white
        static let track = Color.white.opacity(0.3)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
        static let xxl: CGFloat = 64
        /// Horizontal gutter inside the tvOS safe area.
        static let gutter: CGFloat = 48
        static let cardGap: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 8
        static let button: CGFloat = 8
        static let badge: CGFloat = 4
    }

    enum Typography {
        static let billboardTitle = Font.system(size: 64, weight: .black)
        static let pageTitle = Font.system(size: 48, weight: .bold)
        static let rowTitle = Font.system(size: 30, weight: .bold)
        static let cardTitle = Font.system(size: 22, weight: .semibold)
        static let body = Font.system(size: 24)
        static let meta = Font.system(size: 22, weight: .medium).monospacedDigit()
        static let caption = Font.system(size: 18, weight: .medium)
        static let badge = Font.system(size: 16, weight: .heavy)
        static let button = Font.system(size: 24, weight: .bold)
        static let rank = Font.system(size: 200, weight: .black)
    }

    enum Card {
        static let posterSize = CGSize(width: 220, height: 330)
        static let landscapeSize = CGSize(width: 400, height: 225)
        static let episodeSize = CGSize(width: 360, height: 202)
    }

    enum Motion {
        static let focusScale: CGFloat = 1.08
        static let focus = Animation.easeOut(duration: 0.18)
    }

    enum Layout {
        static let billboardHeight: CGFloat = 760
        static let synopsisWidth: CGFloat = 900
        static let logoSize = CGSize(width: 620, height: 200)
    }
}
