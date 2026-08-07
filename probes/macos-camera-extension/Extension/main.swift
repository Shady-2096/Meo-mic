// Meo macOS camera-extension feasibility probe — the extension itself.
//
// Throwaway code for CAMERA_BUILD_PLAN.md §18 step 2. It answers one
// question and no others: can a Core Media I/O camera extension be built,
// installed, and consumed on a stock Mac with a FREE Apple ID — no paid
// Developer Program, no notarization, SIP left alone?
//
// §8.1 says the answer decides whether macOS is viable at all, so it runs
// before any macOS product work. Everything here is deliberately minimal:
// there is no network, no phone, no decode, no frame bridge. It draws colour
// bars. If a meeting app cannot see this camera, the cause is the extension
// mechanism, because there is nothing else here to blame.

import CoreMediaIO
import Foundation
import os.log

// MARK: - Constants

enum Probe {
    static let width = 1280
    static let height = 720
    static let frameRate: Int32 = 30

    // §1.1: on macOS the extension controls its own display name, so unlike
    // Windows this string should appear verbatim. Verifying that is part of
    // what the probe measures.
    static let deviceName = "Meo Camera Probe"
    static let modelID = "MeoCameraProbe"
    static let manufacturer = "Meo"

    // Stable identity across reinstalls, so macOS treats an upgraded
    // extension as the same device rather than accumulating duplicates.
    static let deviceUUID = UUID(uuidString: "6E15A5C6-3E56-4A25-9C24-3F5C8C6A9D01")!
    static let streamUUID = UUID(uuidString: "0B6D2A4E-2D2C-4C0C-9E4B-77C5B3A1F002")!
    static let sourceUUID = UUID(uuidString: "9A2C1B77-4F3E-4B8D-9C11-A5E7D2B40003")!

    static let log = OSLog(subsystem: "com.meo.camera.probe.extension",
                           category: "probe")

    // 'virt' — kIOAudioDeviceTransportTypeVirtual, spelled out here because
    // that constant lives in an IOKit header Swift does not import cleanly.
    // Reporting a virtual transport is what stops macOS filing this under
    // built-in or USB cameras.
    static let virtualTransportType: Int = 0x7669_7274
}

// MARK: - Test pattern

/// Fills an NV12 buffer with colour bars plus a bar that sweeps across the
/// frame once every two seconds.
///
/// The sweep is not decoration. Colour bars that are live and colour bars
/// that are frozen look identical, and §14 lists "stale frozen image mistaken
/// for live" as a threat the product has to design against. If a consuming
/// app shows bars but the sweep has stopped, frames stopped arriving — which
/// is a failure, not a pass.
///
/// NV12 is used rather than BGRA because §8.3 fixes NV12 as the extension's
/// published format. Testing the format the product will actually ship is
/// worth the extra plane arithmetic here.
func writeTestFrame(into pixelBuffer: CVPixelBuffer, frameIndex: UInt64) {
    // Studio-range Y'CbCr. Full-range values through a studio-range consumer
    // look washed out, which reads as a bug somewhere else entirely.
    let bars: [(y: UInt8, u: UInt8, v: UInt8)] = [
        (235, 128, 128),  // white
        (210, 16, 146),   // yellow
        (170, 166, 16),   // cyan
        (145, 54, 34),    // green
        (106, 202, 222),  // magenta
        (81, 90, 240),    // red
        (41, 240, 110),   // blue
        (16, 128, 128),   // black
    ]

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let barWidth = max(1, width / 8)

    let sweepPeriod = UInt64(Probe.frameRate) * 2
    let sweepX = Int((frameIndex % sweepPeriod) * UInt64(width) / sweepPeriod)
    let sweepHalfWidth = 6

    // Y plane.
    if let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let y = yBase.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            let rowStart = row * yStride
            for col in 0..<width {
                let inSweep = col > sweepX - sweepHalfWidth
                    && col < sweepX + sweepHalfWidth
                y[rowStart + col] = inSweep ? 235 : bars[(col / barWidth) % 8].y
            }
        }
    }

    // Interleaved CbCr plane at half resolution in both axes.
    if let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let uv = uvBase.assumingMemoryBound(to: UInt8.self)
        for row in 0..<(height / 2) {
            let rowStart = row * uvStride
            for col in 0..<(width / 2) {
                let fullCol = col * 2
                let inSweep = fullCol > sweepX - sweepHalfWidth
                    && fullCol < sweepX + sweepHalfWidth
                let bar = bars[(fullCol / barWidth) % 8]
                uv[rowStart + col * 2] = inSweep ? 128 : bar.u
                uv[rowStart + col * 2 + 1] = inSweep ? 128 : bar.v
            }
        }
    }
}

// MARK: - Stream

