import SwiftUI

/// Bannière cinématique 16:9 pour les sagas et franchises légendaires.
struct SagaCard: View {
    let saga: SagaCollection
    var size = Theme.Card.sagaSize

    var body: some View {
        RemoteImage(url: saga.backdropURL ?? saga.posterURL, maxPixel: size.width * Theme.pixelScale)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("\(saga.partsCount) films")
                            .font(Theme.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(0.22))
                                    .overlay {
                                        Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                    }
                            }
                    }

                    Text(saga.name)
                        .font(Theme.Typography.cardTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Gradients.cardScrim)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(saga.name), saga de \(saga.partsCount) films")
    }
}
