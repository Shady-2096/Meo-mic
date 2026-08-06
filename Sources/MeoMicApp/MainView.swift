import AppKit
import MeoMicCore
import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)
                .padding(.top, 18)
            signalSection
            Divider().overlay(Palette.line)
            routeSection
            Divider().overlay(Palette.line)
            outputSection
            footer
        }
        .padding(.horizontal, 26)
        .frame(minWidth: 480, idealWidth: 480, maxWidth: 480, minHeight: 600)
        .background(Palette.crust)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showsSetup) {
            SetupView(model: model)
        }
        .sheet(isPresented: $model.showsQRCode) {
            qrSheet
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                GrilleMark()
                Text("MEO MIC")
                    .font(.panel(18, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isConnected ? Palette.text : Palette.surface2)
                    .frame(width: 6, height: 6)
                Text(model.isConnected ? "PHONE LIVE" : "WAITING")
                    .font(.panel(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(model.isConnected ? Palette.subtext : Palette.overlay)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Palette.base)
            .clipShape(Capsule())
        }
        .padding(.top, 22)
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("INPUT LEVEL")
                Spacer()
                Text(model.isConnected ? String(format: "%+.1f dBFS", model.displayDB) : "— dBFS")
                    .font(.data(12, weight: .semibold))
                    .foregroundStyle(model.isConnected ? Palette.subtext : Palette.overlay)
            }

            LevelMeter(levelDB: model.isConnected ? model.displayDB : -60,
                       peakDB: model.isConnected ? model.peakDB : -60)

            HStack {
                Text(signalMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.overlay)
                Spacer()
                if model.isConnected {
                    Text(
                        model.selectedDevice == nil
                            ? "ROUTE OFF"
                            : String(format: "BUFFER %.0f MS", model.bufferMilliseconds)
                    )
                        .font(.data(10, weight: .medium))
                        .foregroundStyle(Palette.overlay)
                }
            }
        }
        .padding(.vertical, 20)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("PHONE CONNECTS AUTOMATICALLY")
            Text(model.connectionAddress)
                .font(.data(20, weight: .semibold))
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                QuietButton(title: copied ? "Copied" : "Copy address", systemImage: "doc.on.doc") {
                    model.copyAddress()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                QuietButton(title: "Show QR", systemImage: "qrcode") {
                    model.showsQRCode = true
                }
                Spacer()
            }
        }
        .padding(.vertical, 18)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("CALL APP ROUTE")
                Spacer()
                if model.routeIsReady {
                    Text("VIRTUAL")
                        .font(.data(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.overlay)
                }
            }

            Picker("Output device", selection: Binding(
                get: { model.selectedDeviceUID },
                set: { model.selectDevice(uid: $0) }
            )) {
                Text("Choose an output…").tag(Optional<String>.none)
                ForEach(model.devices) { device in
                    Text(device.isVirtual ? "\(device.name) — virtual" : device.name)
                        .tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(routeMessage)
                .font(.system(size: 12))
                .foregroundStyle(Palette.overlay)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Eyebrow("GAIN")
                Slider(
                    value: Binding(get: { model.gain }, set: { model.setGain($0) }),
                    in: 0...2,
                    step: 0.01
                )
                .tint(Palette.surface2)
                Text("\(Int((model.gain * 100).rounded()))%")
                    .font(.data(11, weight: .semibold))
                    .foregroundStyle(Palette.subtext)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Button("Audio setup") { model.showsSetup = true }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.subtext)
            Spacer()
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.peach)
                    .lineLimit(1)
                    .help(error)
            } else {
                Text(model.packetsLost == 0 ? "48 KHZ · PCM" : "\(model.packetsLost) PACKETS LOST")
                    .font(.data(9, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Palette.overlay)
            }
        }
        .padding(.vertical, 17)
    }

    private var qrSheet: some View {
        VStack(spacing: 16) {
            QRCodeView(payload: model.qrPayload)
            Text("Scan with Meo Mic")
                .font(.panel(18, weight: .bold))
                .foregroundStyle(Palette.text)
            Text(model.connectionAddress)
                .font(.data(12))
                .foregroundStyle(Palette.overlay)
            Button("Done") { model.showsQRCode = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 270)
        .background(Palette.crust)
        .preferredColorScheme(.dark)
    }

    private var signalMessage: String {
        guard model.isConnected else { return "Waiting for your phone on the same Wi-Fi" }
        return "Voice is arriving from \(model.clientAddress ?? "your phone")"
    }

    private var routeMessage: String {
        guard let device = model.selectedDevice else {
            return "Install a virtual audio device before starting a call."
        }
        if device.isVirtual {
            return "Ready. Pick \(device.name) as the microphone in Discord, Zoom, or Meet."
        }
        return "This plays through \(device.name). Choose a virtual device to use it as a microphone."
    }
}

struct Eyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.panel(10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.overlay)
    }
}

private struct QuietButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.subtext)
        .background(Palette.base)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Palette.surface0, lineWidth: 0.5)
        }
    }
}

private struct GrilleMark: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(index == 2 ? Palette.mauve : Palette.surface2)
                    .frame(width: 2.5, height: index == 2 ? 19 : 14)
            }
        }
        .frame(width: 22, height: 22)
        .background(Palette.base)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
