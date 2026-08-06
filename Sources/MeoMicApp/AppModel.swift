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
    @Published private(set) var peakDB = -60.0
    @Published private(set) var bufferMilliseconds = 0.0
    @Published private(set) var driftPPM = 0.0
    @Published private(set) var packetsLost = 0
    @Published private(set) var errorMessage: String?
    @Published var showsSetup = false
    @Published var showsQRCode = false

    let localAddress = LocalAddress.preferredIPv4() ?? "Unavailable"

    private let receiver = NetworkReceiver()
    private let audio = AudioBridge()
    private var timer: Timer?
    private var targetDB = -60.0
    private var peakHoldUntil = Date.distantPast
    private var lastPeakAt = Date.distantPast
    private var started = false

    var isConnected: Bool { clientAddress != nil }
    var selectedDevice: AudioDevice? {
        devices.first { $0.uid == selectedDeviceUID }
    }
    var hasVirtualDevice: Bool { devices.contains(where: \.isVirtual) }
    var connectionAddress: String { "\(localAddress):\(Self.port)" }
    var qrPayload: String { "meomic://\(localAddress):\(Self.port)" }
    var routeIsReady: Bool { selectedDevice?.isVirtual == true }

    func start() {
        guard !started else { return }
        started = true
        devices = AudioDevices.outputDevices()

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
                self.peakDB = -60
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionAddress, forType: .string)
    }

    private func tick() {
        if Date().timeIntervalSince(lastPeakAt) > 0.07 {
            targetDB = -60
        }

        if targetDB >= displayDB {
            displayDB = targetDB
        } else {
            displayDB = max(targetDB, displayDB - 26 / 30)
        }

        if displayDB >= peakDB {
            peakDB = displayDB
            peakHoldUntil = Date().addingTimeInterval(1.1)
        } else if Date() > peakHoldUntil {
            peakDB = max(displayDB, peakDB - 18 / 30)
        }

        let audioStats = audio.stats()
        bufferMilliseconds = audioStats.bufferMilliseconds
        driftPPM = audioStats.driftPartsPerMillion
        receiver.currentStats { [weak self] stats in
            Task { @MainActor in self?.packetsLost = stats.packetsLost }
        }
    }
}
