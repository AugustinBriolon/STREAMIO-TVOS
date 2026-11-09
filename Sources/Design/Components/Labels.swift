import SwiftUI

/// "★ 7.8 · 2024 · 2 h 10 min · Action, Drame"
struct MetaLine: View {
    let rating: String?
    let components: [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let rating {
                Label(rating, systemImage: "star.fill")
                    .labelStyle(RatingLabelStyle())
            }
            ForEach(Array(components.enumerated()), id: \.offset) { index, text in
                if index > 0 || rating != nil {
                    Text("·").foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(text)
            }
        }
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.Palette.textSecondary)
        .lineLimit(1)
    }
}

private struct RatingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            configuration.icon.foregroundStyle(Theme.Palette.rating).font(.system(size: 16, weight: .bold))
            configuration.title.foregroundStyle(Theme.Palette.textPrimary).bold()
        }
    }
}

/// Red watch-progress track.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                Capsule().fill(Theme.Palette.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Progression \(Int(fraction * 100)) %")
    }
}

/// Small rectangular tag (quality, HDR, audio).
struct Tag: View {
    let text: String
    var color: Color = Theme.Palette.surfaceRaised

    var body: some View {
        Text(text)
            .font(Theme.Typography.badge)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            .foregroundStyle(Theme.Palette.textPrimary)
    }
}
