import Foundation

public enum MeoPacketType: UInt8, Equatable, Sendable {
    case audio = 0
    case keepalive = 1
    case disconnect = 2
    case acknowledgement = 3
}

public struct MeoPacket: Equatable, Sendable {
    public static let headerSize = 8
    public static let protocolVersion: UInt8 = 1

    public let type: MeoPacketType
    public let sequence: UInt32
    public let payload: Data

    public init(type: MeoPacketType, sequence: UInt32, payload: Data = Data()) {
        self.type = type
        self.sequence = sequence
        self.payload = payload
    }

    public init?(data: Data) {
        guard data.count >= Self.headerSize,
              data[0] == 0x57,
              data[1] == 0x4D,
              data[2] == Self.protocolVersion,
              let type = MeoPacketType(rawValue: data[3])
        else {
            return nil
        }

        self.type = type
        self.sequence =
            UInt32(data[4]) << 24 |
            UInt32(data[5]) << 16 |
            UInt32(data[6]) << 8 |
            UInt32(data[7])
        self.payload = Data(data.dropFirst(Self.headerSize))
    }

    public var encoded: Data {
        var bytes: [UInt8] = [
            0x57, 0x4D, Self.protocolVersion, type.rawValue,
            UInt8((sequence >> 24) & 0xff),
            UInt8((sequence >> 16) & 0xff),
            UInt8((sequence >> 8) & 0xff),
            UInt8(sequence & 0xff)
        ]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }
}
