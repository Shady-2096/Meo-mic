import AppKit
import MeoMicCore
import SwiftUI

/// One column, two shapes.
///
/// Waiting: the status sentence tells you what to do, and the pairing card
/// carries the address, copy and QR. Live: the pairing card gets out of the
/// way and the voice bar carries the window. Everything else — output device,
/// volume — is set once and then ignored, so it sits below both.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            status
                .padding(.top, 26)

            voice
                .padding(.top, 20)

            if !model.isConnected {
                PairingCard(model: model, copied: $copied)
                    .padding(.top, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            outputSection
                .padding(.top, 24)

            volumeSection
                .padding(.top, 20)

            Spacer(minLength: 20)

            footer
                .padding(.bottom, 18)
        }
        .animation(.easeOut(duration: 0.22), value: model.isConnected)
        .padding(.horizontal, 26)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.window)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showsSetup) {
            SetupView(model: model)
        }
        .sheet(isPresented: $model.showsQRCode) {
            QRSheet(model: model)
        }
    }

    // MARK: - Status

    /// The window's whole answer. The state dot rides with the sentence rather
    /// than sitting in a badge of its own — the sentence already says it, and
    /// the app name is already in the title bar.
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(model.isConnected ? Palette.live : Palette.textTertiary)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { _ in 7 }

                Text(model.statusHeadline)
                    .font(.status)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(model.statusDetail)
                .font(.uiBody)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 17)
        }
    }

    // MARK: - Voice

    private var voice: some View {
        let bar = VoiceBar(levelDB: model.displayDB, isLive: model.isConnected)
        return VStack(alignment: .leading, spacing: 9) {
            bar
            Text(bar.caption)
                .font(.uiLabel)
                .foregroundStyle(bar.captionColor)
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Send audio to")
                .font(.uiLabel)
                .foregroundStyle(Palette.textTertiary)

            Picker("Send audio to", selection: Binding(
                get: { model.selectedDeviceUID },
                set: { model.selectDevice(uid: $0) }
            )) {
                Text("Choose a device…").tag(Optional<String>.none)
                ForEach(model.devices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .tint(Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.routeMessage)
                .font(.uiLabel)
                .foregroundStyle(model.routeIsReady ? Palette.textSecondary : Palette.hot)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volume")
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(Int((model.gain * 100).rounded()))%")
                    .font(.uiLabel)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }

            Slider(
                value: Binding(get: { model.gain }, set: { model.setGain($0) }),
                in: 0...2
            )
            .controlSize(.small)
            .tint(Palette.accent)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.uiLabel)
                    .foregroundStyle(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Palette.border)

            HStack {
                Button("Audio setup") { model.showsSetup = true }
                    .buttonStyle(.plain)
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .pointingHandCursor()

                Spacer()

                if model.isConnected, model.connectionIsUnstable {
                    Text("Connection is unstable")
                        .font(.uiLabel)
                        .foregroundStyle(Palette.hot)
                }
            }
        }
    }
}

// MARK: - Pairing

/// Only on screen while the phone is not connected. Once it is, this is
/// answered and the space belongs to the voice bar.
private struct PairingCard: View {
    @ObservedObject var model: AppModel
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your phone")
                .font(.cardTitle)
                .foregroundStyle(Palette.text)

            if let address = model.localAddress {
                Text("\(address):\(String(AppModel.port))")
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
            } else {
                Text("Looking for your network…")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textTertiary)
            }

            Text(model.pairingHint)
                .font(.uiLabel)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                CardButton(
                    title: copied ? "Copied" : "Copy address",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                ) {
                    model.copyAddress()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                }
                .disabled(model.localAddress == nil)

                CardButton(title: "Show QR", systemImage: "qrcode") {
                    model.showsQRCode = true
                }
                .disabled(model.localAddress == nil)
            }
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
}

private struct CardButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.uiLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Palette.text : Palette.textTertiary)
        .background(hovering && isEnabled ? Palette.cardHover : Palette.control)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .pointingHandCursor()
    }
}

// MARK: - QR

private struct QRSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            QRCodeView(payload: model.qrPayload)

            VStack(spacing: 5) {
                Text("Scan with Meo Mic")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.text)
                Text("Tap Scan QR Code on your phone.")
                    .font(.uiLabel)
                    .foregroundStyle(Palette.textTertiary)
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .tint(Palette.accent)
        }
        .padding(26)
        .frame(width: 280)
        .background(Palette.window)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared

extension View {
    /// Plain buttons keep the arrow cursor by default, which makes them read
    /// as text rather than as something you can click.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
