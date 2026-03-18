import Foundation
import Network

final class TCPTransport: TransportProtocol {

    // =========================================================
    // MARK: - Public knobs (set by TransportManager / Diagnostics)
    // =========================================================

    /// If the scale requires “Request Required”, enable polling.
    var requestModeEnabled: Bool = true {
        didSet { queue.async { [weak self] in self?.restartPollingIfNeeded() } }
    }

    /// Poll interval seconds.
    var pollInterval: TimeInterval = 1.0 {
        didSet {
            let clamped = max(0.05, min(pollInterval, 10.0))
            if clamped != pollInterval { pollInterval = clamped; return }
            queue.async { [weak self] in self?.restartPollingIfNeeded() }
        }
    }

    /// How we poll/request data from the device.
    enum RequestFormat: String, CaseIterable, Identifiable {
        case asciiAngleC1      // "<C1>" + lineEnding
        case binaryC1          // 0xC1 + lineEnding
        case asciiE21          // "<E21>" + lineEnding
        case customASCII       // customASCIICommand + lineEnding

        var id: String { rawValue }

        var label: String {
            switch self {
            case .asciiAngleC1: return #"ASCII "<C1>""#
            case .binaryC1: return "Binary 0xC1"
            case .asciiE21: return #"ASCII "<E21>""#
            case .customASCII: return "Custom ASCII"
            }
        }
    }

    var requestFormat: RequestFormat = .asciiAngleC1 {
        didSet { queue.async { [weak self] in self?.restartPollingIfNeeded() } }
    }

    /// Used when requestFormat == .customASCII
    var customASCIICommand: String = "<C1>" {
        didSet { queue.async { [weak self] in self?.restartPollingIfNeeded() } }
    }

    /// Line ending appended to ASCII polls / manual ASCII sends.
    enum LineEnding: String, CaseIterable, Identifiable {
        case none
        case cr
        case lf
        case crlf

        var id: String { rawValue }

        var bytes: [UInt8] {
            switch self {
            case .none: return []
            case .cr: return [0x0D]
            case .lf: return [0x0A]
            case .crlf: return [0x0D, 0x0A]
            }
        }

        var label: String {
            switch self {
            case .none: return "None"
            case .cr: return "CR"
            case .lf: return "LF"
            case .crlf: return "CRLF"
            }
        }
    }

    var pollLineEnding: LineEnding = .crlf {
        didSet { queue.async { [weak self] in self?.restartPollingIfNeeded() } }
    }

    // --- Keepalive (benign; separate from polling) ---

    var keepAliveEnabled: Bool = true {
        didSet { queue.async { [weak self] in self?.restartKeepAliveIfNeeded() } }
    }

    var keepAliveInterval: TimeInterval = 5.0 {
        didSet {
            let clamped = max(1.0, min(keepAliveInterval, 30.0))
            if clamped != keepAliveInterval { keepAliveInterval = clamped; return }
            queue.async { [weak self] in self?.restartKeepAliveIfNeeded() }
        }
    }

    // --- Burst/probe behaviour after connect ---

    /// Try multiple poll variants briefly after connect (helps unknown devices).
    var burstBothPollVariantsOnConnect: Bool = true

    /// How many polling ticks we “burst” variants for after connect.
    var burstTicksAfterConnect: Int = 6 {
        didSet { burstTicksAfterConnect = max(0, min(burstTicksAfterConnect, 30)) }
    }

    // --- Framing / “no line ending” rescue ---

    enum FramingMode: String, CaseIterable, Identifiable {
        case terminatorOnly     // only emit when CR/LF/CRLF is found
        case idleGap            // if bytes stop for idleGapMs, flush buffer as a frame

        var id: String { rawValue }

        var label: String {
            switch self {
            case .terminatorOnly: return "Terminator only"
            case .idleGap: return "Idle-gap flush"
            }
        }
    }

    /// ✅ Now live-updatable while connected.
    var framingMode: FramingMode = .idleGap {
        didSet {
            queue.async { [weak self] in
                guard let self else { return }
                self.applyFramingModeToLiveConnection()
            }
        }
    }

