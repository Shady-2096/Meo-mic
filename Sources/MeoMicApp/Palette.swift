import AppKit
import SwiftUI

/// Platform colours, not brand colours.
///
/// Everything here resolves through AppKit's semantic colours or through
/// `primary`, so the window follows the system appearance without a second
/// palette to maintain. That is the point: a hand-rolled dark-only palette is
/// the most reliable tell that an app is not really a Mac app, and no custom
/// hex can track the user's accent colour, increased-contrast setting, or
/// wallpaper tinting the way these do.
enum Palette {
    // MARK: Type

    static let label = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: Surfaces

    /// Inset group fill, sitting on the window's material. Deliberately an
    /// opacity on `primary` rather than a named surface colour: it stays
    /// translucent over the vibrancy behind it, which is what keeps the card
    /// from looking like a flat rectangle pasted onto a blurred window.
    static let groupFill = Color.primary.opacity(0.045)
    static let groupStroke = Color.primary.opacity(0.09)
    static let separator = Color.primary.opacity(0.08)
    static let controlFill = Color.primary.opacity(0.06)
    static let controlFillHover = Color.primary.opacity(0.11)

    // MARK: State

    /// The user's own accent colour, which is the native way to say "this is
    /// the live, current, selected thing".
    static let accent = Color.accentColor
    static let live = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
}

/// Native text styles, not fixed point sizes.
///
/// These track the user's sidebar/text-size setting and stay optically correct
/// at every appearance, which fixed sizes do not.
extension Font {
    /// The one status line the window is built around.
    static let statusTitle = Font.system(.title2, design: .default, weight: .semibold)
    /// The address while waiting, set for glancing at across a desk.
    static let address = Font.system(.title3, design: .default, weight: .medium)
    static let rowLabel = Font.system(.body)
    static let supporting = Font.system(.subheadline)
    static let caption = Font.system(.caption)
}
