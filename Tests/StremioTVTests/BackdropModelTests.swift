import Testing
@testable import StremioTV

@MainActor
struct BackdropModelTests {
    @Test func lastFocusedTitleWinsAfterTheDelay() async {
        let model = BackdropModel(delay: .milliseconds(30))
        model.focus(movie("a"))
        model.focus(movie("b"))
        model.focus(movie("c"))
        #expect(model.item == nil) // nothing applied while the user is still moving
        await model.settle()
        #expect(model.item?.id == "c")
    }

    @Test func nilGoesBackToTheDefaultTitle() async {
        let model = BackdropModel(delay: .milliseconds(10))
        model.focus(movie("a"))
        await model.settle()
        model.focus(nil)
        await model.settle()
        #expect(model.item == nil)
    }
}