    /// When framingMode == .idleGap and no terminator arrives, flush if we haven't received bytes for this long.
    var idleGapMs: Int = 120 {
        didSet {
            idleGapMs = max(20, min(idleGapMs, 2000))
            queue.async { [weak self] in
                guard let self else { return }
                // timer tick reads idleGapMs, so no restart required, but ensure timer exists if needed
                self.applyFramingModeToLiveConnection()
            }
        }
    }

    // --- EID rescue sniffing ---

    /// If true, we scan incoming bytes for 12–18 digit runs and emit `EID: <digits>` even without terminators.
    var eidSniffingEnabled: Bool = true

    /// Minimum digits to consider as “likely EID” during sniffing.
    var eidSniffMinDigits: Int = 12 {
        didSet { eidSniffMinDigits = max(8, min(eidSniffMinDigits, 20)) }
    }

    /// Maximum digits to consider as “likely EID” during sniffing.
    var eidSniffMaxDigits: Int = 18 {
        didSet { eidSniffMaxDigits = max(eidSniffMinDigits, min(eidSniffMaxDigits, 32)) }
    }

    // =========================================================
    // MARK: - ZERO / TARE
    // =========================================================

    /// Te Pari ZERO/TARE command is device-specific.
    /// We default to "<Z>" because many controllers use it, but you can override by calling
    /// `sendZeroTareASCII("<YOURCMD>")` from TransportManager.
    static let defaultZeroTareASCII: String = "<Z>"

    // =========================================================
    // MARK: - Core config
    // =========================================================

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port

    // =========================================================
    // MARK: - State
    // =========================================================

    private var connection: NWConnection?
    private var buffer = Data()

    private let queue = DispatchQueue(label: "TCPTransport.queue", qos: .userInitiated)

    private var keepAliveTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?
    private var idleFlushTimer: DispatchSourceTimer?

    private var connectionToken = UUID()

    /// Used to suppress the next `.disconnected` emission when we intentionally tear down.
    private var suppressNextDisconnectedEvent = false

    // Debug throttle (so Raw Log doesn’t flood)
    private var lastDebugAt: Date?
    private var connectPollBurstCount = 0

    // For idle-gap flush
    private var lastByteAt: Date?

    // For EID sniff spam control
    private var lastEmittedEID: String?
    private var lastEIDEmitAt: Date?

    // =========================================================
    // MARK: - Callbacks
    // =========================================================

    var onReceiveLine: ((String) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?

    var isConnected: Bool {
        if let c = connection, case .ready = c.state { return true }
        return false
    }

    // =========================================================
    // MARK: - Init
    // =========================================================

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        if let p = NWEndpoint.Port(rawValue: port) {
            self.port = p
        } else {
            self.port = 2000
        }
    }

    // =========================================================
    // MARK: - Connect / Disconnect
    // =========================================================

