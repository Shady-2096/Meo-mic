import AppKit
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("AUDIO ROUTE")
                    Text("Give calls somewhere to listen")
                        .font(.panel(24, weight: .bold))
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.overlay)
                .accessibilityLabel("Close")
            }

            Text("macOS needs a virtual audio device to carry your phone’s voice into Discord, Zoom, Meet, or OBS.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(number: "1", title: "Install BlackHole 2ch", detail: "Free, open-source virtual audio routing for macOS.")
                SetupStep(number: "2", title: "Return and re-check", detail: "Meo Mic will select it automatically.")
                SetupStep(number: "3", title: "Pick BlackHole as your mic", detail: "Choose “BlackHole 2ch” inside your call app.")
            }
            .padding(18)
            .background(Palette.base)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.surface0.opacity(0.7), lineWidth: 0.5)
            }
            .padding(.vertical, 20)

            HStack {
                Button("Open BlackHole website") {
                    NSWorkspace.shared.open(URL(string: "https://existential.audio/blackhole/")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.mauve)
                .foregroundStyle(Palette.crust)

                Button("Re-check") {
                    model.refreshDevices()
                    if model.hasVirtualDevice {
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(28)
        .frame(width: 510)
        .background(Palette.crust)
        .preferredColorScheme(.dark)
    }
}

private struct SetupStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.data(11, weight: .bold))
                .foregroundStyle(Palette.subtext)
                .frame(width: 28, height: 28)
                .background(Palette.surface0)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.overlay)
            }
        }
    }
}
