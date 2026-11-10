import TVServices

/// Tells the system the Top Shelf content changed, so it reloads "Reprendre la lecture" (ADR 0015).
enum TopShelfRefresher {
    static func refresh() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