final class ProbeStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat

    init(localizedName: String,
         streamID: UUID,
         format: CMIOExtensionStreamFormat,
         device: CMIOExtensionDevice) {
        self.format = format
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName,
                                          streamID: streamID,
                                          direction: .source,
                                          clockType: .hostTime,
                                          source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            result.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            result.frameDuration = CMTime(value: 1, timescale: Probe.frameRate)
        }
        return result
    }

    func setStreamProperties(
        _ streamProperties: CMIOExtensionStreamProperties
    ) throws {
        // One format only, so there is nothing a client can meaningfully
        // change. Accepting silently is friendlier than throwing at a client
        // that is just echoing properties back.
    }

    // The probe authorizes every client. A real build must not: §6.5 and §14
    // require the camera to be explicit about who is consuming it.
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        os_log("client started stream: %{public}@",
               log: Probe.log, type: .info, client.signingID ?? "unknown")
        return true
    }

    func startStream() throws {
        guard let device = ProbeDeviceSource.shared else { return }
        device.startStreaming()
    }

    func stopStream() throws {
        guard let device = ProbeDeviceSource.shared else { return }
        device.stopStreaming()
    }
}

// MARK: - Device

final class ProbeDeviceSource: NSObject, CMIOExtensionDeviceSource {
    static var shared: ProbeDeviceSource?

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: ProbeStreamSource!
    private var bufferPool: CVPixelBufferPool?
    private var formatDescription: CMFormatDescription?

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.meo.camera.probe.frames",
                                           qos: .userInteractive)
    private var frameIndex: UInt64 = 0
    private var clientCount = 0
    private let lock = NSLock()

    init(localizedName: String) {
        super.init()

        device = CMIOExtensionDevice(localizedName: localizedName,
                                     deviceID: Probe.deviceUUID,
                                     legacyDeviceID: nil,
                                     source: self)

        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: Probe.width,
            kCVPixelBufferHeightKey as String: Probe.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
                                attributes as CFDictionary, &bufferPool)

        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: pixelFormat,
                                       width: Int32(Probe.width),
                                       height: Int32(Probe.height),
                                       extensions: nil,
                                       formatDescriptionOut: &formatDescription)

        guard let formatDescription else {
            os_log("failed to create format description", log: Probe.log,
                   type: .error)
            return
        }

        let format = CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration: CMTime(value: 1, timescale: Probe.frameRate),
            minFrameDuration: CMTime(value: 1, timescale: Probe.frameRate),
            validFrameDurations: nil)

        streamSource = ProbeStreamSource(localizedName: "\(localizedName) video",
                                         streamID: Probe.streamUUID,
                                         format: format,
                                         device: device)
        do {
            try device.addStream(streamSource.stream)
        } catch {
            os_log("addStream failed: %{public}@", log: Probe.log,
                   type: .error, error.localizedDescription)
        }

        ProbeDeviceSource.shared = self
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            result.transportType = Probe.virtualTransportType
        }
        if properties.contains(.deviceModel) {
            result.model = Probe.modelID
        }
        return result
    }

    func setDeviceProperties(
        _ deviceProperties: CMIOExtensionDeviceProperties
    ) throws {}

    func startStreaming() {
        lock.lock()
        clientCount += 1
        let shouldStart = clientCount == 1
        lock.unlock()

        guard shouldStart, bufferPool != nil else { return }
        os_log("starting frame generation", log: Probe.log, type: .info)

        let timer = DispatchSource.makeTimerSource(flags: .strict,
                                                   queue: timerQueue)
        timer.schedule(deadline: .now(),
                       repeating: 1.0 / Double(Probe.frameRate),
                       leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.emitFrame() }
        timer.resume()
        self.timer = timer
    }

    func stopStreaming() {
        lock.lock()
        clientCount = max(0, clientCount - 1)
        let shouldStop = clientCount == 0
        lock.unlock()

        guard shouldStop else { return }
        os_log("stopping frame generation", log: Probe.log, type: .info)
        timer?.cancel()
        timer = nil
    }

    private func emitFrame() {
        guard let bufferPool, let formatDescription else { return }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                 bufferPool,
                                                 &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return }

        writeTestFrame(into: pixelBuffer, frameIndex: frameIndex)
        frameIndex += 1

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Probe.frameRate),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)

        guard status == noErr, let sampleBuffer else { return }

        streamSource.stream.send(sampleBuffer,
                                 discontinuity: [],
                                 hostTimeInNanoseconds: UInt64(
                                    timing.presentationTimeStamp.seconds
                                    * Double(NSEC_PER_SEC)))
    }
}

// MARK: - Provider

final class ProbeProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ProbeDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ProbeDeviceSource(localizedName: Probe.deviceName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            os_log("addDevice failed: %{public}@", log: Probe.log,
                   type: .error, error.localizedDescription)
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        os_log("client connected: %{public}@", log: Probe.log, type: .info,
               client.signingID ?? "unknown")
    }

    func disconnect(from client: CMIOExtensionClient) {
        os_log("client disconnected", log: Probe.log, type: .info)
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            result.manufacturer = Probe.manufacturer
        }
        return result
    }

    func setProviderProperties(
        _ providerProperties: CMIOExtensionProviderProperties
    ) throws {}
}

// MARK: - Entry point

os_log("Meo camera probe extension starting", log: Probe.log, type: .info)
let providerSource = ProbeProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
