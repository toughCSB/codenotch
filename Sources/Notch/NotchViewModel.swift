import SwiftUI
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var snapshots: [ProviderSnapshot] = []
    /// Per runtime, so Ollama's relay switching off clears its own readings
    /// and nobody else's.
    private var performances: [String: [String: LocalModelPerformance]] = [:]
    private var ledger = LocalTokenLedger()
    private var localMetricsEnabled = false

    /// The Ollama relay's own id; its readings are keyed by model name.
    static let ollamaSource = "ollama-local"

    func setLocalMetricsEnabled(_ enabled: Bool) {
        localMetricsEnabled = enabled
        if !enabled { performances[Self.ollamaSource] = nil; thinkingModels = [:] }
        snapshots = snapshots.map(decorated)
    }

    func updateSnapshots(_ providerSnapshots: [ProviderSnapshot]) {
        let hoveredID = hoveredSnapshot?.id
        let next = ProviderOrder.cells(from: providerSnapshots, keeping: snapshots).map(decorated)
        let nextHoveredIndex = hoveredID.flatMap { id in next.firstIndex { $0.id == id } }
        if hoveredIndex != nextHoveredIndex { hoveredIndex = nextHoveredIndex }
        snapshots = next
    }

    func updatePerformances(_ measurements: [String: LocalModelPerformance],
                            source: String = NotchViewModel.ollamaSource) {
        performances[source] = measurements
        snapshots = snapshots.map(decorated)
    }

    /// Logged tokens per cell, read against `now` as it is drawn so "today"
    /// rolls over at midnight without a new line being written.
    func updateLedger(_ ledger: LocalTokenLedger) {
        self.ledger = ledger
        snapshots = snapshots.map(decorated)
    }

    private func decorated(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard let model = snapshot.localModel else { return snapshot }
        var snapshot = snapshot
        let shows = localMetricsEnabled || snapshot.localRuntimeMeasuresSpeed
        snapshot.showsLocalPerformance = shows
        snapshot.localPerformance = shows
            ? performances[snapshot.providerID]?[Self.performanceKey(for: snapshot, model: model)] : nil
        snapshot.localLedger = ledger.summary(for: snapshot.id, now: now)
        snapshot.localContextFraction = snapshot.localLedger?.contextFraction(contextLength: model.contextLength)
        return snapshot
    }

    /// Ollama's relay knows a model by the name a client used, with Ollama's
    /// implicit `:latest`; everything else reports by notch cell id.
    static func performanceKey(for snapshot: ProviderSnapshot, model: LocalRuntimeReading.Model) -> String {
        snapshot.providerID == ollamaSource ? OllamaThinkingStream.modelKey(model.name) : snapshot.id
    }

    @Published var thinkingModels: [String: Date] = [:]
    /// What each local model instance is doing, keyed by cell id. Ollama's
    /// thinking relay reports through `thinkingModels`; LM Studio's state
    /// poll reports here, phase and queue included.
    @Published var localActivities: [String: LocalModelActivity] = [:]

    /// Live agent sessions, keyed by the provider they belong to. They surface
    /// inside that provider's own ring rather than as a cell of their own — one
    /// ring per provider, so nothing in the notch looks like a ring without
    /// being one.
    @Published var sessions: [String: [AgentSession]] = [:]

    /// Which cell the cursor is over, if any. Driven from the window controller
    /// rather than SwiftUI's `.onHover`: the panel ignores mouse events until
    /// the cursor is over it, so SwiftUI cannot see the crossing that turns
    /// event handling on in the first place.
    @Published var hoveredIndex: Int?
    /// Ticked on refresh so the "Resets in N min" copy stays honest.
    @Published var now: Date = Date()
    @Published var resetTimeFormat: ResetTimeFormat = .automatic

    /// Active usage reset notification event to present beside the notch.
    @Published var activeResetAlert: UsageResetEvent?

    func resetAlertIndex(for event: UsageResetEvent) -> Int? {
        snapshots.firstIndex { $0.id == event.providerID }
    }

    /// Whether the notch is open or folded away to its pill.
    @Published var isExpanded = false
    /// Clicked open, so it stays open until clicked shut again. A gesture,
    /// not a setting: it lasts as long as this session of looking at it.
    @Published var isPinned = false

    /// The standing choice from Settings — "Always show".
    ///
    /// Separate from `isPinned` because the two are not the same claim, and
    /// sharing one flag is what let a click on the bar undo a setting. Clicking
    /// toggles a pin; only Settings moves this.
    @Published var isAlwaysOn = false

    /// Held open, by either route. What the folding logic actually asks.
    var staysOpen: Bool { isPinned || isAlwaysOn }
    /// Providers with a fetch in flight, driven by the store.
    @Published var refreshing: Set<String> = []
    @Published private(set) var refreshingCells: Set<String> = []

    func isRefreshing(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.localModel == nil
            ? refreshing.contains(snapshot.providerID)
            : refreshingCells.contains(snapshot.id)
    }

    func refresh(_ snapshot: ProviderSnapshot, using refreshProvider: (String) async -> Void) async {
        guard snapshot.localModel != nil else {
            await refreshProvider(snapshot.providerID)
            return
        }
        guard refreshingCells.insert(snapshot.id).inserted else { return }
        defer { refreshingCells.remove(snapshot.id) }
        // A shared inventory fetch is not activity in every loaded model.
        // Only the clicked cell presses in, even when it joins an existing poll.
        async let feedback: Void = Task.sleep(nanoseconds: 380_000_000)
        await refreshProvider(snapshot.providerID)
        _ = try? await feedback
    }
    /// A tap on a session row in the tooltip: jump to the terminal tab the
    /// session runs in. Takes the session's pid; wired to `SessionFocus`.
    var onFocusSession: ((pid_t) -> Void)?
    /// A tap on one of the hover card's cadence buttons: re-point a provider's
    /// ring at another of its own limits. Persisting it is `Preferences`' job,
    /// exactly as it is for the Settings row offering the same choice.
    var onSetRingCadence: ((String, RingCadence) -> Void)?
    /// Which screen edge the notch is welded to. Everything geometric reads
    /// this through `placement` rather than assuming an axis.
    @Published var edge: NotchEdge = .right
    /// A user-chosen nudge along that edge, in screen points from the centred
    /// default — set live while ⌥-dragging the pill, and by
    /// `NotchGeometry.panelFrame` from there. Reset to whatever was stored for
    /// the new edge whenever `edge` changes; this type does not own that
    /// persistence, only the live value.
    @Published var alongOffset: CGFloat = 0
    /// What every measured distance is multiplied by before it reaches the
    /// screen — the Appearance size choice, as a number.
    ///
    /// Everything in this type stays in **unscaled** points, the size the
    /// design frame is drawn at, and so does `NotchLayout`. Scaling at the
    /// source would mean threading a factor through forty constants and
    /// leaving each one no longer comparable to the frame it is quoted from.
    /// The multiplication happens once, at the two places that touch the
    /// screen: the panel's frame and the drawn content.
    @Published var sizeScale: CGFloat = 1
    /// Mirrors the persisted Appearance choice so the separate notch window
    /// redraws immediately when Settings changes it.
    @Published var accentColor: AccentColorChoice = .system
    /// Whether a provider's weekly limit gets a ring of its own, and where.
    /// Mirrored here for the same reason `accentColor` is: the notch is a
    /// separate window, and it has to redraw the moment Settings changes this.
    @Published var weeklyRing: WeeklyRing = .off
    @Published var weeklyRingDashed: Bool = false
    @Published var watchLimit: Double = 0.50
    @Published var criticalLimit: Double = 0.70
    /// Mirrors the persisted Appearance choice so the separate notch window
    /// redraws immediately when Settings changes it.
    @Published var surfaceStyle: NotchSurfaceStyle = .glass
    /// Whether the panel floats above other applications' windows. Mirrored
    /// from `Preferences.notchAlwaysOnTop`; the controller puts it on the
    /// panel's own level.
    @Published var isAlwaysOnTop = true
    /// Which half of a used-fraction the number under each ring reports.
    /// Mirrored from `Preferences.percentBasis` so the menu can show which one
    /// is on; the rings themselves read it off their snapshots.
    @Published var percentBasis: Percent.Basis = .remaining
    /// Whether DeepSeek's billing phase rows are visible in its usage card.
    @Published var deepSeekPricingEnabled = true
    /// The rule used by the DeepSeek card, mirrored from Preferences so a
    /// settings change is reflected in every notch immediately.
    @Published var deepSeekPricingSchedule = DeepSeekPricing.Schedule.current
    /// The display's own notch, when this edge has to share the bezel with one.
    ///
    /// Set by the window controller from the screen the panel is on, because
    /// that is the only thing that knows which screen that is.
    @Published var hardwareNotch: HardwareNotch?

    /// How much screen there is to spend on the panel.
    ///
    /// The tooltip's budget comes out of this: how many sessions a card can
    /// list before the panel holding it would run off the display. Zero until
    /// the controller says otherwise, which reads as "no screen known yet".
    @Published var screenSize: CGSize = .zero

    /// Visible slice of the panel along its edge, in local stack coordinates.
    @Published var visibleAlongRange: ClosedRange<CGFloat>?

    func tooltipAlong(index: Int, length: CGFloat) -> CGFloat {
        let centre = slack + ringCenter(index: index) * sizeScale
        guard let range = visibleAlongRange else { return centre }
        let lower = range.lowerBound + length / 2
        let upper = range.upperBound - length / 2
        guard lower <= upper else { return (range.lowerBound + range.upperBound) / 2 }
        return min(max(centre, lower), upper)
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Language change leaves snapshots untouched; tick `now` so copy
        // already on screen is redrawn against the new catalog.
        NotificationCenter.default.publisher(for: L10n.didChange)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.now = Date() }
            }
            .store(in: &cancellables)
    }

    /// Take the notch geometry of whichever screen the panel is on.
    func adopt(screen: ScreenDescribing) {
        let merging = edge == .top ? screen.hardwareNotch : nil
        if hardwareNotch != merging { hardwareNotch = merging }
        // `frame`, not `visibleFrame`: the panel is centred on the full screen
        // and may sit under the menu bar, so the menu bar is not room lost.
        let size = screen.frameValue.size
        if screenSize != size { screenSize = size }
    }

    /// How far in from the bezel the notch's contents start.
    ///
    /// Zero everywhere except a top notch merging with the display's own. There
    /// the shape runs up past the menu bar to meet the hardware, and that top
    /// band is a **hole in the screen** — anything drawn in it is not dimmed or
    /// clipped, it is simply not there. So the readings start below it.
    /// Exactly the hardware's height, and nothing on top of it: the readings
    /// then sit the frame's own `ringMargin` below the hardware's bottom edge,
    /// which is the same distance a ring sits from the bezel on every other
    /// placement. Adding a gap as well pads them twice and leaves them adrift
    /// of the notch they are supposed to belong to.
    var contentInset: CGFloat { hardwareNotch?.height ?? 0 }

    /// How much of each end of the bar the flare actually takes.
    var flare: CGFloat {
        isFlushWithHardware ? NotchLayout.bezelFillet : NotchLayout.curlRadius
    }

    /// Whether the shape is drawn the way the Mac's own notch is — flush to
    /// the bezel, no flares — so the two are one object rather than two.
    var isFlushWithHardware: Bool { hardwareNotch != nil }

    /// The hardware notch as the *shape* needs it, which is only where one is
    /// being drawn as.
    var joinedNotch: HardwareNotch? { hardwareNotch }

    /// The corner the shape actually draws at its far end.
    ///
    /// Not always `cornerRadius`: a bar drawn as the hardware notch caps it at
    /// the hardware's own rounding, so that the shape is the same at rest as it
    /// is open.
    var drawnCornerRadius: CGFloat {
        guard let hardwareNotch else { return NotchLayout.cornerRadius }
        return min(NotchLayout.cornerRadius, hardwareNotch.height / 2)
    }

    /// Extra length at each end of the body so the notch has something to open
    /// out *into*.
    ///
    /// A single ring makes a body about 117pt across; this Mac's notch is 220.
    /// Left alone the hardware would be wider than the bar it is supposed to
    /// grow into, which reads as a mistake. Matching it exactly is not enough
    /// either — a bar the same width as the notch is a straight column, and the
    /// notch appears not to have opened at all. So the floor is the notch plus
    /// a fillet's worth of opening at each side, and a corner's worth beyond
    /// that for the bar's own rounding to live in.
    var endSpread: CGFloat { endSpread(cellCount: snapshots.count) }

    func endSpread(cellCount: Int) -> CGFloat {
        guard let hardwareNotch else { return 0 }
        // Expressed against the whole shape, not just its body: with no flares
        // the drawn width *is* the shape's length, and that is what has to
        // clear the hardware.
        let drawn = NotchLayout.shapeLength(
            cellCount: cellCount, edge: edge, flare: flare
        )
        let wanted = hardwareNotch.width + 2 * NotchLayout.cornerRadius
        return max(0, (wanted - drawn) / 2)
    }

    /// Where the tooltip's tail tip sits, measured in from the bezel: just off
    /// the inner face of a shape that the extension has made deeper.
    var tooltipInset: CGFloat {
        notchDrawnDepth + NotchLayout.tailGap
    }

    /// How deep the notch body reaches on screen — the design-frame depth at
    /// the size it is actually drawn.
    ///
    /// Where the notch ends is where the tooltip begins, and the tooltip is not
    /// drawn at that size, so this is the seam between the two spaces rather
    /// than a measurement either of them owns.
    var notchDrawnDepth: CGFloat {
        (contentInset + NotchLayout.bodyDepth(for: edge)) * sizeScale
    }

    /// The straight part of the shape, flares excluded.
    var bodyLength: CGFloat {
        NotchLayout.bodyLength(
            cellCount: snapshots.count, edge: edge, spacing: cellSpacing
        ) + 2 * endSpread
    }

    /// Distance along the stack to cell `index`'s ring centre, widening
    /// included so the readings stay in the middle of the bar.
    func ringCenter(index: Int) -> CGFloat {
        NotchLayout.ringCenter(index: index, edge: edge, flare: flare,
                              spacing: cellSpacing) + endSpread
    }

    var cellSpacing: CGFloat { cellSpacing(cellCount: snapshots.count) }
    var cellPitch: CGFloat { NotchLayout.cellAlong(for: edge) + cellSpacing }

    private func cellSpacing(cellCount: Int) -> CGFloat {
        guard edge.isVertical, screenSize.height > 0, cellCount > 1 else {
            return NotchLayout.cellSpacing
        }
        // Extra model cells spend the gaps first. Reserve the cards actually
        // present; assuming four quota windows for every local model overflows laptops.
        let slack = NotchLayout.slack(for: edge,
            maxCardHeight: snapshots.isEmpty ? NotchLayout.maxCardHeight(sessionCap: 0)
                : contentCardHeight(sessionCap: 0),
            notchScale: sizeScale)
        let packed = NotchLayout.shapeLength(cellCount: cellCount, edge: edge,
                                             flare: flare, spacing: 0)
        return min(NotchLayout.cellSpacing,
                   max(0, ((screenSize.height - 2 * slack) / sizeScale - packed) / CGFloat(cellCount - 1)))
    }

    /// A provider with no activity source gets none, rather than borrowing
    /// somebody else's.
    func activity(for snapshot: ProviderSnapshot) -> ActivitySummary? {
        guard let model = snapshot.localModel else { return activity(for: snapshot.providerID) }
        if let local = localActivities[snapshot.id] {
            return ActivitySummary(sessions: [AgentSession(id: snapshot.id, name: local.label,
                detail: snapshot.displayName, state: .busy, waitingFor: nil, since: local.since)],
                queued: local.queued, note: local.note)
        }
        guard let since = thinkingModels[OllamaThinkingStream.modelKey(model.name)] else { return nil }
        return ActivitySummary(sessions: [AgentSession(id: snapshot.id, name: L10n.t("Thinking"),
            detail: snapshot.displayName, state: .busy, waitingFor: nil, since: since)])
    }

    func activity(for providerID: String) -> ActivitySummary? {
        ActivitySummary(sessions: sessions[providerID] ?? [])
    }

    var hoveredSnapshot: ProviderSnapshot? {
        guard let hoveredIndex, snapshots.indices.contains(hoveredIndex) else { return nil }
        return snapshots[hoveredIndex]
    }

    var shapeLength: CGFloat { shapeLength(cellCount: snapshots.count) }

    var panelSize: CGSize { panelSize(cellCount: snapshots.count) }

    /// How stack space maps onto the panel right now.
    var placement: NotchPlacement { NotchPlacement(edge: edge, panelSize: panelSize) }

    /// Room at each end of the stack, for this edge.
    var slack: CGFloat { slack(cellCount: snapshots.count) }

    func slack(cellCount: Int) -> CGFloat {
        let wanted = NotchLayout.slack(for: edge,
                                       maxCardHeight: maxCardHeight(cellCount: cellCount),
                                       notchScale: sizeScale)
        // The panel is the notch plus this padding at each end, so a display
        // too short for the tallest card has to take the padding out of the
        // padding rather than push the notch off the screen. The notch is what
        // the panel exists to draw; a card clamped inwards at the ends of the
        // stack is the degradation this layout already accepts.
        //
        // Both ends give way together, so the notch stays centred and whole.
        // Vertical edges only: there the padding is spent *along* the stack,
        // which is the screen's height, and it is why a long stack of rings on
        // a laptop ran a card's worth of points past the bottom of the display.
        guard edge.isVertical, screenSize.height > 0 else { return wanted }
        let room = (screenSize.height - shapeLength(cellCount: cellCount) * sizeScale) / 2
        return max(0, min(wanted, room))
    }

    /// How many sessions a tooltip may list here before it has to summarise
    /// the rest — as many as this screen has room for.
    var sessionCap: Int { sessionCap(cellCount: snapshots.count) }

    private var hasTokenUsage: Bool {
        snapshots.contains { $0.tokenUsage != nil }
    }

    private var hasPlan: Bool {
        snapshots.contains { $0.plan != nil }
    }

    private var hasResetCredits: Bool {
        snapshots.contains(where: \.hasAvailableResetCredits)
    }

    /// Whether any card in the stack draws the reset summary or the cadence
    /// switch. Both are blocks the card pays for before its first window row,
    /// so the session budget has to know about them — the panel is sized for
    /// the tallest card there is, and a block counted by the card but not by
    /// the budget is a card taller than the panel that holds it.
    private var hasResetSummary: Bool {
        snapshots.contains { !$0.resetSummaryIDs.isEmpty }
    }

    private var hasCadenceSwitch: Bool {
        snapshots.contains { !$0.switchableCadences.isEmpty }
    }

    func sessionCap(cellCount: Int) -> Int {
        guard screenSize != .zero else { return NotchLayout.defaultSessionCap }
        return NotchLayout.sessionsFitting(cardBudget: cardBudget(cellCount: cellCount),
                                           windowCount: NotchLayout.maxWindowCount,
                                           hasTokenUsage: hasTokenUsage,
                                           hasPlan: hasPlan,
                                           hasResetCredits: hasResetCredits,
                                           hasResetSummary: hasResetSummary,
                                           hasCadenceSwitch: hasCadenceSwitch)
    }

    private func contentCardHeight(sessionCap: Int) -> CGFloat {
        snapshots.map { snapshot in
            NotchLayout.cardHeight(windowCount: snapshot.windows.count,
                groupCount: Set(snapshot.windows.compactMap(\.group)).count,
                moneyWindowCount: snapshot.windows.filter { $0.money != nil }.count,
                usageDetailGroupCount: snapshot.usageDetail?.visibleGroups.count ?? 0,
                sessionCount: snapshot.localModel == nil ? sessionCap + 1 : 0,
                sessionCap: sessionCap,
                statusMessage: snapshot.statusMessage,
                blockMessage: snapshot.block?.summary(now: now),
                hasTokenUsage: snapshot.tokenUsage != nil,
                hasPlan: snapshot.plan != nil,
                hasResetCredits: snapshot.hasAvailableResetCredits,
                localModelName: snapshot.localModel?.name,
                showsLocalPerformance: snapshot.showsLocalPerformance,
                localLedgerRows: snapshot.localLedgerRowCount,
                compactRowCount: snapshot.compactRowCount,
                showsDeepSeekPricing: deepSeekPricingEnabled,
                resetSummaryCount: snapshot.resetSummaryIDs.count,
                cadenceOptionCount: snapshot.switchableCadences.count)
        }.max() ?? 0
    }

    func maxCardHeight(cellCount: Int) -> CGFloat {
        let cap = sessionCap(cellCount: cellCount)
        return snapshots.isEmpty
            ? NotchLayout.maxCardHeight(sessionCap: cap, hasTokenUsage: hasTokenUsage, hasPlan: hasPlan,
                                        hasResetCredits: hasResetCredits)
            : contentCardHeight(sessionCap: cap)
    }

    /// How tall the tallest card may be before the panel runs off the screen.
    ///
    /// Which way it runs out differs by orientation, because the card's height
    /// is spent on a different axis: along a side edge it is spent *along* the
    /// stack, half of it past each end, so the stack itself takes its share
    /// first. Along a horizontal edge the card hangs *inward* instead, and what
    /// it competes with is the depth already spent on the notch body and tail.
    /// The screen is measured in real points, and everything it is compared
    /// against here is unscaled. Dividing brings the screen into the same space
    /// rather than scaling the four constants below it: at `large` a card sized
    /// against the raw height would be drawn a quarter taller than it was
    /// budgeted for, and run off the bottom of a small display.
    private func cardBudget(cellCount: Int) -> CGFloat {
        if edge.isVertical {
            return screenSize.height / sizeScale
                - shapeLength(cellCount: cellCount)
                - 2 * NotchLayout.cardCorner
        }
        return screenSize.height / sizeScale
            - contentInset
            - NotchLayout.bodyDepth(for: edge)
            - NotchLayout.tailLength
            - NotchLayout.tailGap
    }

    /// The drawn extent of the notch body right now, along the stack.
    ///
    /// Where it is joining the display's own notch, folding away means becoming
    /// exactly that notch — same width, same height. The resting pill is the
    /// wrong object there: it hangs below the hardware as a separate little
    /// tab, which is the very seam this placement exists to remove. Matching
    /// the hardware instead means nothing shows at rest at all, and reaching
    /// for it makes the notch itself grow.
    var notchLength: CGFloat {
        if isExpanded { return shapeLength }
        return hardwareNotch?.width ?? NotchLayout.pillHeight
    }

    /// And across it.
    var notchDepth: CGFloat {
        if isExpanded { return contentInset + NotchLayout.bodyDepth(for: edge) }
        return hardwareNotch?.height ?? NotchLayout.pillWidth
    }

    /// What the notch folds away to, whether or not it is open right now —
    /// the hit region has to know that while the notch is still open.
    var restingLength: CGFloat { hardwareNotch?.width ?? NotchLayout.pillHeight }
    var restingDepth: CGFloat { hardwareNotch?.height ?? NotchLayout.pillWidth }

    /// What wakes the folded notch, in panel points: the resting shape and a
    /// band around it, or the resting shape alone.
    ///
    /// The band is for the pill. A 10pt sliver on a screen edge is a fiddly
    /// target, and the only cost of surrounding it is that it opens a little
    /// eagerly. Joined to the hardware notch the band is a different matter:
    /// the notch is already a generous target, and a band around it reached
    /// 34pt *below* the menu bar — across the title bar of a window tiled
    /// against the centre of the screen, whose close, minimise and zoom
    /// buttons then opened the notch on approach and disappeared under it.
    /// Flush with the hardware, what wakes the notch is the notch.
    var wakeLength: CGFloat { max(restingLength * sizeScale, wakeBand) }
    var wakeDepth: CGFloat { restingDepth * sizeScale + wakeBand }
    private var wakeBand: CGFloat { isFlushWithHardware ? 0 : NotchLayout.pillHotZone }

    /// The drawn size of the notch body, in panel axes.
    var notchSize: CGSize {
        NotchPlacement.panelSize(edge: edge, length: notchLength, depth: notchDepth)
    }

    /// Where the notch starts along the stack. Both states share a centre line,
    /// so folding away does not slide the notch along the edge as it shrinks.
    var notchLeadingInset: CGFloat {
        slack + (shapeLength - notchLength) / 2
    }

    /// Sized from an explicit count rather than from `snapshots`.
    ///
    /// `@Published` notifies its subscribers in `willSet`, so a sink reacting to
    /// a change in the provider list still sees the *old* array if it reads the
    /// model back. Taking the count as an argument is the only way to be sure
    /// the panel is sized for the list that caused the change.
    func shapeLength(cellCount: Int) -> CGFloat {
        NotchLayout.shapeLength(cellCount: cellCount,
                                edge: edge, flare: flare,
                                spacing: cellSpacing(cellCount: cellCount))
            + 2 * endSpread(cellCount: cellCount)
    }

    /// The panel as it lands on screen, size choice included.
    ///
    /// Two spaces, added rather than multiplied together: the notch is drawn at
    /// `sizeScale`, and the tooltip is drawn at one size whatever the notch is
    /// set to — its text has a legible size of its own, and shrinking the
    /// reading you opened the notch to read is the opposite of the point.
    ///
    /// So the notch's share scales and the card's share does not. Scaling the
    /// whole panel instead left the card cropped at the small end, where the
    /// panel had shrunk around a card that had not.
    func panelSize(cellCount: Int) -> CGSize {
        let card = maxCardHeight(cellCount: cellCount)
        return NotchPlacement.panelSize(
            edge: edge,
            length: shapeLength(cellCount: cellCount) * sizeScale
                + 2 * slack(cellCount: cellCount),
            depth: (contentInset + NotchLayout.bodyDepth(for: edge)) * sizeScale
                + NotchLayout.tooltipDepth(for: edge, maxCardHeight: card)
        )
    }
}
