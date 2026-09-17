import Foundation

/// Which of a provider's windows the ring means, once the user has had a say.
///
/// The provider declares one (`ProviderSnapshot.declaredHeadlineID`), because
/// it is the only thing that knows what its own windows are called. This is the
/// user's question on top of that declaration — "show me the weekly one" — and
/// it has to be answered from the windows themselves, since every provider
/// names and measures its own differently.
enum HeadlineWindow {
    /// The window to draw, given what the provider declared and what the user
    /// asked for. Returns the declaration when the cadence is `automatic`, or
    /// when nothing in the response answers it.
    ///
    /// Never invents a window. A provider whose weekly window has dropped out of
    /// the response shows its declared window and nothing else — the ring keeps
    /// its subject rather than being handed a different limit wearing the same
    /// position in the stack.
    static func resolve(windows: [LimitWindow], declared: String?, weeklyID: String?,
                        cadence: RingCadence) -> String? {
        guard cadence != .automatic else { return declared }
        return matching(windows, cadence: cadence, weeklyID: weeklyID)?.id ?? declared
    }

    /// Which cadences these windows can actually answer, in the order
    /// `RingCadence` lists them, and never `automatic` — that is always on
    /// offer, and the caller adds it. What the settings picker shows: a menu
    /// listing every cadence on a provider with one window only teaches the
    /// user that the setting does nothing.
    static func cadences(in windows: [LimitWindow], weeklyID: String? = nil) -> [RingCadence] {
        RingCadence.allCases.filter {
            $0 != .automatic && matching(windows, cadence: $0, weeklyID: weeklyID) != nil
        }
    }

    /// The window that answers a cadence, when exactly one does.
    ///
    /// The same rule `resolve` applies, exposed for the callers that need the
    /// window itself rather than its id: the hover card's reset summary counts
    /// down to a window, not to a name.
    static func window(answering cadence: RingCadence, in windows: [LimitWindow],
                       weeklyID: String? = nil) -> LimitWindow? {
        matching(windows, cadence: cadence, weeklyID: weeklyID)
    }

    /// The one window that unambiguously answers this cadence, or nil.
    ///
    /// Two rules, tried in order, and neither of them guesses. Exact durations
    /// first, because a window that states its own length has said what it is:
    /// Claude files its session as five hours and its weeklies as seven days, and
    /// no wording in between can disagree. Only then the words, and only for the
    /// windows that published no length at all — a window that says it lasts a
    /// month is not a week however it is labelled, and reading one as the other
    /// is how a ring ends up reporting the wrong limit.
    ///
    /// Ambiguity is not resolved by picking one. Claude has three weekly
    /// windows — all models, Opus, Sonnet — and choosing between them by name
    /// would be this rule deciding something the provider already answered:
    /// `weeklyID` names the one the second ring draws, so that is the one
    /// "weekly" means. With no such name to fall back on, the honest answer is
    /// to leave the provider's own choice alone.
    private static func matching(_ windows: [LimitWindow], cadence: RingCadence,
                                weeklyID: String?) -> LimitWindow? {
        let byDuration = windows.filter { window in
            guard let duration = window.duration else { return false }
            return cadence.covers(duration)
        }
        let candidates = byDuration.isEmpty
            ? windows.filter { $0.duration == nil && cadence.names($0.id, $0.label) }
            : byDuration
        if candidates.count == 1 { return candidates.first }
        guard candidates.count > 1, let weeklyID else { return nil }
        return candidates.first { $0.id == weeklyID }
    }
}
