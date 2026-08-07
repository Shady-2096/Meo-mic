import SwiftUI

/// The only drawn element in the window, and the thing that makes it feel
/// alive rather than reported-on.
///
/// It replaced a level bar, which replaced a segmented dBFS meter. A bar tells
/// you the present instant and nothing else; this keeps the last two seconds
/// on screen, mirrored around the centre line the way every voice interface on
/// the platform draws sound. Nobody has to read it — a flat line means silence
/// and a moving one means your voice is arriving, which is the entire question
/// the app exists to answer.
struct Waveform: View {
    /// Newest sample last, each already normalised to 0...1 by the model.
    let samples: [Double]
    let isLive: Bool
    let isHot: Bool

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2
    private let height: CGFloat = 36

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(samples.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint)
                    // Older samples fade toward the left, so the newest edge
                    // reads as the present without needing a playhead.
                    .opacity(0.35 + 0.65 * (Double(index) / Double(max(samples.count - 1, 1))))
                    .frame(width: barWidth, height: barHeight(samples[index]))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(.linear(duration: 0.07), value: samples)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(caption)
    }

    /// A floor of 2pt so silence is a hairline through the middle rather than
    /// an empty rectangle — the resting state should still look like an
    /// instrument that is switched on.
    private func barHeight(_ sample: Double) -> CGFloat {
        max(2, CGFloat(sample) * height)
    }

    private var tint: Color {
        guard isLive else { return Palette.tertiary }
        return isHot ? Palette.warning : Palette.accent
    }

    var caption: String {
        guard isLive else { return "No sound yet" }
        switch levelDB {
        case ..<(-50): return "Very quiet — say something"
        case ..<(-30): return "A little quiet"
        case ..<(-6): return "Sounds good"
        case ..<(-3): return "Getting loud"
        default: return "Too loud — turn it down on your phone"
        }
    }

    var captionColor: Color {
        isLive && levelDB >= -3 ? Palette.warning : Palette.secondary
    }

    /// The newest sample, back in dBFS, for the caption thresholds.
    private var levelDB: Double {
        guard let newest = samples.last else { return -60 }
        return newest * 60 - 60
    }
}
