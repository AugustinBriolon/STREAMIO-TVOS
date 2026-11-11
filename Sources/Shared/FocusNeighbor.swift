import Foundation

/// Resolves the closest surviving item identifier when an element is removed from a tvOS list or grid.
enum FocusNeighbor {
    /// Returns the ID of the nearest remaining item in `newIDs` relative to `removedID`'s position in `oldIDs`.
    /// Prefers the element immediately following the removed item (right/next), falling back to the
    /// preceding element (left/previous) when the removed item was last.
    static func nearestRemaining(oldIDs: [String], newIDs: [String], removedID: String) -> String? {
        guard !newIDs.isEmpty else { return nil }
        let surviving = Set(newIDs)
        guard let removedIndex = oldIDs.firstIndex(of: removedID) else {
            return newIDs.first
        }

        // Prefer the nearest surviving neighbor to the right (same visual slot after collapse).
        for idx in (removedIndex + 1)..<oldIDs.count where surviving.contains(oldIDs[idx]) {
            return oldIDs[idx]
        }
        // Otherwise step backwards to the nearest surviving neighbor on the left.
        for idx in stride(from: removedIndex - 1, through: 0, by: -1) where surviving.contains(oldIDs[idx]) {
            return oldIDs[idx]
        }
        return newIDs.first
    }

    /// Convenience helper when removing a single element directly from `orderedIDs`.
    static func nearestRemainingID(in orderedIDs: [String], removing id: String) -> String? {
        let newIDs = orderedIDs.filter { $0 != id }
        return nearestRemaining(oldIDs: orderedIDs, newIDs: newIDs, removedID: id)
    }
}
