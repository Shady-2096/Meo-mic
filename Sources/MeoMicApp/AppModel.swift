import AppKit
import Combine
import Foundation
import MeoMicCore

@MainActor
final class AppModel: ObservableObject {
    static let port: UInt16 = 48_888

    @Published private(set) var clientAddress: String?
    @Published private(set) var devices: [AudioDevice] = []
    @Published var selectedDeviceUID: String?
    @Published var gain = 1.0
    @Published private(set) var displayDB = -60.0
    @Published private(set) var packetsLost = 0
    @Published private(set) var errorMessage: String?
    @Published var showsSetup = false
    @Published var showsQRCode = false

    /// Nil until macOS will tell us. Resolved repeatedly rather than once at
    /// launch: on macOS 15 and later an app sees no useful interface list
    /// until the person has granted Local Network access, and that approval
    /// arrives seconds after the window is already on screen.
    @Published private(set) var localAddress: String?

    private let receiver = NetworkReceiver()
    private let audio = AudioBridge()
    private var timer: Timer?
    private var targetDB = -60.0
    private var lastPeakAt = Date.distantPast
    private var ticksSinceAddressCheck = 0
    private var started = false

    var isConnected: Bool { clientAddress != nil }
    var selectedDevice: AudioDevice? {
        devices.first { $0.uid == selectedDeviceUID }
    }
    var hasVirtualDevice: Bool { devices.contains(where: \.isVirtual) }
    var routeIsReady: Bool { selectedDevice?.isVirtual == true }
    var connectionAddress: String {
        guard let localAddress else { return "" }
        return "\(localAddress):\(Self.port)"
    }
    var qrPayload: String { "meomic://\(connectionAddress)" }

    /// Enough packets have gone missing that the person would notice it as
    /// choppy audio. Below this, silence is the right thing to say.
    var connectionIsUnstable: Bool { packetsLost > 50 }

    // MARK: - The sentence the window is built around

    var statusHeadline: String {
        isConnected ? "Your phone is live" : "Waiting for your phone"
    }

    var statusDetail: String {
        if isConnected {
            if let device = selectedDevice, device.isVirtual {
                return "Arriving from \(clientAddress ?? "your phone") and going into \(device.name)."
            }
            return "Arriving from \(clientAddress ?? "your phone")."
        }
        if localAddress == nil {
            return "Connect this Mac to Wi-Fi first."
        }
        return "Open Meo Mic on your phone — it will find this Mac."
    }

    var pairingHint: String {
        "Tap Search for PC on your phone, or scan the code."
    }

    var routeMessage: String {
        guard let device = selectedDevice else {
            return "Pick a virtual audio device so call apps can hear your phone."
        }
        if device.isVirtual {
            return "Ready — choose \(device.name) as your microphone in Discord, Zoom, or Meet."
        }
        return "This plays out loud. No app can use it as a microphone."
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        devices = AudioDevices.outputDevices()
        localAddress = LocalAddress.preferredIPv4()

        let savedUID = UserDefaults.standard.string(forKey: "outputDeviceUID")
        let initial = devices.first { $0.uid == savedUID }
            ?? devices.first(where: \.isVirtual)
        selectedDeviceUID = initial?.uid
        audio.select(initial)
        if initial == nil {
            showsSetup = true
        }

        receiver.onAudio = { [weak self] data in
            self?.audio.write(pcm16LittleEndian: data)
        }
        receiver.onConnectionChanged = { [weak self] address in
            Task { @MainActor in
                guard let self else { return }
                self.clientAddress = address
                self.targetDB = -60
                self.displayDB = -60
                self.packetsLost = 0
                self.audio.resetStream()
            }
        }
        receiver.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }
        audio.onPeak = { [weak self] db in
            Task { @MainActor in
                self?.targetDB = max(-60, min(0, db))
                self?.lastPeakAt = Date()
            }
        }
        audio.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }

        do {
            try receiver.start(port: Self.port)
        } catch {
            errorMessage = error.localizedDescription
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        receiver.stop()
        audio.stop()
    }

    func selectDevice(uid: String?) {
        selectedDeviceUID = uid
        let device = devices.first { $0.uid == uid }
        audio.select(device)
        if let uid {
            UserDefaults.standard.set(uid, forKey: "outputDeviceUID")
        } else {
            UserDefaults.standard.removeObject(forKey: "outputDeviceUID")
        }
    }

    func setGain(_ value: Double) {
        gain = value
        audio.setGain(value)
    }

    func refreshDevices() {
        let previous = selectedDeviceUID
        devices = AudioDevices.outputDevices()
        if devices.contains(where: { $0.uid == previous }) {
            return
        }
        let replacement = devices.first(where: \.isVirtual)
        selectDevice(uid: replacement?.uid)
    }

    func copyAddress() {
        guard !connectionAddress.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionAddress, forType: .string)
    }

    // MARK: - Frame

    private func tick() {
        if Date().timeIntervalSince(lastPeakAt) > 0.07 {
            targetDB = -60
        }

        // Instant attack, timed release. Without the asymmetry the bar
        // flickers on every syllable and stops being readable.
        if targetDB >= displayDB {
            displayDB = targetDB
        } else {
            displayDB = max(targetDB, displayDB - 26 / 30)
        }

        receiver.currentStats { [weak self] stats in
            Task { @MainActor in self?.packetsLost = stats.packetsLost }
        }

        ticksSinceAddressCheck += 1
        if ticksSinceAddressCheck >= 60 {
            ticksSinceAddressCheck = 0
            let resolved = LocalAddress.preferredIPv4()
            if resolved != localAddress {
                localAddress = resolved
            }
        }
    }
}
