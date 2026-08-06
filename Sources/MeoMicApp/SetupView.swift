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
                .font(.uiBody)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            stepsCard
                .padding(.top, 20)

            statusArea
                .padding(.top, 18)

            actions
                .padding(.top, 18)

            manualSteps
        }
        .padding(26)
        .frame(width: 460)
        .background(Palette.window)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Set up your audio route")
                .font(.status)
                .foregroundStyle(Palette.text)
            Spacer()
            Button {
                setup.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textTertiary)
            .accessibilityLabel("Close")
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                detail: "Meo Mic selects it here automatically. Choose it inside your call app."
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
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
                        .tint(Palette.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                }
                Text(message)
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textSecondary)
            }

        case let .failed(message, _):
            Notice(icon: "exclamationmark.triangle.fill", tint: Palette.error, text: message)

        case let .finished(deviceName):
            Notice(
                icon: "checkmark.circle.fill",
                tint: Palette.live,
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
                    .tint(Palette.accent)
                    .foregroundStyle(Palette.window)

            case .working:
                Button("Cancel") { setup.cancel() }
                    .buttonStyle(.bordered)

            case let .failed(_, canRetry):
                if canRetry {
                    Button("Try again") { startInstall() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .foregroundStyle(Palette.window)
                }

            case .finished:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .foregroundStyle(Palette.window)
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
        .controlSize(.large)
    }

    private var manualSteps: some View {
        DisclosureGroup(isExpanded: $setup.showsManualSteps) {
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Download BlackHole 2ch from existential.audio.\n2. Open the downloaded .pkg and follow the installer.\n3. Come back here and press Re-check.")
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open BlackHole website") {
                    NSWorkspace.shared.open(BlackHoleInstaller.downloadPageURL)
                }
                .buttonStyle(.bordered)

                Text("BlackHole is free, open-source software by Existential Audio. Meo Mic does not bundle or modify it.")
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Install manually instead")
                .font(.uiLabel)
                .foregroundStyle(Palette.textSecondary)
        }
        .tint(Palette.textTertiary)
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
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(text)
                .font(.uiLabel)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SetupStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.uiLabel)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(Palette.control)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
