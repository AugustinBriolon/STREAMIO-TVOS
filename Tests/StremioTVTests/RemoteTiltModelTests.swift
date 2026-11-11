import Testing
@testable import StremioTV

@MainActor
struct RemoteTiltModelTests {
    @Test func neutralOnStart() {
        let model = RemoteTiltModel()
        #expect(model.x == 0)
        #expect(model.y == 0)
        #expect(!model.isTouching)
    }

    @Test func updatesCoordinatesAndClampsWithinBounds() {
        let model = RemoteTiltModel()
        model.handle(x: 0.6, y: -0.4)
        #expect(model.x == 0.6)
        #expect(model.y == -0.4)
        #expect(model.isTouching)

        // Clamping to -1...1
        model.handle(x: 2.5, y: -3.0)
        #expect(model.x == 1.0)
        #expect(model.y == -1.0)
        #expect(model.isTouching)
    }

    @Test func deadzoneIgnoresMicroJitter() {
        let model = RemoteTiltModel()
        model.handle(x: 0.005, y: -0.008)
        #expect(model.x == 0)
        #expect(model.y == 0)
        #expect(!model.isTouching)
    }

    @Test func settleResetsToNeutral() {
        let model = RemoteTiltModel()
        model.handle(x: 0.8, y: 0.5)
        #expect(model.isTouching)
        model.settle()
        #expect(model.x == 0)
        #expect(model.y == 0)
        #expect(!model.isTouching)
    }
}
