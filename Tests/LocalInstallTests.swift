import XCTest
@testable import ProviderMonitor

/// Putting the running build where an app belongs.
///
/// The counterpart to `UpdateOutcomeTests`: that one is about what the original
/// app's feed says, this one is about this build on this Mac. The two are
/// deliberately separate controls, so the two are tested apart.
///
/// Everything here works in a temporary directory. The tests run *inside* the
/// app, so `Bundle.main` is the very build that would otherwise be copied to the
/// real /Applications — a test that did that would install the suite's host
/// over the user's copy.
@MainActor
final class LocalInstallTests: XCTestCase {
    private var root: URL!
    private var build: URL!
    private var destination: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LocalInstallTests-\(UUID().uuidString)", isDirectory: true)
        build = root.appendingPathComponent("DerivedData/Provider Monitor.app", isDirectory: true)
        destination = root.appendingPathComponent("Applications/Provider Monitor.app", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// A stand-in with the one thing that has to survive the copy: a file where
    /// a bundle keeps its executable.
    @discardableResult
    private func makeBundle(at bundle: URL, marker: String) throws -> URL {
        let executable = bundle.appendingPathComponent("Contents/MacOS/Provider Monitor")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: executable)
        return bundle
    }

    private func installer() -> LocalInstall {
        let installer = LocalInstall()
        installer.runningFrom = build
        installer.destination = destination
        return installer
    }

    private func contentsOfDestinationFolder() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
            .sorted()
    }

    func testItCopiesTheRunningBuildIntoPlace() throws {
        try makeBundle(at: build, marker: "the build that is running")
        let installer = installer()
        XCTAssertFalse(installer.isInstalledCopy)

        installer.install()

        XCTAssertEqual(installer.outcome, .installed(destination))
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("Contents/MacOS/Provider Monitor"),
                       encoding: .utf8),
            "the build that is running"
        )
        // Staged and swapped, never half-copied: nothing but the app itself is
        // left in the folder.
        XCTAssertEqual(try contentsOfDestinationFolder(), ["Provider Monitor.app"])
    }

    /// What was there is replaced rather than merged: an install is the copy on
    /// disk being made to match this build, and a file the old bundle had is a
    /// file the new one does not.
    func testItReplacesTheCopyThatWasAlreadyThere() throws {
        try makeBundle(at: build, marker: "the build that is running")
        try makeBundle(at: destination, marker: "an older build")
        try Data("stale".utf8).write(to: destination.appendingPathComponent("Contents/stale.txt"))

        installer().install()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/stale.txt").path),
            "the old bundle's own file survived the install"
        )
        XCTAssertEqual(try contentsOfDestinationFolder(), ["Provider Monitor.app"])
    }

    /// The state this button exists to reach, and therefore one it must not
    /// work in: a build already installed has nothing to copy onto itself.
    func testItDoesNothingWhenTheRunningCopyIsTheInstalledOne() throws {
        try makeBundle(at: destination, marker: "already installed")
        let installer = LocalInstall()
        installer.runningFrom = destination
        installer.destination = destination
        XCTAssertTrue(installer.isInstalledCopy)

        installer.install()

        XCTAssertEqual(installer.outcome, .alreadyThere)
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("Contents/MacOS/Provider Monitor"),
                       encoding: .utf8),
            "already installed"
        )
    }

    /// A failure is reported rather than thrown at nobody, and it leaves the
    /// folder as it found it — the staging copy is not left as litter beside
    /// the app it could not become.
    func testAFailedCopySaysWhyAndLeavesNothingBehind() throws {
        try makeBundle(at: build, marker: "the build that is running")
        // A destination whose parent is a *file*: the copy cannot be made, and
        // the reason has to reach the pane.
        let blocker = root.appendingPathComponent("blocked")
        try Data("not a folder".utf8).write(to: blocker)

        let installer = LocalInstall()
        installer.runningFrom = build
        installer.destination = blocker.appendingPathComponent("Provider Monitor.app")
        installer.install()

        guard case .failed(let why) = installer.outcome else {
            return XCTFail("expected a failure, got \(installer.outcome)")
        }
        XCTAssertFalse(why.isEmpty, "a failure with nothing to say reads as a broken button")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
                       ["DerivedData", "blocked"])
    }

    /// Every outcome a user can land on has words, except the one that means
    /// nothing has been asked yet.
    func testEveryOutcomeExceptIdleSaysSomething() {
        XCTAssertNil(LocalInstall.Outcome.idle.message)
        for outcome: LocalInstall.Outcome in [.installing, .alreadyThere,
                                              .installed(destination), .failed("disk full")] {
            XCTAssertNotNil(outcome.message, "\(outcome) says nothing")
        }
    }

    func testOnlyAFailureIsColouredAsOne() {
        XCTAssertTrue(LocalInstall.Outcome.failed("disk full").isFailure)
        XCTAssertFalse(LocalInstall.Outcome.alreadyThere.isFailure)
        XCTAssertFalse(LocalInstall.Outcome.installed(destination).isFailure)
    }
}
