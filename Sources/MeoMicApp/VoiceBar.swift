import SwiftUI

/// The one piece of custom drawing in the app, and the only thing allowed to
/// carry saturated colour at rest.
///
/// It replaced a segmented, tick-marked dBFS meter. The ballistics behind it
/// are unchanged — instant attack, timed release — because that is what makes
/// a level readable. What changed is that it no longer asks the person using
/// it to read a calibrated scale: one continuous bar, one colour at a time,
/// and a sentence underneath saying what it means.
struct VoiceBar: View {
    /// Current level in dBFS, already smoothed by the model.
    let levelDB: Double
    let isLive: Bool

    private let floorDB = -60.0
    private let height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.card)

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, fraction * geometry.size.width))
                    .animation(.linear(duration: 0.05), value: fraction)
            }
        }
        .frame(height: height)
        .overlay {
            Capsule()
                .stroke(Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(caption)
    }

    private var fraction: CGFloat {
        guard isLive else { return 0 }
        let clamped = max(floorDB, min(0, levelDB))
        return CGFloat((clamped - floorDB) / -floorDB)
    }

    private var fillColor: Color {
        switch levelDB {
        case ..<(-12): Palette.live
        case ..<(-6): Palette.warn
        case ..<(-3): Palette.hot
        default: Palette.error
        }
    }

    /// What the level means, in the words of someone about to join a call.
    var caption: String {
        guard isLive else { return "No sound yet" }
        switch levelDB {
        case ..<(-50): return "Very quiet — say something"
        case ..<(-30): return "A little quiet"
        case ..<(-6): return "Sounds good"
        case ..<(-3): return "Getting loud"
        default: return "Too loud — turn the volume down on your phone"
        }
    }

    var captionColor: Color {
        guard isLive else { return Palette.textTertiary }
        switch levelDB {
        case ..<(-50): return Palette.textTertiary
        case ..<(-3): return Palette.textSecondary
        default: return Palette.hot
        }
    }
}
