import SwiftUI

struct LevelMeter: View {
    let levelDB: Double
    let peakDB: Double

    private let minimumDB = -60.0
    private let segmentCount = 42
    private let ticks = [-60, -48, -36, -24, -12, -6, 0]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                Canvas { context, size in
                    drawSegments(context: &context, size: size)
                    drawPeak(context: &context, size: size)
                }
                .background(Palette.mantle)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Palette.surface0.opacity(0.7), lineWidth: 0.5)
                }
            }
            .frame(height: 42)

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(ticks, id: \.self) { tick in
                        let fraction = CGFloat((Double(tick) - minimumDB) / -minimumDB)
                        Rectangle()
                            .fill(Palette.surface2)
                            .frame(width: 1, height: 4)
                            .position(
                                x: clampedX(fraction * geometry.size.width, width: geometry.size.width),
                                y: 2
                            )
                        Text("\(tick)")
                            .font(.data(9, weight: .medium))
                            .foregroundStyle(Palette.overlay)
                            .position(
                                x: clampedLabelX(
                                    fraction * geometry.size.width,
                                    width: geometry.size.width,
                                    tick: tick
                                ),
                                y: 13
                            )
                    }
                }
            }
            .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(levelDB.rounded())) decibels full scale")
    }

    private func drawSegments(context: inout GraphicsContext, size: CGSize) {
        let gap: CGFloat = 2.5
        let width = (size.width - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount)
        let litCount = Int(
            (((max(minimumDB, min(0, levelDB)) - minimumDB) / -minimumDB) *
             Double(segmentCount)).rounded(.down)
        )

        for index in 0..<segmentCount {
            let segmentDB = minimumDB + (-minimumDB * Double(index + 1) / Double(segmentCount))
            let rect = CGRect(
                x: CGFloat(index) * (width + gap),
                y: 6,
                width: width,
                height: size.height - 12
            )
            let path = Path(roundedRect: rect, cornerRadius: 1.25)
            context.fill(
                path,
                with: .color(index < litCount ? color(for: segmentDB) : Palette.surface0)
            )
        }
    }

    private func drawPeak(context: inout GraphicsContext, size: CGSize) {
        guard peakDB > minimumDB else { return }
        let fraction = CGFloat((min(0, peakDB) - minimumDB) / -minimumDB)
        let x = min(size.width - 2, max(2, fraction * size.width))
        let rect = CGRect(x: x - 1.5, y: 3, width: 3, height: size.height - 6)
        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color(for: peakDB)))
    }

    private func color(for db: Double) -> Color {
        switch db {
        case ..<(-12): Palette.green
        case ..<(-6): Palette.yellow
        case ..<(-3): Palette.peach
        default: Palette.red
        }
    }

    private func clampedX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(width - 0.5, max(0.5, x))
    }

    private func clampedLabelX(_ x: CGFloat, width: CGFloat, tick: Int) -> CGFloat {
        if tick == ticks.first { return 10 }
        if tick == ticks.last { return width - 5 }
        return x
    }
}
