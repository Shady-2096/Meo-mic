import SwiftUI

/// Catppuccin Mocha, addressed by role rather than by colour name.
///
/// The rule the interface is built on: chrome is achromatic, and saturated
/// colour only appears where something is happening. An idle window is grey.
enum Palette {
    static let window = Color(hex: 0x11111B)
    static let card = Color(hex: 0x1E1E2E)
    static let cardHover = Color(hex: 0x313244)
    static let control = Color(hex: 0x313244)
    static let border = Color(hex: 0x282839)

    static let text = Color(hex: 0xCDD6F4)
    static let textSecondary = Color(hex: 0xA6ADC8)
    /// Catppuccin Overlay2, not Overlay0. Labels and captions are set at 11.5pt,
    /// and Overlay0 measures 3.4:1 against the card — under AA for small text.
    static let textTertiary = Color(hex: 0x9399B2)

    /// Primary action, focus, brand mark. Never a status colour.
    static let accent = Color(hex: 0xCBA6F7)

    static let live = Color(hex: 0xA6E3A1)
    static let warn = Color(hex: 0xF9E2AF)
    static let hot = Color(hex: 0xFAB387)
    static let error = Color(hex: 0xF38BA8)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

/// The type scale: the system face, four steps, sentence case.
/// No display face and no monospace — this is a utility window, not an
/// instrument. Numbers that change in place get `.monospacedDigit()` instead.
extension Font {
    /// The one status sentence. The largest thing on screen.
    static let status = Font.system(size: 22, weight: .semibold)
    /// Card titles and the app name.
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    /// Supporting sentences and control text.
    static let uiBody = Font.system(size: 13)
    /// Field labels, captions, footer.
    static let uiLabel = Font.system(size: 11.5, weight: .medium)
}
