import SwiftUI

struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.railOpener) private var opener
    @State private var backdrop = BackdropModel()
    @FocusState private var focusedItemID: String?
    @State private var lastFocusedItemID: String?
    @State private var pendingNeighborID: String?
    @State private var focusRestoreTarget: String?
    @State private var focusRestoreTask: Task<Void, Never>?
    @Binding var path: NavigationPath

    private let columns = [GridItem(.adaptive(minimum: Theme.Card.posterSize.width), spacing: Theme.Spacing.cardGap)]

    init(path: Binding<NavigationPath> = .constant(NavigationPath())) {
        _path = path
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DynamicBackdrop(model: backdrop, fallback: library.myList.first)
                list
            }
            .opensRailOnExit()
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
            .navigationDestination(for: CastMember.self) { PersonDetailView(member: $0) }
        }
        .onChange(of: focusedItemID) { _, newValue in
            if let newValue {
                lastFocusedItemID = newValue
            }
        }
        .onChange(of: library.myList.map(\.id)) { oldIDs, newIDs in
            guard let targetSource = lastFocusedItemID,
                  oldIDs.contains(targetSource),
                  !newIDs.contains(targetSource) else { return }
            let neighbor = FocusNeighbor.nearestRemaining(oldIDs: oldIDs, newIDs: newIDs, removedID: targetSource)
            if path.isEmpty {
                if let neighbor {
                    restoreFocusAfterRemoval(neighbor)
                } else {
                    openRailAfterEmptyRemoval()
                }
            } else {
                pendingNeighborID = neighbor
            }
        }
        .onChange(of: path.count) { _, count in
            guard count == 0 else { return }
            if let neighbor = pendingNeighborID {
                pendingNeighborID = nil
                restoreFocusAfterRemoval(neighbor)
            } else if library.myList.isEmpty, lastFocusedItemID != nil {
                lastFocusedItemID = nil
                openRailAfterEmptyRemoval()
            }
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
                            .font(Theme.Typography.pageTitle).tracking(Theme.Typography.displayTracking)
                            .padding(.horizontal, Theme.Spacing.gutter)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
                            ForEach(library.myList) { item in
                                NavigationLink(value: item) { PosterCard(item: item) }
                                    .buttonStyle(CardFocusStyle(onFocus: {
                                        backdrop.focus(item)
                                        lastFocusedItemID = item.id
                                        if focusRestoreTarget == item.id {
                                            focusRestoreTarget = nil
                                            focusRestoreTask?.cancel()
                                        }
                                    }))
                                    .focused($focusedItemID, equals: item.id)
                                    .contextMenu {
                                        Button("Retirer de Ma liste", systemImage: "xmark.circle", role: .destructive) {
                                            removeFromMyList(item)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.gutter)
                        .focusSection()
                    }
                    .padding(.vertical, Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func removeFromMyList(_ item: MediaItem) {
        let neighbor = FocusNeighbor.nearestRemainingID(in: library.myList.map(\.id), removing: item.id)
        lastFocusedItemID = nil
        pendingNeighborID = nil
        library.toggleMyList(item)
        if let neighbor {
            restoreFocusAfterRemoval(neighbor)
        } else {
            openRailAfterEmptyRemoval()
        }
    }

    private func restoreFocusAfterRemoval(_ targetID: String) {
        focusRestoreTarget = targetID
        FocusRestorer.schedule(
            target: targetID,
            focus: $focusedItemID,
            currentTask: &focusRestoreTask,
            isStillPending: { focusRestoreTarget == targetID },
            onExhausted: { if focusRestoreTarget == targetID { focusRestoreTarget = nil } }
        )
    }

    private func openRailAfterEmptyRemoval() {
        focusRestoreTask?.cancel()
        focusRestoreTarget = nil
        focusRestoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled, library.myList.isEmpty else { return }
            opener.open()
        }
    }
}
