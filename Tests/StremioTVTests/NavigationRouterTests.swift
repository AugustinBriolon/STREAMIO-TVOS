import XCTest
import SwiftUI
@testable import StremioTV

@MainActor
final class NavigationRouterTests: XCTestCase {

    func testInitialStateIsAtRoot() {
        let router = NavigationRouter()
        for tab in AppTab.allCases {
            XCTAssertTrue(router.isAtRoot(for: tab), "L'onglet \(tab) devrait être à la racine initialement")
        }
    }

    func testPushingAndPopToRoot() {
        let router = NavigationRouter()
        XCTAssertTrue(router.isAtRoot(for: .home))

        // Simule la navigation vers un média (1 écran poussé)
        router.homePath.append("tt0117509")
        XCTAssertFalse(router.isAtRoot(for: .home))
        XCTAssertEqual(router.homePath.count, 1)

        // Simule la navigation vers la page d'un acteur (2 écrans poussés)
        router.homePath.append("actor-6193")
        XCTAssertFalse(router.isAtRoot(for: .home))
        XCTAssertEqual(router.homePath.count, 2)

        // Contrat Pop-to-Root : dépilement complet
        router.popToRoot(for: .home)
        XCTAssertTrue(router.isAtRoot(for: .home))
        XCTAssertEqual(router.homePath.count, 0)
    }

    func testTabIsolation() {
        let router = NavigationRouter()

        router.homePath.append("media-1")
        router.moviesPath.append("media-2")

        XCTAssertFalse(router.isAtRoot(for: .home))
        XCTAssertFalse(router.isAtRoot(for: .movies))
        XCTAssertTrue(router.isAtRoot(for: .series))
        XCTAssertTrue(router.isAtRoot(for: .search))

        // Dépiler Home n'affecte pas Movies
        router.popToRoot(for: .home)
        XCTAssertTrue(router.isAtRoot(for: .home))
        XCTAssertFalse(router.isAtRoot(for: .movies))
    }

    func testBindingPathUpdatesRouter() {
        let router = NavigationRouter()
        let binding = router.path(for: .myList)

        XCTAssertTrue(router.isAtRoot(for: .myList))

        binding.wrappedValue.append("media-my-list")
        XCTAssertFalse(router.isAtRoot(for: .myList))

        binding.wrappedValue = NavigationPath()
        XCTAssertTrue(router.isAtRoot(for: .myList))
    }
}
