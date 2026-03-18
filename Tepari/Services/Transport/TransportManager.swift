import Foundation
import Combine

@MainActor
final class TransportManager: ObservableObject {

    // =========================================================
    // MARK: - Method (LEGACY)
    // =========================================================

    enum Method: CaseIterable, Identifiable, Hashable {
        case demo
        case tcp
        case ble

        var id: Method { self }

        var label: String {
            switch self {
            case .demo: return "Demo"
            case .tcp:  return "Wi-Fi (TCP)"
            case .ble:  return "Bluetooth (BLE)"
            }
        }
    }

    @Published var method: Method = .demo {
        didSet {
            if oldValue == .tcp, method != .tcp {
                disconnect(shouldLog: true)
            }
        }
    }

    /// Convenience: what most users actually want for T1.
    func useT1Defaults() {
        method = .tcp
        host = "t1.local"
        port = 2000

        requestModeEnabled = false
        keepAliveEnabled = false
        burstBothPollVariantsOnConnect = false

        // Reconnects automatically if ESP32/socket goes quiet
        watchdogEnabled = true
        watchdogSilenceSeconds = 15

        framingMode = .idleGap
        idleGapMs = 40

        appendLog("[INFO] Using T1 defaults: Wi-Fi (TCP) t1.local:2000")
    }

    private func useT1DefaultsIfNeeded() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        let needsDefaults =
            method != .tcp ||
            trimmedHost.isEmpty ||
            trimmedHost == "localhost" ||
            port == 0

        guard needsDefaults else { return }

