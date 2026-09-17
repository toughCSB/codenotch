import XCTest
@testable import ProviderMonitor

/// A press on the notch is a click until the pointer says otherwise. The
/// threshold is the whole of that decision, and it is the one part of a drag
/// that cannot be reached through an event stream in a test.
final class PressGestureTests: XCTestCase {
    func testAPressThatNeverMovesIsAClick() {
        var gesture = PressGesture(immediate: false)

        XCTAssertFalse(gesture.dragged(dx: 0, dy: 0))
        XCTAssertFalse(gesture.isDragging)
    }

    /// A finger rolls a little during a click. That it rolled is not a drag.
    func testASmallRollIsStillAClick() {
        var gesture = PressGesture(immediate: false)

        XCTAssertFalse(gesture.dragged(dx: 1, dy: 1))
        XCTAssertFalse(gesture.dragged(dx: -0.5, dy: 0.5))
        XCTAssertFalse(gesture.isDragging, "two points of travel is not a drag")
    }

    func testTravellingPastTheThresholdIsADrag() {
        var gesture = PressGesture(immediate: false)

        XCTAssertFalse(gesture.dragged(dx: 0, dy: 2))
        XCTAssertTrue(gesture.dragged(dx: 0, dy: 2), "four points of travel is")
        XCTAssertTrue(gesture.isDragging)
    }

    /// The caller begins the drag on the gesture's own word, so it has to give
    /// that word once. Answered twice, `NotchWindowController` would suspend its
    /// hover tracking a second time for a drag already in progress.
    func testItBecomesADragExactlyOnce() {
        var gesture = PressGesture(immediate: false)

        XCTAssertTrue(gesture.dragged(dx: 10, dy: 0))
        XCTAssertFalse(gesture.dragged(dx: 10, dy: 0))
        XCTAssertFalse(gesture.dragged(dx: 10, dy: 0))
        XCTAssertTrue(gesture.isDragging)
    }

    /// ⌥ has dragged from the first event since the nudge existed, and a
    /// threshold in front of it would be a delay on a gesture that has none.
    func testOptionDragsFromTheFirstPixel() {
        var gesture = PressGesture(immediate: true)

        XCTAssertTrue(gesture.isDragging)
        XCTAssertFalse(gesture.dragged(dx: 0, dy: 0), "already dragging; nothing to announce")
    }

    /// Distance, not displacement. A pointer that goes out and comes back has
    /// been dragged, and delivering a click on release would be answering a
    /// gesture nobody made.
    func testComingBackDoesNotUndoTheTravel() {
        var wander = PressGesture(immediate: false)
        XCTAssertFalse(wander.dragged(dx: 3, dy: 0))
        XCTAssertTrue(wander.dragged(dx: -3, dy: 0),
                      "three there and three back is six points travelled, however still the pointer is")
    }
}
