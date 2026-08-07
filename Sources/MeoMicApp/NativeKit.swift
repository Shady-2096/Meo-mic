import AppKit
import SwiftUI

enum Metrics {
    /// Narrow on purpose. The window is glanced at beside a call app, so it is
    /// sized to sit in a corner rather than to fill the space a settings window
    /// would take.
    static let window: CGFloat = 360
    static let gutter: CGFloat = 20
    /// Clears the traffic lights, which float over the content once the title
    /// bar is hidden.
    static let topInset: CGFloat = 40
    static let groupRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6
}

/// Real behind-window vibrancy.
///
/// SwiftUI's `.regularMaterial` blurs what is inside the window; this blurs
/// what is behind it, which is the difference between a grey rectangle and a
/// Mac window. `.underWindowBackground` is the material AppKit provides for
/// exactly this — a full-window ground under a hidden title bar.
struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// An inset grouped container, the shape macOS uses for settings rows. The
/// only box in the window — one card, and everything else breathes on the
/// ground.
struct Group_<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
                    .fill(Palette.groupFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
                    .strokeBorder(Palette.groupStroke, lineWidth: 1)
            }
    }
}

/// A settings row: label on the left, control on the right, the way every
/// native Mac form is laid out.
struct Row<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.rowLabel)
                .foregroundStyle(Palette.label)

            Spacer(minLength: 8)

            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// Separators in a grouped list start at the content's leading edge, not at
/// the card's — the detail that makes a stack of rows read as one list.
struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

/// A small borderless symbol button, as used in a Mac toolbar or an inline
/// field affordance.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(hovering ? Palette.controlFillHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// An inline advisory. Native apps say this in a line with a symbol, not in a
/// coloured banner and never in a modal.
struct InlineNote: View {
    let symbol: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
