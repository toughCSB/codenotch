import CoreGraphics

/// A press that may or may not turn out to be a drag.
///
/// The two gestures begin identically — one finger down on the notch — and only
/// the pointer's own travel tells them apart. Splitting the decision out of
/// `NotchPanel` is what lets the threshold be exercised without an event
/// stream, which is the one part of a drag a test cannot otherwise reach.
struct PressGesture {
    /// How far the pointer has to travel before the press is a drag.
    ///
    /// Points, not a share of the notch: this is a property of the hand and the
    /// trackpad, not of how large anything happens to be drawn. Small enough
    /// that a deliberate movement is a drag at once, large enough that the few
    /// pixels a finger rolls during a click stay a click. A ring is 44pt across
    /// and was being clicked accurately long before this existed, so nothing
    /// under a tenth of that can be stealing clicks from it.
    static let threshold: CGFloat = 4

    /// Total distance travelled rather than displacement: a pointer that leaves
    /// and comes back has still been dragged, and pretending otherwise would
    /// deliver a click nobody made.
    private(set) var travelled: CGFloat = 0
    private(set) var isDragging: Bool

    /// `immediate` is ⌥, which has always dragged from the first event.
    init(immediate: Bool) { isDragging = immediate }

    /// Feeds one pointer delta. True the moment the press becomes a drag —
    /// once, so the caller begins the drag exactly once.
    mutating func dragged(dx: CGFloat, dy: CGFloat) -> Bool {
        travelled += abs(dx) + abs(dy)
        guard !isDragging, travelled >= Self.threshold else { return false }
        isDragging = true
        return true
    }
}
