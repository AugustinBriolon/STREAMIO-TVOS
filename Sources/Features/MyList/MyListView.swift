import SwiftUI

struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var backdrop = BackdropModel()

    var body: some View {
        NavigationStack {
            ZStack {
                DynamicBackdrop(model: backdrop, fallback: library.myList.first)
                list
            }
            .opensRailOnExit()
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
    }

    @ViewBuilder
    private var list: some View {
        Group {
                if library.myList.isEmpty {
                    StateView(kind: .empty(
                        symbol: "plus.rectangle.on.rectangle",
                        title: "Votre liste est vide",
                        message: "Ajoutez des films et des séries avec le bouton « Ma liste » pour les retrouver ici."
                    ))
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                            Text("Ma liste")
                                .font(Theme.Typography.pageTitle)
                                .padding(.horizontal, Theme.Spacing.gutter)
                            PosterGrid(title: nil, items: library.myList, onFocus: backdrop.focus)
                        }
                        .padding(.vertical, Theme.Spacing.l)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
