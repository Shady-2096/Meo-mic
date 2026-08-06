import CMeoAudio
import Foundation
import MeoMicCore
import Testing

@Test func parsesBigEndianHeaderAndPreservesLittleEndianPayload() {
    let bytes: [UInt8] = [
        0x57, 0x4D, 0x01, 0x00,
        0x12, 0x34, 0x56, 0x78,
        0x34, 0x12, 0xCC, 0xFF
    ]
    let packet = MeoPacket(data: Data(bytes))

    #expect(packet?.type == .audio)
    #expect(packet?.sequence == 0x12345678)
    #expect(packet?.payload == Data([0x34, 0x12, 0xCC, 0xFF]))
}

@Test func acknowledgementEncodingMatchesWireProtocol() {
    let packet = MeoPacket(type: .acknowledgement, sequence: 0xA1B2C3D4)
    #expect(Array(packet.encoded) == [
        0x57, 0x4D, 0x01, 0x03,
        0xA1, 0xB2, 0xC3, 0xD4
    ])
}

@Test func rejectsMalformedPackets() {
    #expect(MeoPacket(data: Data([0x57, 0x4D])) == nil)
    #expect(MeoPacket(data: Data([0x58, 0x4D, 1, 1, 0, 0, 0, 0])) == nil)
    #expect(MeoPacket(data: Data([0x57, 0x4D, 2, 1, 0, 0, 0, 0])) == nil)
}

@Test func ringBufferDecodesPCMAndPrimesAtTarget() {
    let ring = meo_ring_create(32, 4)!
    defer { meo_ring_destroy(ring) }
    let pcm: [UInt8] = [
        0x00, 0x00,
        0x00, 0x40,
        0x00, 0x80,
        0xFF, 0x7F,
        0x00, 0x00,
        0x00, 0x00
    ]
    pcm.withUnsafeBufferPointer {
        _ = meo_ring_write_pcm16le(ring, $0.baseAddress, UInt32($0.count), 1)
    }
    var output = [Float](repeating: 0, count: 3)
    let produced = meo_ring_render(ring, &output, UInt32(output.count))

    #expect(produced == 3)
    #expect(abs(output[0]) < 0.0001)
    #expect(abs(output[1] - 0.5) < 0.001)
    #expect(abs(output[2] + 1.0) < 0.001)
}
