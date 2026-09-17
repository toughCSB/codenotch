import Foundation

/// How long a limit window lasts, as the question a user actually asks.
///
/// A provider's windows are named and numbered by the vendor — `primary`,
/// `secondary`, `weekly_all`, `rolling`, `gemini-hourly` — and nobody thinks in
/// those. "Show me the weekly one" is the same request everywhere, and this is
/// that request, whatever the provider called it.
///
/// It began as Antigravity's own setting, which is why the raw values are
/// spellings of durations rather than numbers: they are what is already written
/// in the preferences of everyone who chose one.
enum RingCadence: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case fiveHour = "5h"
    case weekly = "weekly"
    case monthly = "monthly"
    
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return L10n.t("Default")
        case .fiveHour: return L10n.t("5-Hour Limit")
        case .weekly: return L10n.t("Weekly Limit")
        case .monthly: return L10n.t("Monthly Limit")
        }
    }

    var explanation: String { title }

    /// The card's own button face.
    ///
    /// An abbreviation rather than the settings row's full name — "Weekly
    /// Limit", "5-Hour Limit" — because four of them share one line of a card
    /// 226pt wide. The default is named rather than abbreviated: it is the one
    /// choice here that is not a duration.
    var shortTitle: String {
        switch self {
        case .automatic: return L10n.t("Default")
        case .fiveHour:  return L10n.t("5h")
        case .weekly:    return L10n.t("Weekly")
        case .monthly:   return L10n.t("Monthly")
        }
    }
}

extension RingCadence {
    /// Whether a window that states its own length is this cadence.
    ///
    /// Bands rather than exact values, and adjacent ones, so nothing can match
    /// two: a vendor rounds (Antigravity's session comes back as 18 000 seconds,
    /// a month as thirty or thirty-one days) and an equality test would miss it,
    /// while a tolerance wide enough to catch both would start overlapping.
    /// Nothing longer than ten days is a week, and nothing shorter than six
    /// hours is a month.
    func covers(_ duration: TimeInterval) -> Bool {
        switch self {
        case .automatic: return false
        case .fiveHour:  return duration > 0 && duration <= 6 * 3600
        case .weekly:    return duration > 6 * 3600 && duration <= 10 * 86400
        case .monthly:   return duration > 10 * 86400
        }
    }

    /// Whether a window's own name or label is this cadence.
    ///
    /// The fallback for providers that publish no duration at all. Deliberately
    /// literal: these are the words the vendors themselves use, including the
    /// two that name a cadence by convention rather than by length — a rolling
    /// session and a Codex `primary` are both the short window.
    func names(_ id: String, _ label: String) -> Bool {
        let value = "\(id) \(label)".lowercased()
        switch self {
        case .automatic:
            return false
        case .fiveHour:
            return ["5h", "5-hour", "5 hour", "five hour", "hourly", "session", "rolling"]
                .contains(where: value.contains)
        case .weekly:
            return value.contains("weekly") || value.contains("week")
        case .monthly:
            return value.contains("monthly") || value.contains("month")
        }
    }
}