        useT1Defaults()
    }

    // =========================================================
    // MARK: - TCP Target
    // =========================================================

    @Published var host: String = "t1.local"
    @Published var port: UInt16 = 2000

    // =========================================================
    // MARK: - TCP Live Settings
    // =========================================================

    @Published var requestModeEnabled: Bool = false { didSet { scheduleApplyTCPSettings() } }

    @Published var pollIntervalSeconds: Double = 1.0 {
        didSet {
            let clamped = max(0.05, min(pollIntervalSeconds, 10.0))
            if pollIntervalSeconds != clamped {
                pollIntervalSeconds = clamped
                return
            }
            scheduleApplyTCPSettings()
        }
    }

    @Published var requestFormat: TCPTransport.RequestFormat = .asciiAngleC1 { didSet { scheduleApplyTCPSettings() } }
    @Published var customASCIICommand: String = "<C1>" { didSet { scheduleApplyTCPSettings() } }
    @Published var pollLineEnding: TCPTransport.LineEnding = .crlf { didSet { scheduleApplyTCPSettings() } }

    @Published var keepAliveEnabled: Bool = false { didSet { scheduleApplyTCPSettings() } }

    @Published var keepAliveIntervalSeconds: Double = 5.0 {
        didSet {
            let clamped = max(1.0, min(keepAliveIntervalSeconds, 30.0))
            if keepAliveIntervalSeconds != clamped {
                keepAliveIntervalSeconds = clamped
                return
            }
            scheduleApplyTCPSettings()
        }
    }

    @Published var burstBothPollVariantsOnConnect: Bool = false { didSet { scheduleApplyTCPSettings() } }

    @Published var burstTicksAfterConnect: Int = 6 {
        didSet {
            let clamped = max(0, min(burstTicksAfterConnect, 30))
            if burstTicksAfterConnect != clamped {
                burstTicksAfterConnect = clamped
                return
            }
            scheduleApplyTCPSettings()
        }
    }

    @Published var framingMode: TCPTransport.FramingMode = .idleGap { didSet { scheduleApplyTCPSettings() } }

    @Published var idleGapMs: Int = 40 {
        didSet {
            let clamped = max(20, min(idleGapMs, 2000))
            if idleGapMs != clamped {
                idleGapMs = clamped
                return
            }
            scheduleApplyTCPSettings()
        }
    }

    @Published var eidSniffingEnabled: Bool = true { didSet { scheduleApplyTCPSettings() } }

    @Published var eidSniffMinDigits: Int = 12 {
        didSet {
            let clamped = max(8, min(eidSniffMinDigits, 20))
            if eidSniffMinDigits != clamped {
                eidSniffMinDigits = clamped
                return
            }
            if eidSniffMaxDigits < eidSniffMinDigits {
                eidSniffMaxDigits = eidSniffMinDigits
            }
            scheduleApplyTCPSettings()
        }
    }

    @Published var eidSniffMaxDigits: Int = 18 {
        didSet {
            let clamped = max(eidSniffMinDigits, min(eidSniffMaxDigits, 32))
            if eidSniffMaxDigits != clamped {
                eidSniffMaxDigits = clamped
                return
            }
            scheduleApplyTCPSettings()
        }
    }

    // =========================================================
    // MARK: - ZERO / TARE
    // =========================================================

    @Published var zeroTareASCIICommand: String = TCPTransport.defaultZeroTareASCII

    // =========================================================
    // MARK: - State
    // =========================================================

    @Published private(set) var state: ConnectionState = .disconnected

    @Published private(set) var log: [RawLogEntry] = []
    @Published var logLimit: Int = 500

    var onReceiveLine: ((String) -> Void)?

    private var transport: TransportProtocol?
    private var sessionToken = UUID()
    private var autoReconnectTask: Task<Void, Never>?
    private var lastAutoConnectAttemptAt: Date?

    // =========================================================
    // MARK: - Watchdog (TCP only)
    // =========================================================

    @Published var watchdogEnabled: Bool = true
    @Published var watchdogSilenceSeconds: Double = 15 {
        didSet {
            let clamped = max(2, min(watchdogSilenceSeconds, 120))
            if watchdogSilenceSeconds != clamped {
                watchdogSilenceSeconds = clamped
            }
        }
    }
    private var lastReceiveAt: Date?
    private var hasEverReceivedLine: Bool = false
    private var watchdogTimer: Timer?

    // =========================================================
    // MARK: - Diagnostics / Metrics
    // =========================================================

    @Published private(set) var reconnectCount: Int = 0
    @Published private(set) var watchdogTriggerCount: Int = 0

    @Published private(set) var totalBytes: Int = 0
    @Published private(set) var totalLines: Int = 0

    @Published private(set) var bytesPerSecond: Double = 0
    @Published private(set) var linesPerSecond: Double = 0

    private var connectionStartedAt: Date?
    private var metricsTimer: Timer?

    private var rateWindowStart: Date?
    private var rateWindowBytes: Int = 0
    private var rateWindowLines: Int = 0

    // =========================================================
    // MARK: - Debounced settings apply
    // =========================================================

    private var applySettingsTask: Task<Void, Never>?

    private func scheduleApplyTCPSettings() {
        guard method == .tcp else { return }
        guard transport is TCPTransport else { return }

        applySettingsTask?.cancel()

        applySettingsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.applyTCPSettingsToLiveTransport()
        }
    }

    // =========================================================
    // MARK: - Public API
    // =========================================================

    func ensureT1Connected() {
        useT1DefaultsIfNeeded()

        guard method == .tcp else { return }

        switch state {
        case .connected, .connecting, .reconnecting:
            return
        case .disconnected, .scanning, .error:
            break
        }

        let now = Date()
        if let last = lastAutoConnectAttemptAt, now.timeIntervalSince(last) < 1.5 {
            return
        }
        lastAutoConnectAttemptAt = now

        appendLog("[AUTO] Ensuring T1 connection")
        connect()
    }

    func appBecameActive() {
        ensureT1Connected()
    }

    func connect() {
        autoReconnectTask?.cancel()
        autoReconnectTask = nil

        switch state {
        case .connecting, .reconnecting, .connected:
            return
        default:
            break
        }

        disconnect(shouldLog: false)

        sessionToken = UUID()
        let token = sessionToken

        lastReceiveAt = nil
        hasEverReceivedLine = false
        connectionStartedAt = nil
        rateWindowStart = Date()
        rateWindowBytes = 0
        rateWindowLines = 0

        startWatchdogIfNeeded()
        startMetricsTimerIfNeeded()

        switch method {
        case .demo:
            state = .connected
            appendLog("[DEMO] Connected")
            connectionStartedAt = Date()
            return

        case .tcp:
            if port == 80 {
                let t = T1HTTPTransport(host: host, port: port)
                hook(t, token: token)
                transport = t

                appendLog("[INFO] Connecting T1 HTTP to \(host):\(port)")
                t.connect()
            } else {
                let t = TCPTransport(host: host, port: port)
                configureTCPTransport(t)
                hook(t, token: token)
                transport = t

                appendLog("[INFO] Connecting TCP to \(host):\(port)")
                t.connect()
            }

        case .ble:
            let t = BLETransport()
            hook(t, token: token)
            transport = t

            appendLog("[INFO] Connecting BLE")
            t.connect()
        }
    }

    func disconnect(shouldLog: Bool = true) {
        sessionToken = UUID()

        autoReconnectTask?.cancel()
        autoReconnectTask = nil

        applySettingsTask?.cancel()
        applySettingsTask = nil

        stopWatchdog()
        stopMetricsTimer()

        transport?.disconnect()
        transport = nil

        lastReceiveAt = nil
        hasEverReceivedLine = false
        connectionStartedAt = nil

        bytesPerSecond = 0
        linesPerSecond = 0

        if method != .demo {
            state = .disconnected
        }

        if shouldLog {
            appendLog("[INFO] Disconnected")
        }
    }

    func clearLog() {
        log.removeAll()
    }

    func appendLog(_ line: String) {
        log.append(RawLogEntry(timestamp: Date(), line: line))
        if log.count > logLimit {
            log.removeFirst(max(0, log.count - logLimit))
        }
    }

    // =========================================================
    // MARK: - ZERO / TARE
    // =========================================================

    func sendZeroCommand() {
        switch method {
        case .demo:
            appendLog("[DEMO] ZERO/TARE")
            return

        case .tcp:
            guard let t = transport as? TCPTransport else {
                appendLog("[WARN] ZERO/TARE ignored (no TCP transport)")
                return
            }

            let cmd = zeroTareASCIICommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else {
                appendLog("[WARN] ZERO/TARE command is empty")
                return
            }

            appendLog("[TX-ZERO] \(cmd)")
            t.sendZeroTareASCII(cmd)

        case .ble:
            appendLog("[WARN] ZERO/TARE not supported on BLE yet")
            return
        }
    }

    // =========================================================
    // MARK: - Diagnostics helpers
    // =========================================================

    var connectionUptimeString: String {
        guard let start = connectionStartedAt, state == .connected || state == .reconnecting else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        return formatSeconds(s)
    }

    var lastReceiveString: String {
        guard let lastReceiveAt else { return "—" }
        return formatRelativeSeconds(Int(Date().timeIntervalSince(lastReceiveAt))) + " ago"
    }

    var silenceDurationString: String {
        guard let lastReceiveAt else { return "—" }
        let s = Int(Date().timeIntervalSince(lastReceiveAt))
        return formatSeconds(s)
    }

    var bytesPerSecondString: String {
        bytesPerSecond < 0.05 ? "0" : String(format: "%.1f", bytesPerSecond)
    }

    var linesPerSecondString: String {
        linesPerSecond < 0.05 ? "0" : String(format: "%.1f", linesPerSecond)
    }

    var totalBytesString: String {
        formatBytes(totalBytes)
    }

    var pollIntervalString: String { String(format: "%.2fs", pollIntervalSeconds) }

    // =========================================================
    // MARK: - Actions
    // =========================================================

    func forceReconnect() {
        appendLog("[INFO] Force reconnect")
        reconnectCount += 1
        disconnect(shouldLog: false)
        connect()
    }

    private func scheduleAutoReconnect(after seconds: Double = 2.0) {
        guard method == .tcp else { return }

        autoReconnectTask?.cancel()

        autoReconnectTask = Task { [weak self] in
            let delay = UInt64(max(0.5, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }

                switch self.state {
                case .connected, .connecting, .reconnecting:
                    return
                case .disconnected, .scanning, .error:
                    break
                }

                self.appendLog("[AUTO] Reconnect attempt")
                self.connect()
            }
        }
    }

    func resetDiagnostics() {
        appendLog("[INFO] Reset diagnostics")
        reconnectCount = 0
        watchdogTriggerCount = 0
        totalBytes = 0
        totalLines = 0
        bytesPerSecond = 0
        linesPerSecond = 0

        rateWindowStart = Date()
        rateWindowBytes = 0
        rateWindowLines = 0
    }

    func sendManualASCII(_ command: String) {
        guard method == .tcp else { return }
        guard let t = transport as? TCPTransport else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendLog("[TX-ASCII] \(trimmed)")
        t.sendASCII(trimmed, appendLineEnding: true)
    }

    func sendBinaryC1() {
        guard method == .tcp else { return }
        guard let t = transport as? TCPTransport else { return }

        appendLog("[TX] 0xC1 + \(pollLineEnding.label)")
        var d = Data([0xC1])
        d.append(contentsOf: pollLineEnding.bytes)
        t.sendRaw(d)
    }

    func sendProbeSequence() {
        guard method == .tcp else { return }
        guard let t = transport as? TCPTransport else { return }
        appendLog("[TX] Probe sequence")
        t.sendProbeSequence()
    }

    // =========================================================
    // MARK: - Internal: wire callbacks
    // =========================================================

    private func hook(_ t: TransportProtocol, token: UUID) {
        t.onStateChange = { [weak self] s in
            guard let self else { return }
            Task { @MainActor in
                guard token == self.sessionToken else { return }

                self.state = s
                self.appendLog("[STATE] \(s.shortDescription)")

                switch s {
                case .connected:
                    self.connectionStartedAt = Date()
                    self.autoReconnectTask?.cancel()
                    self.autoReconnectTask = nil
                    self.scheduleApplyTCPSettings()

                case .disconnected, .error:
                    self.scheduleAutoReconnect()

                default:
                    break
                }
            }
        }

        t.onReceiveLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in
                guard token == self.sessionToken else { return }

                let bytes = line.utf8.count

                self.hasEverReceivedLine = true
                self.lastReceiveAt = Date()

                self.totalLines += 1
                self.totalBytes += bytes

                self.rateWindowLines += 1
                self.rateWindowBytes += bytes

                self.appendLog(line)
                self.onReceiveLine?(line)
            }
        }
    }

    // =========================================================
    // MARK: - Apply settings to TCPTransport
    // =========================================================

    private func configureTCPTransport(_ t: TCPTransport) {
        t.requestModeEnabled = requestModeEnabled

        let safePoll = max(0.05, min(pollIntervalSeconds, 10.0))
        t.pollInterval = safePoll

        t.requestFormat = requestFormat
        t.customASCIICommand = customASCIICommand
        t.pollLineEnding = pollLineEnding

        t.keepAliveEnabled = keepAliveEnabled
        t.keepAliveInterval = max(1.0, min(keepAliveIntervalSeconds, 30.0))

        t.burstBothPollVariantsOnConnect = burstBothPollVariantsOnConnect
        t.burstTicksAfterConnect = max(0, min(burstTicksAfterConnect, 30))

        t.framingMode = framingMode
        t.idleGapMs = max(20, min(idleGapMs, 2000))

        t.eidSniffingEnabled = eidSniffingEnabled
        t.eidSniffMinDigits = max(8, min(eidSniffMinDigits, 20))
        t.eidSniffMaxDigits = max(t.eidSniffMinDigits, min(eidSniffMaxDigits, 32))
    }

    private func applyTCPSettingsToLiveTransport() {
        guard method == .tcp else { return }
        guard let t = transport as? TCPTransport else { return }
        configureTCPTransport(t)
    }

    // =========================================================
    // MARK: - Watchdog
    // =========================================================

    private func startWatchdogIfNeeded() {
        stopWatchdog()

        guard watchdogEnabled else { return }
        guard method == .tcp else { return }

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.watchdogTick()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard watchdogEnabled else { return }
        guard method == .tcp else { return }
        guard state == .connected || state == .reconnecting else { return }

        let now = Date()
        let last = lastReceiveAt ?? now
        let silence = now.timeIntervalSince(last)

        if silence >= watchdogSilenceSeconds {
            watchdogTriggerCount += 1
            appendLog("[WATCHDOG] Silent for \(Int(silence))s → reconnect")
            reconnectCount += 1
            disconnect(shouldLog: false)
            scheduleAutoReconnect(after: 1.0)
        }
    }

    // =========================================================
    // MARK: - Metrics timer
    // =========================================================

    private func startMetricsTimerIfNeeded() {
        stopMetricsTimer()

        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.metricsTick()
            }
        }
    }

    private func stopMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }

    private func metricsTick() {
        guard let start = rateWindowStart else {
            rateWindowStart = Date()
            return
        }

        let dt = Date().timeIntervalSince(start)
        guard dt >= 0.5 else { return }

        bytesPerSecond = Double(rateWindowBytes) / dt
        linesPerSecond = Double(rateWindowLines) / dt

        rateWindowStart = Date()
        rateWindowBytes = 0
        rateWindowLines = 0
    }
}

// =========================================================
// MARK: - Helpers
// =========================================================

private extension ConnectionState {
    var shortDescription: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

private func formatSeconds(_ s: Int) -> String {
    if s < 60 { return "\(s)s" }
    let m = s / 60
    let r = s % 60
    if m < 60 { return "\(m)m \(r)s" }
    let h = m / 60
    let mr = m % 60
    return "\(h)h \(mr)m"
}

private func formatRelativeSeconds(_ s: Int) -> String {
    if s < 0 { return "0s" }
    return formatSeconds(s)
}

private func formatBytes(_ n: Int) -> String {
    let b = Double(max(0, n))
    if b < 1024 { return "\(n) B" }
    let kb = b / 1024
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024
    if mb < 1024 { return String(format: "%.1f MB", mb) }
    let gb = mb / 1024
    return String(format: "%.2f GB", gb)
}
