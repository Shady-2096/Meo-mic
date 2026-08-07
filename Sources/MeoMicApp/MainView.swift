import AppKit
import MeoMicCore
import SwiftUI

/// A compact Mac utility panel.
///
/// One status line, a live waveform, and a single grouped card of the two
/// things you ever set. It deliberately does not diagram the audio path: the
/// route only matters when it is broken, so a broken leg is one line of plain
/// text under the card and the rest of the time the window says nothing about
/// it at all.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            status

            if model.isConnected {
                voice
            } else {
                pairing
            }

            settings

            footer
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, Metrics.topInset)
        .padding(.bottom, 16)
        .frame(width: Metrics.window)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowMaterial().ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: model.isConnected)
        .sheet(isPresented: $model.showsSetup) {
            SetupView(model: model)
        }
        .sheet(isPresented: $model.showsQRCode) {
            QRSheet(model: model)
        }
    }

    // MARK: - Status

    private var status: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.isConnected ? Palette.live.opacity(0.15) : Palette.controlFill)
                    .frame(width: 30, height: 30)

                Image(systemName: model.isConnected ? "waveform" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.isConnected ? Palette.live : Palette.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.statusHeadline)
                    .font(.statusTitle)
                    .foregroundStyle(Palette.label)

                Text(model.statusDetail)
                    .font(.supporting)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Voice

    private var voice: some View {
        let wave = Waveform(
            samples: model.waveform,
            isLive: true,
            isHot: model.displayDB >= -3
        )
        return VStack(alignment: .leading, spacing: 6) {
            wave
            Text(wave.caption)
                .font(.caption)
                .foregroundStyle(wave.captionColor)
        }
    }

    // MARK: - Pairing

    /// Only while the phone is not through. The address is a field you can
    /// select and copy, not a headline — reading it off the screen into a
    /// phone is the actual task.
    @ViewBuilder
    private var pairing: some View {
        if let address = model.localAddress {
            VStack(alignment: .leading, spacing: 7) {
                Group_ {
                    HStack(spacing: 6) {
                        Text("\(address):\(String(AppModel.port))")
                            .font(.address)
                            .monospacedDigit()
                            .foregroundStyle(Palette.label)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

                        IconButton(
                            symbol: copied ? "checkmark" : "square.on.square",
                            help: copied ? "Copied" : "Copy address"
                        ) {
                            model.copyAddress()
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                        }

                        IconButton(symbol: "qrcode", help: "Show QR code") {
                            model.showsQRCode = true
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Text(model.pairingHint)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group_ {
                Row(label: "Output") {
                    Picker("Output", selection: Binding(
                        get: { model.selectedDeviceUID },
                        set: { model.selectDevice(uid: $0) }
                    )) {
                        Text("Choose…").tag(Optional<String>.none)
                        ForEach(model.devices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 170)
                }

                RowSeparator()

                Row(label: "Volume") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(get: { model.gain }, set: { model.setGain($0) }),
                            in: 0...2
                        )
                        .controlSize(.small)

                        Text("\(Int((model.gain * 100).rounded()))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: 170)
                }
            }

            if !model.routeIsReady {
                InlineNote(
                    symbol: "exclamationmark.circle.fill",
                    tint: Palette.warning,
                    message: model.routeMessage
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                InlineNote(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Palette.error,
                    message: error
                )
            }

            if model.isConnected, model.connectionIsUnstable {
                InlineNote(
                    symbol: "wifi.exclamationmark",
                    tint: Palette.warning,
                    message: "Connection is unstable."
                )
            }

            HStack {
                Button("Audio Setup…") { model.showsSetup = true }
                    .buttonStyle(.link)
                    .font(.caption)

                Spacer()

                if model.routeIsReady {
                    Text(model.routeMessage)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(model.routeMessage)
                }
            }
        }
    }
}

// MARK: - QR

private struct QRSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            QRCodeView(payload: model.qrPayload)

            VStack(spacing: 3) {
                Text("Scan with Meo Mic")
                    .font(.system(.headline))
                    .foregroundStyle(Palette.label)
                Text("Tap Scan QR Code on your phone.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .frame(width: 260)
        .background(WindowMaterial().ignoresSafeArea())
    }
}
