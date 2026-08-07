import AppKit
import MeoMicCore
import SwiftUI

/// The one-time job: install a virtual device so call apps have something to
/// listen to. Shaped as a standard Mac sheet — title, explanation, numbered
/// steps, a confirming button on the trailing edge.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @StateObject private var setup = SetupModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set Up Audio")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(Palette.label)

                Text("macOS has no built-in way for an app to appear as a microphone, so Meo Mic needs a virtual audio device to carry your phone’s voice into Discord, Zoom, Meet, or OBS.")
                    .font(.supporting)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group_ {
                SetupStep(
                    number: 1,
                    title: "Meo Mic downloads BlackHole 2ch",
                    detail: "Straight from existential.audio. Nothing is bundled or repackaged."
                )
                RowSeparator()
                SetupStep(
                    number: 2,
                    title: "macOS checks it and asks your permission",
                    detail: "Meo Mic verifies Apple’s signature first, then Existential Audio’s own installer asks for your administrator password. Meo Mic never sees it."
                )
                RowSeparator()
                SetupStep(
                    number: 3,
                    title: "Pick BlackHole as your mic",
                    detail: "Meo Mic selects it here automatically. Choose it inside your call app."
                )
            }

            statusArea

            manualSteps

            Divider()

            actions
        }
        .padding(20)
        .frame(width: 420)
        .background(WindowMaterial().ignoresSafeArea())
    }

    @ViewBuilder
    private var statusArea: some View {
        switch setup.phase {
        case .idle:
            EmptyView()

        case let .working(message, fraction):
            VStack(alignment: .leading, spacing: 6) {
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }

        case let .failed(message, _):
            InlineNote(
                symbol: "exclamationmark.triangle.fill",
                tint: Palette.error,
                message: message
            )

        case let .finished(deviceName):
            InlineNote(
                symbol: "checkmark.circle.fill",
                tint: Palette.live,
                message: "\(deviceName) is installed and selected."
            )
        }
    }

    private var manualSteps: some View {
        DisclosureGroup(isExpanded: $setup.showsManualSteps) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Download BlackHole 2ch from existential.audio.\n2. Open the downloaded .pkg and follow the installer.\n3. Come back here and press Re-check.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open BlackHole Website") {
                    NSWorkspace.shared.open(BlackHoleInstaller.downloadPageURL)
                }
                .controlSize(.small)

                Text("BlackHole is free, open-source software by Existential Audio. Meo Mic does not bundle or modify it.")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Install manually instead")
                .font(.caption)
                .foregroundStyle(Palette.secondary)
        }
    }

    /// Cancel on the left, the confirming action last on the right — the
    /// arrangement every Mac sheet uses.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if !setup.isWorking {
                Button("Re-check") {
                    model.refreshDevices()
                    if model.hasVirtualDevice { dismiss() }
                }
            }

            Spacer()

            Button("Close") {
                setup.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            switch setup.phase {
            case .idle:
                Button("Install BlackHole") { startInstall() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

            case .working:
                Button("Cancel") { setup.cancel() }

            case let .failed(_, canRetry):
                if canRetry {
                    Button("Try Again") { startInstall() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }

            case .finished:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func startInstall() {
        setup.install {
            model.refreshDevices()
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.controlFill))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
