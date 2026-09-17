import Foundation

/// A notch size, as one of three named ones.
///
/// A shortcut, not a second control: choosing one moves the size slider
/// (`Preferences.customNotchScale`), which is what the drawn size follows. The
/// three exist because most people want a decision made for them; the slider
/// exists because the useful range is narrow enough to be worth aiming at
/// directly — below about three quarters the percentage under each ring stops
/// being readable at a glance, which is the one thing the notch exists to do,
/// and much above a quarter larger a stack of five providers competes with the
/// windows it sits beside rather than reporting on them.
///
/// The scale multiplies the whole surface — rings, text, tooltip and all — so
/// the proportions stay exactly as they were drawn. `NotchLayout` keeps every
/// constant it quotes from the design frame, and `medium` is that frame at 1:1.
enum NotchSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// What every measured distance is multiplied by. `medium` is 1, so it is
    /// the design frame untouched and the behaviour every earlier version had.
    var scale: CGFloat {
        switch self {
        case .small:  return 0.8
        case .medium: return 1
        case .large:  return 1.25
        }
    }

    var title: String {
        switch self {
        case .small:  return L10n.t("Small")
        case .medium: return L10n.t("Medium")
        case .large:  return L10n.t("Large")
        }
    }
}
