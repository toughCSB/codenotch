import AppKit
import XCTest
@testable import ProviderMonitor

/// The notch floats above ordinary windows unless it is told not to. The
/// level is the whole of the setting: a floating window still outranks every
/// ordinary one, which is the thing being switched off.
@MainActor
final class NotchAlwaysOnTopTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "NotchAlwaysOnTopTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testThePanelStartsAboveOrdinaryWindows() {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 120, height: 400))
        XCTAssertEqual(panel.level, .statusBar)
    }

    func testTurningItOffDropsThePanelIntoTheOrdinaryOrder() {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 120, height: 400))
        panel.apply(alwaysOnTop: false)
        XCTAssertEqual(panel.level, .normal)
        panel.apply(alwaysOnTop: true)
        XCTAssertEqual(panel.level, .statusBar)
    }

    /// On by default — a notch another window can cover is one that disappears
    /// behind the window you were about to read it against — and an absent key
    /// is not a stored "off".
    func testTheSettingDefaultsToOnAndRoundTrips() {
        let defaults = freshDefaults()
        let first = Preferences(defaults: defaults)
        XCTAssertTrue(first.notchAlwaysOnTop)

        first.notchAlwaysOnTop = false
        XCTAssertFalse(Preferences(defaults: defaults).notchAlwaysOnTop)
    }
}