    func connect() {
        // We are intentionally cycling the connection → do not emit a transient disconnected.
        suppressNextDisconnectedEvent = true
        disconnect()

        emitState(.connecting)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        let token = UUID()
        connectionToken = token
        connectPollBurstCount = 0
        lastDebugAt = nil
        lastByteAt = nil
        lastEmittedEID = nil
        lastEIDEmitAt = nil

        let conn = NWConnection(host: host, port: port, using: parameters)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            guard token == self.connectionToken else { return }

            switch state {
            case .ready:
                self.emitState(.connected)
                self.startReceiveLoop(token: token)

                if self.keepAliveEnabled {
                    self.startKeepAlive(token: token)
                }

                self.applyFramingModeToLiveConnection()

                if self.requestModeEnabled {
                    // Give the socket a moment to settle.
                    self.startPolling(token: token, delay: 1.0)
                }

            case .waiting:
                self.emitState(.reconnecting)

            case .failed(let err):
                // ✅ Keep the error visible (don’t immediately overwrite it with disconnected).
                self.emitState(.error(err.localizedDescription))
                self.teardownWithoutEmittingDisconnected()

            case .cancelled:
                self.emitState(.disconnected)

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    func disconnect() {
        teardown(emitDisconnected: true)
    }

    /// Internal teardown helper (optionally suppress `.disconnected` emission).
    private func teardown(emitDisconnected: Bool) {
        if !emitDisconnected {
            suppressNextDisconnectedEvent = true
        }

        stopKeepAlive()
        stopPolling()
        stopIdleFlushTimer()

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        buffer.removeAll(keepingCapacity: true)
        lastByteAt = nil

        if suppressNextDisconnectedEvent {
            suppressNextDisconnectedEvent = false
        } else {
            emitState(.disconnected)
        }
    }

    /// Use this when we just emitted `.error(...)` and want it to persist.
    private func teardownWithoutEmittingDisconnected() {
        teardown(emitDisconnected: false)
    }

    // =========================================================
    // MARK: - Public Send (TransportManager / Diagnostics)
    // =========================================================

    /// ✅ This is what TransportManager / Diagnostics call.
    func sendRaw(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let c = self.connection else { return }
            guard !data.isEmpty else { return }
            c.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    /// Convenience: send ASCII with optional terminator.
    func sendASCII(_ command: String, appendLineEnding: Bool = true) {
        var d = Data(command.utf8)
        if appendLineEnding {
            d.append(contentsOf: pollLineEnding.bytes)
        }
        sendRaw(d)
    }

    /// ZERO/TARE helper (ASCII). Uses `pollLineEnding` for terminator.
    func sendZeroTareASCII(_ command: String = TCPTransport.defaultZeroTareASCII) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendASCII(trimmed, appendLineEnding: true)
    }

    /// One-shot probe burst (useful if EID isn’t coming through).
    /// Sends: <C1>, <E21>, 0xC1 (each with current line ending), plus CR-only.
    func sendProbeSequence() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let c = self.connection else { return }

            func send(_ data: Data) {
                guard !data.isEmpty else { return }
                c.send(content: data, completion: .contentProcessed { _ in })
            }

            var a = Data("<C1>".utf8); a.append(contentsOf: self.pollLineEnding.bytes)
            var b = Data("<E21>".utf8); b.append(contentsOf: self.pollLineEnding.bytes)
            var c1 = Data([0xC1]); c1.append(contentsOf: self.pollLineEnding.bytes)

            send(a)
            send(b)
            send(c1)
            send(Data([0x0D])) // CR-only
        }
    }

    // =========================================================
    // MARK: - Receive loop
    // =========================================================

    private func startReceiveLoop(token: UUID) {
        receiveLoop(token: token)
    }

