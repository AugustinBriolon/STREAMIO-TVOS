import SwiftUI

/// Titled horizontal row of focusable cards. Focus scale is allowed to overflow the row bounds.
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: Theme.Spacing.cardGap) {
                    ForEach(items, id: id) { card($0) }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

extension ShelfRow where Data.Element: Identifiable, ID == Data.Element.ID {
    init(_ title: String, items: Data, @ViewBuilder card: @escaping (Data.Element) -> Card) {
        self.init(title, items: items, id: \.id, card: card)
    }
}
