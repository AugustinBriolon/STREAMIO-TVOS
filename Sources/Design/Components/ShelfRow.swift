import SwiftUI

/// Titled horizontal row of focusable cards with leading overflow clipping and a smooth left fade.
struct ShelfRow<Data: RandomAccessCollection, ID: Hashable, Card: View>: View {
    let title: String
    let items: Data
    let id: KeyPath<Data.Element, ID>
    @ViewBuilder let card: (Data.Element) -> Card

    init(_ title: String, items: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder card: @escaping (Data.Element) -> Card) {
        self.title = title
        self.items = items
        self.id = id
        self.card = card
    }

    private static var trailingOverscan: CGFloat { 90 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: Theme.Spacing.cardGap) {
                    ForEach(items, id: id) { card($0) }
                }
                .padding(.leading, Theme.Spacing.gutter)
                .padding(.trailing, Theme.Spacing.gutter + Self.trailingOverscan)
                .padding(.top, Theme.Spacing.l + Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xl + Theme.Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .padding(.trailing, -Self.trailingOverscan)
            .horizontalEdgeFade()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

extension View {
    /// Clips scrolled content on the leading edge and dissolves it with an opacity gradient
    /// so cards scrolling left never overlap adjacent floating chrome such as `NavRail`.
    func horizontalEdgeFade(leadingWidth: CGFloat = Theme.Spacing.gutter) -> some View {
        clipped()
            .mask {
                HStack(spacing: 0) {
                    if leadingWidth > 0 {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.08), location: 0.20),
                                .init(color: .black.opacity(0.45), location: 0.55),
                                .init(color: .black.opacity(0.85), location: 0.82),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: leadingWidth)
                    }
                    Rectangle().fill(.black)
                }
            }
    }
}

extension ShelfRow where Data.Element: Identifiable, ID == Data.Element.ID {
    init(_ title: String, items: Data, @ViewBuilder card: @escaping (Data.Element) -> Card) {
        self.init(title, items: items, id: \.id, card: card)
    }
}
