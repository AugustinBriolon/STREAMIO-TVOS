import TVServices

/// Top Shelf of the Apple TV home screen: the active profile's "Reprendre la lecture" (ADR 0015).
/// Returning nil makes the system show the static Top Shelf image from the asset catalog.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let entries = TopShelfEntry.load(defaults: AppGroup.defaults)
        guard !entries.isEmpty else { return nil }

        let items = entries.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: entry.id)
            item.title = [entry.title, entry.subtitle].compactMap { $0 }.joined(separator: " · ")
            item.imageShape = .hdtv
            if let url = entry.imageURL {
                item.setImageURL(url, for: [.screenScale1x, .screenScale2x])
            }
            item.playbackProgress = entry.progress
            item.playAction = TVTopShelfAction(url: entry.link)
            item.displayAction = TVTopShelfAction(url: entry.link)
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Reprendre la lecture"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
