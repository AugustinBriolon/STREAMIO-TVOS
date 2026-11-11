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

    /// Apple TV elevation and depth tokens.
    enum Shadow {
        /// Broad ambient diffusion representing the card/button lifting off the canvas plane toward the viewer.
        static let ambientColor = Color.black.opacity(0.45)
        static let ambientRadius: CGFloat = 26
        static let ambientY: CGFloat = 12

        /// Directional contact shadow anchoring the control against directional overhead living-room lighting.
        static let contactColor = Color.black.opacity(0.32)
        static let contactRadius: CGFloat = 8
        static let contactY: CGFloat = 4

        /// Compressed shadow geometry during remote click actuation.
        static let pressedAmbientRadius: CGFloat = 14
        static let pressedAmbientY: CGFloat = 6
        static let pressedContactRadius: CGFloat = 4
        static let pressedContactY: CGFloat = 2
    }

    /// Gradients for contrast and specular illumination.
    enum Gradients {
        /// Non-linear progressive scrim gradient that prevents OLED dark-room color banding.
        static let cardScrim = LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.18), location: 0.45),
                .init(color: .black.opacity(0.55), location: 0.72),
                .init(color: .black.opacity(0.88), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Specular top-edge sheen reflecting virtual living-room lighting across focused surfaces.
        static let specularSheen = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.20), location: 0.0),
                .init(color: Color.white.opacity(0.04), location: 0.25),
                .init(color: Color.clear, location: 0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
        static let brandHubSize = CGSize(width: 260, height: 116)
        static let sagaSize = CGSize(width: 380, height: 214)
        static let awardSize = CGSize(width: 320, height: 154)
    }

    /// Pixels per point of the current output (2 on a 4K Apple TV, 1 on 1080p).
    @MainActor static var pixelScale: CGFloat { UIScreen.main.scale }

    /// Apple TV fluid spring motion: critically damped for focus shifts (zero overshoot, velocity-preserving
    /// across rapid remote swipes) and high-stiffness tactile spring for remote clickpad actuation.
    enum Motion {
        static let focusScale: CGFloat = 1.08
        /// Critically-damped interactive spring: immediate response, zero bounce, smooth momentum handoff.
        static let focus = Animation.spring(duration: 0.22, bounce: 0)
        /// Tactile clickpad depression spring matching physical remote button actuation.
        static let press = Animation.snappy(duration: 0.14, extraBounce: 0)
        /// Content transitions and dynamic backdrop cross-fades.
        static let fade = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
        /// Navigation rail and slide-over panels.
        static let panel = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
        /// Transport HUD overlay entrance: smooth Apple tvOS critically-damped spring (settles cleanly into safe area).
        static let overlayEntrance = Animation.spring(duration: 0.28, bounce: 0)
        /// Transport HUD overlay exit: rapid dismissal (clears the picture out of the viewer's way).
        static let overlayExit = Animation.spring(duration: 0.20, bounce: 0)
        static let pressScale: CGFloat = 0.96

        /// Scale of a focusable control. On tvOS only the focused element can be clicked, so the press
        /// dip is applied on top of the focus scale (a first version only dipped unfocused controls,
        /// which never happens: nothing reacted to a click).
        static func scale(focused: Bool, pressed: Bool, focusScale: CGFloat = Motion.focusScale, reduceMotion: Bool) -> CGFloat {
            if reduceMotion { return 1 }
            return (focused ? focusScale : 1) * (pressed ? pressScale : 1)
        }
    }

    enum Layout {
        static let billboardHeight: CGFloat = 760
        static let synopsisWidth: CGFloat = 900
        static let logoSize = CGSize(width: 620, height: 200)
    }
}
