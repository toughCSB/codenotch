import Foundation
import Sparkle

/// Reads the original app's update feed, and reports what it says.
///
/// The feed is upstream Codenotch's — `SUFeedURL` and `SUPublicEDKey` in the
/// Info.plist are both upstream's own — which makes this the app's view of what
/// there is to port, and *not* a route by which this build is replaced. A check
/// allowed to install would quietly turn Provider Monitor back into the original
/// app the next time upstream shipped, undoing the fork in the background. So
/// this type only ever reports: `automaticallyDownloadsUpdates` is forced off
/// at launch and never turned on, and the manual check is Sparkle's probing one.
///
/// Putting *this* build where an app belongs is `LocalInstall`' job, and the two
/// are deliberately two controls in one pane: different questions, different
/// answers, and only one of them writes anything.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// What the last check came to, in words the settings sheet can show.
    ///
    /// Sparkle's own answer to a failed check is a modal saying "an error
    /// occurred in retrieving update information" — true, and useless: it names
    /// no cause and offers nothing to do. Keeping the outcome here lets the one
    /// place a user goes to think about updates say what actually happened.
    enum Outcome: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case found(String)
        case unreachable
        case failed(String)

        var message: String? {
            switch self {
            case .idle:          return nil
            case .checking:      return L10n.t("Checking…")
            case .upToDate:      return L10n.t("The original app's feed has no newer version.")
            case .found(let v):  return L10n.t("Codenotch \(v) is available upstream.")
            case .unreachable:
                // The one people actually hit, and the one Sparkle's wording
                // hides: nothing is wrong with the app or the machine.
                return L10n.t("Couldn't reach the update server. Provider Monitor will try again on its own — nothing is wrong with this copy.")
            case .failed(let why): return why
            }
        }
    }

    @Published private(set) var outcome: Outcome = .idle

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
    )

    /// Whether the scheduled check runs — a check and never an install,
    /// whatever this is set to. See the type's own note.
    var automatic: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var lastChecked: Date? { controller.updater.lastUpdateCheckDate }

    /// Starts the scheduled checks. Deliberately not in `init`: the controller
    /// is lazy so that `self` exists before it is handed over as the delegate.
    func start() {
        _ = controller
        // Set on every launch, not only when the setting moves: a copy whose
        // preferences were written by an earlier build — or by upstream itself
        // — must not be able to download its own replacement from a feed that
        // is not this app's.
        controller.updater.automaticallyDownloadsUpdates = false
    }

    /// The manual path, for someone who does not want to wait for the schedule.
    ///
    /// Sparkle's probing check: it fetches the appcast and reports through the
    /// delegate without ever offering to install what it found. That is the
    /// whole point — the ordinary check ends in a window with an Install button
    /// on it, and the update behind that button is the original app, not this
    /// one. The answer here is the message the pane shows.
    func checkNow() {
        outcome = .checking
        controller.updater.checkForUpdateInformation()
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.outcome = .upToDate(Date()) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.outcome = .found(version) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let code = (error as NSError).code
        Task { @MainActor in
            // A feed that cannot be fetched is the ordinary failure — offline,
            // or the server is down — and it is not the user's problem to
            // solve. Anything else is reported as itself.
            self.outcome = Self.isUnreachable(code)
                ? .unreachable
                : .failed(error.localizedDescription)
        }
    }

    /// Sparkle folds every "could not load the feed" case into one code.
    static func isUnreachable(_ code: Int) -> Bool {
        code == Int(SUError.appcastError.rawValue)
    }
}
