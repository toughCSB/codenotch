import AppKit

/// Installing *this* build, as opposed to reading the original app's feed.
///
/// Two different questions with two different answers, which is why the app
/// asks them in two places. `Updater` reports what upstream Codenotch has
/// shipped — a fork's view of what there is to port. This puts the build that is
/// running where an app belongs, so the copy that gets launched is the one whose
/// readings are on screen. Nothing here touches the network.
@MainActor
final class LocalInstall: ObservableObject {
    enum Outcome: Equatable {
        case idle
        case installing
        case alreadyThere
        case installed(URL)
        case failed(String)

        var message: String? {
            switch self {
            case .idle:            return nil
            case .installing:      return L10n.t("Installing…")
            case .alreadyThere:    return L10n.t("Provider Monitor is already the app in /Applications.")
            case .installed:       return L10n.t("Installed in /Applications. Quit and reopen Provider Monitor to run this build.")
            case .failed(let why): return L10n.t("Could not install: \(why)")
            }
        }

        /// Whether this is the one outcome worth colouring: reported as a
        /// failure rather than as a fact about the copy on disk.
        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var outcome: Outcome = .idle

    /// Where an app belongs: with every other one on the machine, where
    /// Spotlight, the login item and the Finder all look for it.
    static var defaultDestination: URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent("Provider Monitor.app", isDirectory: true)
    }

    /// Writable so the copy can be exercised without touching the real
    /// /Applications: under XCTest the app *is* the test host, so `Bundle.main`
    /// is the very build that would otherwise be copied there.
    var destination: URL = LocalInstall.defaultDestination

    /// The bundle that is running — the build being installed.
    ///
    /// Writable for the same reason `destination` is: the unit tests run inside
    /// the app as their host, so the real answer is the 100MB build under test,
    /// and a test that copied *that* would be measuring the disk rather than
    /// this rule.
    var runningFrom: URL = Bundle.main.bundleURL

    /// True when the running copy is the installed one, which is the state this
    /// button exists to reach and therefore has nothing left to do in.
    var isInstalledCopy: Bool {
        runningFrom.standardizedFileURL == destination.standardizedFileURL
    }

    func install() {
        guard !isInstalledCopy else {
            outcome = .alreadyThere
            return
        }
        outcome = .installing
        do {
            try copyIntoPlace(from: runningFrom, to: destination)
            outcome = .installed(destination)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    /// Copies the bundle in beside its destination and swaps it into place.
    ///
    /// Staged rather than copied over the top, so the swap can be atomic: an
    /// install that is interrupted — a full disk, a permission prompt dismissed
    /// — leaves whatever was already there untouched rather than half a bundle.
    ///
    /// `ditto` rather than `FileManager.copyItem`, because a bundle is more than
    /// the files inside it: extended attributes, the symlinks inside a framework
    /// and the resource envelope the code signature covers all have to survive,
    /// and `ditto` is the tool that keeps them.
    private func copyIntoPlace(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".(destination.lastPathComponent).(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: staging)
        defer { try? FileManager.default.removeItem(at: staging) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = [source.path, staging.path]
        let complaint = Pipe()
        ditto.standardError = complaint
        try ditto.run()
        let said = complaint.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw InstallProblem(why: String(decoding: said, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }
}

/// What `ditto` said, when it said anything at all.
private struct InstallProblem: LocalizedError {
    let why: String
    var errorDescription: String? {
        why.isEmpty ? L10n.t("Provider Monitor could not be written to /Applications.") : why
    }
}
