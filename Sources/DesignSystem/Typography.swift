import SwiftUI

/// Sizes are derived from cap heights measured in the design frame, so they
/// track `Design.scale` along with everything else.
enum Typography {
    /// The percent under each provider ring. Cap height 27px in the frame.
    static let percent = Font.system(size: Design.fontSize(capPixels: 27), weight: .semibold)

    /// "Claude Usage". Cap height 26px.
    static let cardTitle = Font.system(size: Design.fontSize(capPixels: 26), weight: .semibold)

    /// "Current session", "73% Used", "Resets in 51 min". Cap height 18px.
    static let cardBody = Font.system(size: Design.fontSize(capPixels: 18), weight: .regular)

    /// The reset countdown at the top of a card. Cap height 34px — the card's
    /// own headline figure, deliberately larger than its title, because how
    /// long is left is the reason the card was opened.
    static let hero = Font.system(size: Design.fontSize(capPixels: 34), weight: .bold)

    /// The cadence badge on a ring: M, W or 5h. Cap height 16px, which sits
    /// between the body face and the percent it qualifies.
    static let badge = Font.system(size: Design.fontSize(capPixels: 16), weight: .medium)
}
