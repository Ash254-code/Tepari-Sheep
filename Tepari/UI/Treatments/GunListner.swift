import Foundation
import Network
import Combine

@MainActor
final class GunListener: ObservableObject {

    enum State: String, Hashable {
        case stopped
        case starting
        case listening
        case error

        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting"
            case .listening: return "Listening"
            case .error: return "Error"
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var port: UInt16 = 2000
    @Published private(set) var lastPeer: String = "—"
    @Published private(set) var lastMessageText: String? = nil
    @Published private(set) var lastErrorText: String? = nil
    @Published private(set) var log: [LogEntry] = []

    // Raw packet state
    @Published private(set) var lastPacket: String? = nil
    @Published private(set) var lastKeepAliveAt: Date? = nil

    // Decoded gun data
    @Published private(set) var lastPlainDoseML: Double? = nil          // from <285>
    @Published private(set) var lastStructuredDoseML: Double? = nil     // from <R0403285>
    @Published private(set) var lastTriggerDoseML: Double? = nil        // best "real" trigger dose
    @Published private(set) var lastTriggerAt: Date? = nil

    // TX diagnostics
    @Published private(set) var lastSentText: String? = nil
    @Published private(set) var lastSentAt: Date? = nil

    let packetSubject = PassthroughSubject<String, Never>()
    let triggerDoseSubject = PassthroughSubject<Double, Never>()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tepari.gun.listener")
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var currentConnectionKey: ObjectIdentifier? = nil

    // Pending TX support
    private var pendingRawText: String? = nil
    private var pendingQueuedAt: Date? = nil

    // =====================================================
    // MARK: - Public
    // =====================================================

    func start(port: UInt16 = 2000) {
        stop(silent: true)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = .error
            lastErrorText = "Invalid listener port \(port)"
            addLog("Start failed: invalid port \(port)")
            return
        }

