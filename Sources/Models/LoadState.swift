import Foundation

/// Lifecycle of a screen's remote data.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    static func failure(_ error: Error) -> LoadState {
        .failed(error.localizedDescription)
    }
}
