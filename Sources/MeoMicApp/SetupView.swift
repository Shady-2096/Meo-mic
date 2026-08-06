import AppKit
import MeoMicCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: AppModel
    @StateObject private var setup = SetupModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Text("macOS has no built-in way for an app to appear as a microphone, so Meo Mic needs a virtual audio device to carry your phone’s voice into Discord, Zoom, Meet, or OBS.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            stepsCard
                .padding(.vertical, 20)

            statusArea

            actions
                .padding(.top, 18)

            manualSteps
        }
        .padding(28)
        .frame(width: 510)
        .background(Palette.crust)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("AUDIO ROUTE")
                Text("Give calls somewhere to listen")
                    .font(.panel(24, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button {
                setup.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.overlay)
            .accessibilityLabel("Close")
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SetupStep(
                number: "1",
                title: "Meo Mic downloads BlackHole 2ch",
                detail: "Straight from existential.audio. Nothing is bundled or repackaged."
            )
            SetupStep(
                number: "2",
                title: "macOS checks it and asks your permission",
                detail: "Meo Mic verifies Apple’s signature first, then Existential Audio’s own installer asks for your administrator password. Meo Mic never sees it."
            )
            SetupStep(
                number: "3",
                title: "Pick BlackHole as your mic",
                detail: "Meo Mic selects it here automatically. Choose “BlackHole 2ch” inside your call app."
            )
        }
        .padding(18)
        .background(Palette.base)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.surface0.opacity(0.7), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch setup.phase {
        case .idle:
            EmptyView()

        case let .working(message, fraction):
            VStack(alignment: .leading, spacing: 8) {
                if let fraction {
                    ProgressView(value: fraction)
                        .tint(Palette.mauve)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Palette.mauve)
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtext)
            }

        case let .failed(message, _):
            Notice(icon: "exclamationmark.triangle.fill", tint: Palette.red, text: message)

        case let .finished(deviceName):
            Notice(
                icon: "checkmark.circle.fill",
                tint: Palette.green,
                text: "\(deviceName) is installed and selected."
            )
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch setup.phase {
            case .idle:
                Button("Install BlackHole") { startInstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.mauve)
                    .foregroundStyle(Palette.crust)

            case .working:
                Button("Cancel") { setup.cancel() }
                    .buttonStyle(.bordered)

            case let .failed(_, canRetry):
                if canRetry {
                    Button("Try again") { startInstall() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.mauve)
                        .foregroundStyle(Palette.crust)
                }

            case .finished:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.mauve)
                    .foregroundStyle(Palette.crust)
            }

            if !setup.isWorking {
                Button("Re-check") {
                    model.refreshDevices()
                    if model.hasVirtualDevice { dismiss() }
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private var manualSteps: some View {
        DisclosureGroup(isExpanded: $setup.showsManualSteps) {
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Download BlackHole 2ch from existential.audio.\n2. Open the downloaded .pkg and follow the installer.\n3. Come back here and press Re-check.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open BlackHole website") {
                    NSWorkspace.shared.open(BlackHoleInstaller.downloadPageURL)
                }
                .buttonStyle(.bordered)

                Text("BlackHole is free, open-source software by Existential Audio. Meo Mic does not bundle or modify it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.overlay)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Install manually instead")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.subtext)
        }
        .tint(Palette.overlay)
        .padding(.top, 20)
    }

    private func startInstall() {
        setup.install {
            model.refreshDevices()
        }
    }
}

private struct Notice: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
