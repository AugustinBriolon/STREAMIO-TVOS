import TVServices

/// Top Shelf of the Apple TV home screen: the active profile's "Reprendre la lecture" and "Ma liste"
/// (ADR 0015, 0016). Returning nil makes the system show the static Top Shelf image from the asset catalog.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let sections = TopShelfSection.load(defaults: AppGroup.defaults)
        guard !sections.isEmpty else { return nil }

        return TVTopShelfSectionedContent(sections: sections.map { section in
            let collection = TVTopShelfItemCollection(items: section.entries.map(Self.item))
            collection.title = section.title
            return collection
        })
    }

    private static func item(_ entry: TopShelfEntry) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: entry.id)
        item.title = entry.title
        item.imageShape = entry.isPoster ? .poster : .hdtv
        if let url = entry.imageURL {
            item.setImageURL(url, for: [.screenScale1x, .screenScale2x])
        }
        if let progress = entry.progress { item.playbackProgress = progress }
        item.playAction = TVTopShelfAction(url: entry.playLink.url)
        item.displayAction = TVTopShelfAction(url: entry.displayLink.url)
        return item
    }
}
