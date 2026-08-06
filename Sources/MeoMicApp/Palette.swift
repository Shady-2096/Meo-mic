import SwiftUI

enum Palette {
    static let crust = Color(hex: 0x11111B)
    static let mantle = Color(hex: 0x181825)
    static let base = Color(hex: 0x1E1E2E)
    static let surface0 = Color(hex: 0x313244)
    static let surface1 = Color(hex: 0x45475A)
    static let surface2 = Color(hex: 0x585B70)
    static let text = Color(hex: 0xCDD6F4)
    static let subtext = Color(hex: 0xA6ADC8)
    static let overlay = Color(hex: 0x6C7086)
    static let mauve = Color(hex: 0xCBA6F7)
    static let green = Color(hex: 0xA6E3A1)
    static let yellow = Color(hex: 0xF9E2AF)
    static let peach = Color(hex: 0xFAB387)
    static let red = Color(hex: 0xF38BA8)
    static let line = Color(hex: 0x282839)
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

extension Font {
    static func panel(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).width(.condensed)
    }

    static func data(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
