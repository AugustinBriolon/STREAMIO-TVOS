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

struct MotionTests {
    @Test func aFocusedControlDipsWhenPressed() {
        let resting = Theme.Motion.scale(focused: true, pressed: false, reduceMotion: false)
        let pressed = Theme.Motion.scale(focused: true, pressed: true, reduceMotion: false)
        #expect(resting == Theme.Motion.focusScale)
        #expect(pressed < resting)          // the click is visible on the focused element
        #expect(pressed > 1)                // but it stays the focused one
        #expect(Theme.Motion.scale(focused: false, pressed: false, reduceMotion: false) == 1)
    }

    @Test func wideRowsLiftLessThanCards() {
        let row = Theme.Motion.scale(focused: true, pressed: false, focusScale: Theme.Motion.rowFocusScale, reduceMotion: false)
        #expect(row == Theme.Motion.rowFocusScale)
        #expect(row < Theme.Motion.focusScale)
    }

    @Test func reduceMotionRemovesScaling() {
        #expect(Theme.Motion.scale(focused: true, pressed: true, reduceMotion: true) == 1)
    }
}