    private func receiveLoop(token: UUID) {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard token == self.connectionToken else { return }

            if let data, !data.isEmpty {
                self.lastByteAt = Date()
                self.buffer.append(data)

                // ✅ EID “rescue” sniffing (works even with no terminators)
                if self.eidSniffingEnabled {
                    self.sniffAndEmitEIDCandidates()
                }

                // Try to drain normal lines.
                self.drainFramesOrDebug()
            }

            if let error {
                // ✅ Keep the error visible (don’t overwrite with disconnected).
                self.emitState(.error(error.localizedDescription))
                self.teardownWithoutEmittingDisconnected()
                return
            }

            if isComplete {
                // Remote closed. This is a real disconnect.
                self.emitState(.disconnected)
                self.teardown(emitDisconnected: false) // already emitted disconnected above
                return
            }

            self.receiveLoop(token: token)
        }
    }

    // =========================================================
    // MARK: - Framing (CRLF / LF / CR tolerant + idle-gap flush)
    // =========================================================

    private func drainFramesOrDebug() {
        var emittedAnyLine = false

        while true {
            guard let term = findLineTerminator(in: buffer) else { break }

            let lineData = buffer.subdata(in: 0..<term.lowerBound)
            buffer.removeSubrange(0..<term.upperBound)

            let line = decodeLine(lineData)
            if !line.isEmpty {
                emittedAnyLine = true
                emitLine(line)
            }
        }

        // If bytes are arriving but we can't find a terminator yet, prove it with debug.
        if !emittedAnyLine, buffer.count > 0 {
            emitBufferedDebugIfNeeded()
        }
    }

    private func decodeLine(_ lineData: Data) -> String {
        var line = String(data: lineData, encoding: .utf8) ?? ""
        line = line.trimmingCharacters(in: .newlines)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }

    private func findLineTerminator(in data: Data) -> Range<Int>? {
        // Prefer CRLF, then LF, then CR
        if let r = data.firstRange(of: Data([0x0D, 0x0A])) { return r } // \r\n
        if let r = data.firstRange(of: Data([0x0A])) { return r }       // \n
        if let r = data.firstRange(of: Data([0x0D])) { return r }       // \r
        return nil
    }

    private func applyFramingModeToLiveConnection() {
        guard isConnected else {
            stopIdleFlushTimer()
            return
        }

        switch framingMode {
        case .idleGap:
            if idleFlushTimer == nil {
                startIdleFlushTimer(token: connectionToken)
            }
        case .terminatorOnly:
            stopIdleFlushTimer()
        }
    }

    private func startIdleFlushTimer(token: UUID) {
        stopIdleFlushTimer()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: 0.05)

        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard token == self.connectionToken else { return }
            self.idleFlushTick()
        }

        idleFlushTimer = t
        t.resume()
    }

    private func stopIdleFlushTimer() {
        idleFlushTimer?.cancel()
        idleFlushTimer = nil
    }

    private func idleFlushTick() {
        guard framingMode == .idleGap else { return }
        guard !buffer.isEmpty else { return }
        guard let last = lastByteAt else { return }

        let gap = Date().timeIntervalSince(last)
        if gap < Double(idleGapMs) / 1000.0 { return }

        // If we have no terminator but things went quiet, flush buffer as a “frame”.
        let frame = buffer
        buffer.removeAll(keepingCapacity: true)

        let s = decodeLine(frame)
        if !s.isEmpty {
            emitLine(s)
        } else {
            // If it's not valid UTF-8, log a short hex preview.
            let preview = frame.prefix(64)
            let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
            emitLine("[DBG-FRAME] Flushed \(frame.count) bytes (non-UTF8). Preview(hex): \(hex)")
        }
    }

    private func emitBufferedDebugIfNeeded() {
        let now = Date()
        let shouldEmit: Bool
        if let last = lastDebugAt {
            shouldEmit = now.timeIntervalSince(last) >= 1.0
        } else {
            shouldEmit = true
        }

        if shouldEmit {
            lastDebugAt = now
            let preview = buffer.prefix(32)
            let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
            emitLine("[DBG-RX] \(buffer.count) bytes buffered (no line ending yet). Preview(hex): \(hex)")
        }
    }

    // =========================================================
    // MARK: - EID sniffing (digits rescue)
    // =========================================================

    private func sniffAndEmitEIDCandidates() {
        // Convert buffer to ASCII-ish string; non-digit bytes become separators.
        let ascii = buffer.map { b -> Character in
            if b >= 48 && b <= 57 { return Character(UnicodeScalar(b)) } // 0-9
            return " "
        }
        let s = String(ascii)

        // Find digit runs.
        var current = ""
        var candidates: [String] = []

        for ch in s {
            if ch >= "0" && ch <= "9" {
                current.append(ch)
                if current.count > eidSniffMaxDigits {
                    current.removeFirst(current.count - eidSniffMaxDigits)
                }
            } else {
                if current.count >= eidSniffMinDigits && current.count <= eidSniffMaxDigits {
                    candidates.append(current)
                }
                current.removeAll(keepingCapacity: true)
            }
        }

        if current.count >= eidSniffMinDigits && current.count <= eidSniffMaxDigits {
            candidates.append(current)
        }

        guard let best = candidates.last else { return }

        // Throttle repeats.
        if best == lastEmittedEID {
            if let t = lastEIDEmitAt, Date().timeIntervalSince(t) < 2.0 { return }
        }

        lastEmittedEID = best
        lastEIDEmitAt = Date()

        emitLine("EID: \(best)")
    }

    // =========================================================
    // MARK: - Keepalive (benign)
    // =========================================================

    private func startKeepAlive(token: UUID) {
        stopKeepAlive()

        let interval = max(1.0, keepAliveInterval)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard token == self.connectionToken else { return }
            guard let c = self.connection else { return }

            // harmless empty line (parser ignores)
            let payload = Data([0x0D, 0x0A])
            c.send(content: payload, completion: .contentProcessed { _ in })
        }

        keepAliveTimer = t
        t.resume()
    }

    private func stopKeepAlive() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    private func restartKeepAliveIfNeeded() {
        guard isConnected else { return }
        let token = connectionToken
        if keepAliveEnabled {
            startKeepAlive(token: token)
        } else {
            stopKeepAlive()
        }
    }

    // =========================================================
    // MARK: - Polling / Request Mode
    // =========================================================

    private func startPolling(token: UUID, delay: TimeInterval) {
        stopPolling()
        guard requestModeEnabled else { return }

        let interval = max(0.05, pollInterval)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + delay, repeating: interval)

        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard token == self.connectionToken else { return }
            self.sendPollCommand()
        }

        pollTimer = t
        t.resume()
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func restartPollingIfNeeded() {
        guard isConnected else { return }
        let token = connectionToken
        if requestModeEnabled {
            startPolling(token: token, delay: 0.2)
        } else {
            stopPolling()
        }
    }

    private func sendPollCommand() {
        guard let c = connection else { return }

        if burstBothPollVariantsOnConnect && connectPollBurstCount < burstTicksAfterConnect {
            connectPollBurstCount += 1

            var a = Data("<C1>".utf8)
            a.append(contentsOf: pollLineEnding.bytes)
            c.send(content: a, completion: .contentProcessed { _ in })

            var b = Data([0xC1])
            b.append(contentsOf: pollLineEnding.bytes)
            c.send(content: b, completion: .contentProcessed { _ in })

            var e = Data("<E21>".utf8)
            e.append(contentsOf: pollLineEnding.bytes)
            c.send(content: e, completion: .contentProcessed { _ in })

            c.send(content: Data([0x0D]), completion: .contentProcessed { _ in })
            return
        }

        let payload = makePollPayload()
        guard !payload.isEmpty else { return }
        c.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func makePollPayload() -> Data {
        switch requestFormat {
        case .asciiAngleC1:
            var d = Data("<C1>".utf8)
            d.append(contentsOf: pollLineEnding.bytes)
            return d

        case .asciiE21:
            var d = Data("<E21>".utf8)
            d.append(contentsOf: pollLineEnding.bytes)
            return d

        case .customASCII:
            var d = Data(customASCIICommand.utf8)
            d.append(contentsOf: pollLineEnding.bytes)
            return d

        case .binaryC1:
            var d = Data([0xC1])
            d.append(contentsOf: pollLineEnding.bytes)
            return d
        }
    }

    // =========================================================
    // MARK: - Helpers
    // =========================================================

    private func emitLine(_ line: String) {
        DispatchQueue.main.async { [onReceiveLine] in
            onReceiveLine?(line)
        }
    }

    private func emitState(_ state: ConnectionState) {
        DispatchQueue.main.async { [onStateChange] in
            onStateChange?(state)
        }
    }
}

// =========================================================
// MARK: - Data helper
// =========================================================

private extension Data {
    func firstRange(of needle: Data) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= self.count else { return nil }

        return self.withUnsafeBytes { (hayPtr: UnsafeRawBufferPointer) -> Range<Int>? in
            needle.withUnsafeBytes { (neePtr: UnsafeRawBufferPointer) -> Range<Int>? in
                let hay = hayPtr.bindMemory(to: UInt8.self)
                let nee = neePtr.bindMemory(to: UInt8.self)

                guard let hBase = hay.baseAddress, let nBase = nee.baseAddress else { return nil }
                let hCount = hay.count
                let nCount = nee.count

                if nCount == 1 {
                    let byte = nBase.pointee
                    for i in 0..<hCount where hBase.advanced(by: i).pointee == byte {
                        return i..<(i + 1)
                    }
                    return nil
                }

                for i in 0...(hCount - nCount) {
                    var match = true
                    for j in 0..<nCount {
                        if hBase.advanced(by: i + j).pointee != nBase.advanced(by: j).pointee {
                            match = false
                            break
                        }
                    }
                    if match { return i..<(i + nCount) }
                }
                return nil
            }
        }
    }
}
