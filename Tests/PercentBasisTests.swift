import XCTest
@testable import ProviderMonitor

/// The number under a ring is the one reading whose *direction* is a matter of
/// taste. The arc is not: it fills as the limit is spent whichever way round
/// the figure under it counts, because a ring that meant the opposite would
/// need the space above it read as the limit.
@MainActor
final class PercentBasisTests: XCTestCase {
    private func snapshot(_ fraction: Double, basis: Percent.Basis) -> ProviderSnapshot {
        ProviderSnapshot(id: "p", displayName: "P", glyph: .third, fidelity: .official,
                         status: .ok,
                         windows: [LimitWindow(id: "w", label: "W", usedFraction: fraction)],
                         headlineID: "w", percentBasis: basis)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "PercentBasisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Left of centre, because "how much is left" is the question a quota is
    /// usually asked.
    func testWhatIsLeftIsTheDefault() {
        XCTAssertEqual(Preferences(defaults: freshDefaults()).percentBasis, .remaining)
        XCTAssertEqual(snapshot(0.12, basis: .remaining).headlineText, "88%")
    }

    /// And the other way round on request — the same reading, the other half.
    func testTheSameReadingReportsWhicheverHalfIsAsked() {
        XCTAssertEqual(snapshot(0.12, basis: .used).headlineText, "12%")
        XCTAssertEqual(snapshot(0.12, basis: .remaining).headlineText, "88%")
    }

    func testTheRingGraphUsesTheSameBasisAsItsNumber() {
        XCTAssertEqual(snapshot(0.12, basis: .used).displayedRingFraction, 0.12)
        XCTAssertEqual(snapshot(0.12, basis: .remaining).displayedRingFraction, 0.88)
    }

    func testNearFullRemainingTextHasNoComparisonSign() {
        XCTAssertEqual(snapshot(0.0004, basis: .remaining).headlineText, "99.9%")
        XCTAssertFalse(snapshot(0.0004, basis: .remaining).headlineText.contains(">"))
    }

    /// Both halves come off the same rounding, or the ring and the card would
    /// contradict each other about the same window.
    func testTheHalvesAgreeAtEveryFraction() {
        for percent in stride(from: 0, through: 100, by: 7) {
            let fraction = Double(percent) / 100
            let halves = Percent.halves(for: fraction)
            XCTAssertEqual(snapshot(fraction, basis: .used).headlineText, halves.used + "%")
            XCTAssertEqual(snapshot(fraction, basis: .remaining).headlineText, halves.left + "%")
        }
    }

    /// A window that counts something rather than measuring it against a limit
    /// has no other half, and the basis must not invent one.
    func testACountIsUntouchedByTheChoice() {
        let snapshot = ProviderSnapshot(
            id: "p", displayName: "P", glyph: .third, fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "w", label: "Requests", used: 8)],
            headlineID: "w", percentBasis: .remaining
        )
        XCTAssertEqual(snapshot.headlineText, "8")
    }

    /// A provider with nothing to show says so, either way round.
    func testNothingToShowIsNotAZero() {
        for basis in Percent.Basis.allCases {
            let snapshot = ProviderSnapshot(
                id: "p", displayName: "P", glyph: .third, fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "w", label: "W")],
                headlineID: "w", percentBasis: basis
            )
            XCTAssertEqual(snapshot.headlineText, "—")
        }
    }

    /// The choice survives a relaunch, and an absent value is not the same as
    /// a stored "used".
    func testTheChoiceIsStoredAndRoundTrips() {
        let defaults = freshDefaults()
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.percentBasis, .remaining)
        first.percentBasis = .used

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.percentBasis, .used)
    }

    /// Both titles exist for the picker, and they are not each other.
    func testTheTwoChoicesAreDistinguishable() {
        XCTAssertEqual(Percent.Basis.allCases.count, 2)
        XCTAssertNotEqual(Percent.Basis.remaining.title, Percent.Basis.used.title)
    }
}
