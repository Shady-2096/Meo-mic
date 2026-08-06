import Foundation
import Network

public final class NetworkReceiver: @unchecked Sendable {
    public struct Stats: Sendable {
        public var packetsReceived = 0
        public var packetsLost = 0
    }

    public var onAudio: ((Data) -> Void)?
    public var onConnectionChanged: ((String?) -> Void)?
    public var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "app.meomic.receiver", qos: .userInitiated)
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var activeEndpoint: NWEndpoint?
    private var timeoutTimer: DispatchSourceTimer?
    private var lastPacketAt = DispatchTime.now()
    private var lastAckAt = DispatchTime(uptimeNanoseconds: 0)
    private var lastSequence: UInt32?
    private var ackSequence: UInt32 = 0
    private var stats = Stats()

    public init() {}

    public func start(port: UInt16 = 48_888) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.service = NWListener.Service(
            name: "Meo Mic \(Host.current().localizedName ?? "Mac")",
            type: "_meomic._udp",
            domain: "local.",
            txtRecord: NWTXTRecord(["version": "1", "platform": "macOS"])
        )
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                self?.onError?("Could not listen on UDP \(port): \(error.localizedDescription)")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        startTimeoutTimer()
    }

    public func stop() {
        queue.async { [weak self] in
            self?.disconnectCurrent(notify: true)
            self?.listener?.cancel()
            self?.listener = nil
            self?.timeoutTimer?.cancel()
            self?.timeoutTimer = nil
        }
    }

    public func currentStats(_ completion: @escaping (Stats) -> Void) {
        queue.async { [weak self] in completion(self?.stats ?? Stats()) }
    }

    private func accept(_ connection: NWConnection) {
        let endpoint = connection.endpoint
        if activeEndpoint != endpoint {
            activeConnection?.cancel()
            activeConnection = connection
            activeEndpoint = endpoint
            lastPacketAt = .now()
            lastAckAt = DispatchTime(uptimeNanoseconds: 0)
            lastSequence = nil
            stats = Stats()
            onConnectionChanged?(host(from: endpoint))
        }

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .ready = state, let connection {
                self?.receive(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] content, _, _, error in
            guard let self, let connection else { return }
            if let content, let packet = MeoPacket(data: content) {
                self.handle(packet, on: connection)
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ packet: MeoPacket, on connection: NWConnection) {
        guard connection === activeConnection else { return }
        lastPacketAt = .now()
        stats.packetsReceived += 1

        if let previous = lastSequence {
            let expected = previous &+ 1
            if packet.sequence != expected {
                let missing = packet.sequence &- expected
                if missing < 1_000 {
                    stats.packetsLost += Int(missing)
                }
            }
        }
        lastSequence = packet.sequence

        switch packet.type {
        case .audio:
            if !packet.payload.isEmpty {
                onAudio?(packet.payload)
            }
            if elapsed(since: lastAckAt) >= 0.5 {
                sendAcknowledgement(on: connection)
            }
        case .keepalive:
            sendAcknowledgement(on: connection)
        case .disconnect:
            disconnectCurrent(notify: true)
        case .acknowledgement:
            break
        }
    }

    private func sendAcknowledgement(on connection: NWConnection) {
        let packet = MeoPacket(type: .acknowledgement, sequence: ackSequence)
        ackSequence &+= 1
        lastAckAt = .now()
        connection.send(content: packet.encoded, completion: .contentProcessed { _ in })
    }

    private func startTimeoutTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.activeConnection != nil else { return }
            if self.elapsed(since: self.lastPacketAt) > 5 {
                self.disconnectCurrent(notify: true)
            }
        }
        timer.resume()
        timeoutTimer = timer
    }

    private func disconnectCurrent(notify: Bool) {
        guard activeConnection != nil else { return }
        activeConnection?.cancel()
        activeConnection = nil
        activeEndpoint = nil
        lastSequence = nil
        if notify {
            onConnectionChanged?(nil)
        }
    }

    private func elapsed(since time: DispatchTime) -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds) / 1_000_000_000
    }

    private func host(from endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, _) = endpoint {
            return "\(host)"
        }
        return "\(endpoint)"
    }
}