        do {
            self.port = port
            state = .starting
            lastErrorText = nil
            addLog("Starting listener on port \(port)")

            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task { @MainActor in
                    switch newState {
                    case .setup:
                        self.addLog("Listener setup")

                    case .waiting(let error):
                        self.state = .error
                        self.lastErrorText = error.localizedDescription
                        self.addLog("Listener waiting: \(error.localizedDescription)")

                    case .ready:
                        self.state = .listening
                        self.lastErrorText = nil
                        self.addLog("Listening on port \(port)")

                    case .failed(let error):
                        self.state = .error
                        self.lastErrorText = error.localizedDescription
                        self.addLog("Listener failed: \(error.localizedDescription)")

                    case .cancelled:
                        if self.state != .error {
                            self.state = .stopped
                        }
                        self.addLog("Listener cancelled")

                    @unknown default:
                        self.state = .error
                        self.lastErrorText = "Unknown listener state"
                        self.addLog("Listener unknown state")
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { @MainActor in
                    self.accept(connection)
                }
            }

            listener.start(queue: queue)

        } catch {
            state = .error
            lastErrorText = error.localizedDescription
            addLog("Start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        stop(silent: false)
    }

    func clearLog() {
        log.removeAll()
    }

    func clearStatus() {
        lastMessageText = nil
        lastErrorText = nil
        lastPacket = nil
        lastKeepAliveAt = nil
        lastPlainDoseML = nil
        lastStructuredDoseML = nil
        lastTriggerDoseML = nil
        lastTriggerAt = nil
        lastSentText = nil
        lastSentAt = nil
        pendingRawText = nil
        pendingQueuedAt = nil
    }

    func sendRaw(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let connection = currentActiveConnection() {
            write(trimmed, over: connection)
            return
        }

        pendingRawText = trimmed
        pendingQueuedAt = Date()
        lastErrorText = "No active gun connection. Command queued."
        addLog("TX queued awaiting gun connection: \(trimmed)")
    }

    func sendWrapped(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendRaw("<\(trimmed)>")
    }

    // =====================================================
    // MARK: - Internals
    // =====================================================

    private func stop(silent: Bool) {
        for (_, conn) in activeConnections {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        activeConnections.removeAll()
        currentConnectionKey = nil

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        if !silent {
            state = .stopped
            addLog("Listener stopped")
        }
    }

    private func currentActiveConnection() -> NWConnection? {
        if let key = currentConnectionKey, let conn = activeConnections[key] {
            return conn
        }
        return activeConnections.values.first
    }

    private func accept(_ connection: NWConnection) {
        let peer = endpointLabel(connection.endpoint)
        lastPeer = peer
        addLog("Accepted connection from \(peer)")

        let key = ObjectIdentifier(connection)
        activeConnections[key] = connection
        currentConnectionKey = key

        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            guard let self, let connection else { return }

            Task { @MainActor in
                switch newState {
                case .setup:
                    self.addLog("Peer setup: \(peer)")

                case .preparing:
                    self.addLog("Peer preparing: \(peer)")

                case .ready:
                    self.currentConnectionKey = key
                    self.lastPeer = peer
                    self.addLog("Peer ready: \(peer)")
                    self.flushPendingIfPossible(on: connection)
                    self.receiveNext(on: connection)

                case .waiting(let error):
                    self.lastErrorText = error.localizedDescription
                    self.addLog("Peer waiting (\(peer)): \(error.localizedDescription)")

                case .failed(let error):
                    self.lastErrorText = error.localizedDescription
                    self.addLog("Peer failed (\(peer)): \(error.localizedDescription)")
                    self.activeConnections.removeValue(forKey: key)
                    if self.currentConnectionKey == key {
                        self.currentConnectionKey = self.activeConnections.keys.first
                    }
                    if self.activeConnections.isEmpty {
                        self.lastPeer = "—"
                    }

                case .cancelled:
                    self.addLog("Peer cancelled: \(peer)")
                    self.activeConnections.removeValue(forKey: key)
                    if self.currentConnectionKey == key {
                        self.currentConnectionKey = self.activeConnections.keys.first
                    }
                    if self.activeConnections.isEmpty {
                        self.lastPeer = "—"
                    }

                @unknown default:
                    self.addLog("Peer unknown state: \(peer)")
                }
            }
        }

        connection.start(queue: queue)
    }

    private func flushPendingIfPossible(on connection: NWConnection) {
        guard let pending = pendingRawText else { return }
        addLog("Flushing queued TX: \(pending)")
        pendingRawText = nil
        pendingQueuedAt = nil
        write(pending, over: connection)
    }

    private func write(_ trimmed: String, over connection: NWConnection) {
        let payload = Data(trimmed.utf8)
        lastSentText = trimmed
        lastSentAt = Date()
        lastErrorText = nil
        addLog("TX: \(trimmed)")
        addLog("TX hex: \(payload.hexString)")

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.lastErrorText = error.localizedDescription
                    self.addLog("TX failed: \(error.localizedDescription)")

                    if self.pendingRawText == nil {
                        self.pendingRawText = trimmed
                        self.pendingQueuedAt = Date()
                        self.addLog("Re-queued TX after failure: \(trimmed)")
                    }
                } else {
                    self.addLog("TX ok (\(payload.count) bytes)")
                }
            }
        })
    }

    private func receiveNext(on connection: NWConnection) {
        let key = ObjectIdentifier(connection)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            Task { @MainActor in
                if let error {
                    self.lastErrorText = error.localizedDescription
                    self.addLog("RX failed: \(error.localizedDescription)")
                    self.activeConnections.removeValue(forKey: key)
                    if self.currentConnectionKey == key {
                        self.currentConnectionKey = self.activeConnections.keys.first
                    }
                    if self.activeConnections.isEmpty {
                        self.lastPeer = "—"
                    }
                    return
                }

                if let data, !data.isEmpty {
                    self.currentConnectionKey = key
                    self.handleIncomingData(data)
                }

                if isComplete {
                    self.addLog("Peer closed")
                    self.activeConnections.removeValue(forKey: key)
                    if self.currentConnectionKey == key {
                        self.currentConnectionKey = self.activeConnections.keys.first
                    }
                    if self.activeConnections.isEmpty {
                        self.lastPeer = "—"
                    }
                    return
                }

                self.receiveNext(on: connection)
            }
        }
    }

    private func handleIncomingData(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            lastMessageText = trimmed
            addLog("RX: \(trimmed)")
        } else {
            lastMessageText = data.hexString
            addLog("RX bytes: \(data.count)")
        }

        addLog("RX hex: \(data.hexString)")

        let packets = extractPackets(from: text)
        if packets.isEmpty, !trimmed.isEmpty {
            packetSubject.send(trimmed)
            decodePacket(trimmed)
        } else {
            for packet in packets {
                lastPacket = packet
                packetSubject.send(packet)
                decodePacket(packet)
            }
        }
    }

    private func extractPackets(from text: String) -> [String] {
        var packets: [String] = []
        var current = ""
        var inside = false

        for ch in text {
            if ch == "<" {
                current = "<"
                inside = true
            } else if ch == ">" && inside {
                current.append(">")
                packets.append(current)
                current = ""
                inside = false
            } else if inside {
                current.append(ch)
            }
        }

        return packets
    }

    private func decodePacket(_ packet: String) {
        let raw = packet
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

        guard !raw.isEmpty else { return }

        if raw == "KA" {
            lastKeepAliveAt = Date()
            addLog("Decoded keepalive")
            return
        }

        if let plainDose = decodePlainDose(raw) {
            lastPlainDoseML = plainDose
            lastTriggerDoseML = plainDose
            lastTriggerAt = Date()
            addLog("Decoded plain dose: \(formatDose(plainDose)) mL")
            triggerDoseSubject.send(plainDose)
            return
        }

        if let structuredDose = decodeStructuredDose(raw) {
            lastStructuredDoseML = structuredDose
            lastTriggerDoseML = structuredDose
            lastTriggerAt = Date()
            addLog("Decoded structured dose: \(formatDose(structuredDose)) mL")
            triggerDoseSubject.send(structuredDose)
            return
        }
    }

    private func decodePlainDose(_ raw: String) -> Double? {
        guard raw.allSatisfy(\.isNumber) else { return nil }
        guard let tenths = Int(raw) else { return nil }
        return Double(tenths) / 10.0
    }

    private func decodeStructuredDose(_ raw: String) -> Double? {
        // Expected shape: R04 + digitCount(2) + value
        guard raw.hasPrefix("R04") else { return nil }

        let remainder = String(raw.dropFirst(3))
        guard remainder.count >= 2 else { return nil }

        let digitCountString = String(remainder.prefix(2))
        let valueString = String(remainder.dropFirst(2))

        guard let digitCount = Int(digitCountString), digitCount > 0 else { return nil }
        guard valueString.count == digitCount else {
            addLog("Structured decode skipped: expected \(digitCount) digits, got \(valueString.count)")
            return nil
        }
        guard valueString.allSatisfy(\.isNumber) else { return nil }
        guard let tenths = Int(valueString) else { return nil }

        return Double(tenths) / 10.0
    }

    private func endpointLabel(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return endpoint.debugDescription
        }
    }

    private func formatDose(_ dose: Double) -> String {
        if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", dose)
        } else if (dose * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", dose)
        } else {
            return String(format: "%.2f", dose)
        }
    }

    private func addLog(_ message: String) {
        log.append(.init(timestamp: Date(), message: message))
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
