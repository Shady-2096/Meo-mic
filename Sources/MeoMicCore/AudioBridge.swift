import AVFAudio
import CMeoAudio
import Foundation

public struct AudioBridgeStats: Sendable {
    public let bufferMilliseconds: Double
    public let driftPartsPerMillion: Double
    public let underruns: UInt64
    public let overruns: UInt64
}

public final class AudioBridge: @unchecked Sendable {
    public var onPeak: ((Double) -> Void)?
    public var onError: ((String?) -> Void)?

    private let engine = AVAudioEngine()
    private let ring: OpaquePointer
    private var sourceNode: AVAudioSourceNode?
    private var gain: Float = 1
    private let queue = DispatchQueue(label: "app.meomic.audio")
    private(set) public var selectedDevice: AudioDevice?

    public init() {
        guard let ring = meo_ring_create(48_000, 2_400) else {
            fatalError("Unable to allocate audio jitter buffer")
        }
        self.ring = ring
    }

    deinit {
        stop()
        meo_ring_destroy(ring)
    }

    public func setGain(_ value: Double) {
        queue.async { [weak self] in
            self?.gain = Float(max(0, min(2, value)))
        }
    }

    public func select(_ device: AudioDevice?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopEngine()
            self.selectedDevice = device
            meo_ring_clear(self.ring)
            guard let device else {
                self.onError?(nil)
                return
            }
            do {
                try self.configureAndStart(device)
                self.onError?(nil)
            } catch {
                self.onError?("Could not route audio to \(device.name): \(error.localizedDescription)")
            }
        }
    }

    public func resetStream() {
        queue.async { [weak self] in
            guard let self else { return }
            meo_ring_clear(self.ring)
        }
    }

    public func write(pcm16LittleEndian data: Data) {
        guard !data.isEmpty else { return }
        let localGain = gain
        var peak: Int32 = 0
        data.withUnsafeBytes { raw in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            _ = meo_ring_write_pcm16le(ring, bytes, UInt32(data.count), localGain)
            var index = 0
            while index + 1 < data.count {
                let rawValue = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                let sample = Int32(abs(Int(Int16(bitPattern: rawValue))))
                peak = max(peak, sample)
                index += 2
            }
        }
        let normalized = min(1, Double(peak) * Double(localGain) / 32_768)
        let db = 20 * log10(max(normalized, 0.000_001))
        onPeak?(db)
    }

    public func stats() -> AudioBridgeStats {
        let available = meo_ring_available(ring)
        let ratio = meo_ring_current_ratio(ring)
        return AudioBridgeStats(
            bufferMilliseconds: Double(available) / 48,
            driftPartsPerMillion: (ratio - 1) * 1_000_000,
            underruns: meo_ring_underruns(ring),
            overruns: meo_ring_overruns(ring)
        )
    }

    public func stop() {
        queue.sync {
            stopEngine()
        }
    }

    private func configureAndStart(_ device: AudioDevice) throws {
        let output = engine.outputNode
        try output.auAudioUnit.setDeviceID(device.id)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            _ = meo_ring_render(ring, first, frameCount)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        engine.stop()
        if let sourceNode {
            engine.disconnectNodeOutput(sourceNode)
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
    }
}
