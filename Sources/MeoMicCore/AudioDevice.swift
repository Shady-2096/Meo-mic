import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let outputChannels: Int
    public let isVirtual: Bool

    public init(id: AudioDeviceID, uid: String, name: String, outputChannels: Int) {
        self.id = id
        self.uid = uid
        self.name = name
        self.outputChannels = outputChannels
        let lowered = name.lowercased()
        self.isVirtual = [
            "blackhole", "loopback", "existential audio", "soundflower",
            "virtual", "cable", "meo mic"
        ].contains { lowered.contains($0) }
    }
}

public enum AudioDevices {
    public static func outputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount
        ) == noErr else {
            return []
        }

        let count = Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount, &ids
        ) == noErr else {
            return []
        }

        return ids.compactMap { id in
            let channels = outputChannelCount(id)
            guard channels > 0 else { return nil }
            return AudioDevice(
                id: id,
                uid: stringProperty(id, selector: kAudioDevicePropertyDeviceUID) ?? "\(id)",
                name: stringProperty(id, selector: kAudioObjectPropertyName) ?? "Audio Device \(id)",
                outputChannels: channels
            )
        }
        .sorted {
            if $0.isVirtual != $1.isVirtual { return $0.isVirtual && !$1.isVirtual }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func stringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value
        else {
            return nil
        }
        return value.takeUnretainedValue() as String
    }

    private static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              let raw = malloc(Int(size))
        else {
            return 0
        }
        defer { free(raw) }

        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else {
            return 0
        }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }
}
