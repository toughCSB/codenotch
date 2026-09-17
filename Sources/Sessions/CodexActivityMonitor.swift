import AppKit
import Combine
import Foundation

/// The small, stable part of a Codex rollout that is useful for activity.
///
/// `item_completed` is intentionally ignored: commands and other child items
/// emit it too. A turn is complete only after Codex writes `task_complete`.
struct CodexRolloutActivity {
    enum State: Equatable {
        case busy
        case success
    }

    /// What one record can say about the turn.
    private enum Event: Equatable {
        case started
        case completed
        case aborted
    }

    /// The bytes a record has to contain before it is worth parsing.
    ///
    /// A rollout is almost entirely records that cannot change the answer —
    /// messages, tool output, token counts — and JSON-parsing every one of them
    /// every couple of seconds is what made this expensive. On a 38 MB
    /// conversation it held the main thread at most of a core, and the notch
    /// answered the pointer late because of it. The byte test below costs a
    /// fraction of the parse, so only the few records that pass it are decoded.
    private static let needles: [(bytes: [UInt8], type: String, event: Event)] = [
        (Array(#""task_started""#.utf8), "task_started", .started),
        (Array(#""task_complete""#.utf8), "task_complete", .completed),
        (Array(#""turn_aborted""#.utf8), "turn_aborted", .aborted),
    ]

    /// How far a reading has got through one rollout, and what it left behind.
    struct Cursor: Equatable {
        var offset: UInt64
        var modified: Date?
        var state: State?
    }

    /// The state the rollout's newest lifecycle event leaves behind.
    ///
    /// `nil` is what a rollout with no lifecycle event at all reports, and also
    /// what an aborted turn reports: an abort completed nothing, and nil lets
    /// the activity monitor drop it without announcing.
    ///
    /// A rollout is appended to for the life of a conversation, and this is
    /// asked for every couple of seconds while one is running. Reading the file
    /// from the top each time was the whole cost of that: every record decoded
    /// again, on the main thread, at most of a core on a 38 MB conversation —
    /// which is why the notch answered the pointer late. Only what has been
    /// appended since the last read can change the answer, so a repeat read
    /// looks at that and nothing else. The answer itself is unchanged: a cursor
    /// records where a reading got to, it does not read differently.
    static func state(from url: URL) -> State? {
        cursors.state(of: url)
    }

    /// Every lifecycle event in `data`, applied in order, so the newest wins.
    ///
    /// `item_completed` and every other record is ignored: commands and other
    /// child items emit those too, and a turn is complete only after Codex
    /// writes `task_complete`.
    private static func state(of data: Data, carrying carried: State?) -> State? {
        var state = carried
        for line in data.split(separator: 0x0A) {
            guard let event = event(in: line) else { continue }
            switch event {
            case .started:   state = .busy
            case .completed: state = .success
            // An aborted turn is not a successful completion.
            case .aborted:   state = nil
            }
        }
        return state
    }

    /// Where each rollout that has been read got to.
    ///
    /// Guarded by a lock rather than confined to an actor because `state(from:)`
    /// answers whoever asks; the app asks from the main thread. Bounded, because
    /// a rollout file never goes away on its own and one entry per conversation
    /// would accumulate for as long as the app runs — and dropping an entry only
    /// costs the next reading of that rollout its head start.
    private static let cursors = CursorStore()

    private final class CursorStore {
        private let lock = NSLock()
        private var cursors: [String: Cursor] = [:]
        private let limit = 16

        func state(of url: URL) -> State? {
            let path = url.path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes?[.modificationDate] as? Date

            lock.lock()
            defer { lock.unlock() }

            var carried = cursors[path]
            // A file that shrank, or one rewritten where it stood, is not the
            // file that was read: start again rather than trust the offset.
            if let cursor = carried, cursor.offset > size || (cursor.modified != modified && cursor.offset == size) {
                carried = nil
            }
            if let cursor = carried, cursor.offset == size {
                return cursor.state
            }

            guard let read = read(url, from: carried?.offset ?? 0) else {
                return carried?.state
            }
            let state = CodexRolloutActivity.state(of: read.bytes, carrying: carried?.state)
            if cursors.count >= limit, cursors[path] == nil, let oldest = cursors.keys.first {
                cursors.removeValue(forKey: oldest)
            }
            cursors[path] = Cursor(offset: read.offset, modified: modified, state: state)
            return state
        }

        /// Everything from `offset` on, and the size that was read to.
        private func read(_ url: URL, from offset: UInt64) -> (bytes: Data, offset: UInt64)? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd(),
                  (try? handle.seek(toOffset: min(offset, size))) != nil,
                  let data = try? handle.readToEnd() else { return nil }
            return (data, size)
        }
    }

    /// The lifecycle event a record reports, or `nil` for a record that reports
    /// none — which is most of them.
    private static func event(in line: Data) -> Event? {
        // A record that does not even contain the words is not worth a parse.
        guard let needle = needles.first(where: { mentions(line, $0.bytes) }) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let record = object as? [String: Any],
              record["type"] as? String == "event_msg",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == needle.type
        else { return nil }
        return needle.event
    }

    /// A byte-window search, so a record can be rejected without being parsed.
    private static func mentions(_ line: Data, _ needle: [UInt8]) -> Bool {
        let count = line.count
        guard !needle.isEmpty, count >= needle.count else { return false }
        return line.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            let last = count - needle.count
            var offset = 0
            while offset <= last {
                if base[offset] == needle[0] {
                    var i = 1
                    var matched = true
                    while i < needle.count {
                        if base[offset + i] != needle[i] { matched = false; break }
                        i += 1
                    }
                    if matched { return true }
                }
                offset += 1
            }
            return false
        }
    }
}

/// Reports whether Codex is mid-turn.
///
/// Codex does not publish a live status field, but its rollout includes
/// lifecycle events. `task_started` and `task_complete` are used when present;
/// the file's recent modification time remains the activity fallback.
///
/// **That is a heuristic, and it is labelled as one.** It cannot tell a turn
/// that is thinking from one that finished a second ago, so it errs short: the
/// ring stops spinning `staleAfter` seconds after the last write rather than
/// claiming activity it cannot see. A stale rollout is deliberately not
/// converted into `.success` or `.idle`, because inactivity is not evidence
/// that a Codex turn completed — a long-running command can be quiet too.
/// If Codex grows a real status field this should be replaced by it.
@MainActor
final class CodexActivityMonitor: ObservableObject, AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let stateStore: URL
    private let desktopStore: URL
    private let profile: CodexProfile
    private let interval: TimeInterval
    /// How long after the last write a turn is still considered in flight.
    private let staleAfter: TimeInterval
    private var timer: Timer?

    init(
        profile: CodexProfile = .default(),
        stateStore: URL? = nil,
        desktopStore: URL? = nil,
        interval: TimeInterval = 2,
        staleAfter: TimeInterval = 8
    ) {
        self.profile = profile
        self.stateStore = stateStore ?? profile.stateURL
        self.desktopStore = desktopStore ?? profile.desktopStoreURL
        self.interval = interval
        self.staleAfter = staleAfter
    }

    func start() {
        rescan()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rescan() {
        let found = Self.read(stateStore: stateStore, desktopStore: desktopStore,
                              staleAfter: staleAfter, profile: profile)
        guard found != sessions else { return }
        sessions = found
    }

    static func read(stateStore: URL, desktopStore: URL,
                     staleAfter: TimeInterval, now: Date = Date(),
                     profile: CodexProfile = .default()) -> [AgentSession] {
        // Both surfaces, because "Codex" is two programs that record their work
        // in different places: the CLI and the VS Code extension append to a
        // rollout, and the desktop app writes to its own catalogue. Whichever
        // moved last is the one that is working.
        var candidates: [(id: String, name: String, at: Date, state: AgentSession.State)] = []

        if let rollout = CodexStore.newestRollout(in: stateStore),
           let modified = (try? FileManager.default
               .attributesOfItem(atPath: rollout.path))?[.modificationDate] as? Date {
            let state: AgentSession.State
            switch CodexRolloutActivity.state(from: rollout) {
            case .success: state = .success
            case .busy, .none: state = .busy
            }
            candidates.append((id: "\(profile.id).\(rollout.lastPathComponent)",
                               name: profile.displayName, at: modified, state: state))
        }
        if let desktop = CodexStore.newestDesktopThread(in: desktopStore) {
            candidates.append((id: "\(profile.id).desktop", name: desktop.title,
                               at: desktop.updatedAt, state: .busy))
        }

        guard let newest = candidates.max(by: { $0.at < $1.at }),
              let session = session(id: newest.id, name: newest.name,
                                    modified: newest.at, state: newest.state,
                                    staleAfter: staleAfter, now: now)
        else { return [] }
        return [session]
    }

    /// Only work recorded within the window counts. Anything older is a
    /// finished turn, and reporting it as work in progress would be a guess
    /// dressed as a fact.
    static func session(
        id: String, name: String, modified: Date,
        state: AgentSession.State = .busy,
        staleAfter: TimeInterval, now: Date
    ) -> AgentSession? {
        guard now.timeIntervalSince(modified) <= staleAfter else { return nil }

        return AgentSession(
            id: id,
            name: name,
            detail: state == .success ? L10n.t("Complete") : L10n.t("Working"),
            state: state,
            waitingFor: nil,
            since: modified
        )
    }
}
