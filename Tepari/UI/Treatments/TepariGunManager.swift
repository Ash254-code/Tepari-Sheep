import Foundation
import Combine
import Network

@MainActor
final class TepariGunManager: ObservableObject {

    // =====================================================
    // MARK: - Connection State
    // =====================================================

    enum State: String, Codable, Hashable {
        case disconnected
        case connecting
        case connected
        case error

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .error: return "Error"
            }
        }
    }

    enum ConnectionMode: String, CaseIterable, Codable, Hashable, Identifiable {
        case client
        case listener

        var id: String { rawValue }

        var label: String {
            switch self {
            case .client: return "Connect to Gun"
            case .listener: return "Gun Connects to iPad"
            }
        }
    }

    enum LineEnding: String, CaseIterable, Codable, Hashable, Identifiable {
        case none
        case lf
        case cr
        case crlf

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .lf: return "LF"
            case .cr: return "CR"
            case .crlf: return "CRLF"
            }
        }

        var suffix: String {
            switch self {
            case .none: return ""
            case .lf: return "\n"
            case .cr: return "\r"
            case .crlf: return "\r\n"
            }
        }
    }

    // =====================================================
    // MARK: - Published UI State
    // =====================================================

    @Published private(set) var state: State = .disconnected
    @Published private(set) var isVisible: Bool = false

    @Published var connectionMode: ConnectionMode
    @Published var host: String
    @Published var port: Int

    @Published var lineEnding: LineEnding
    @Published var autoWrapAngleBrackets: Bool
    @Published var reconnectPerCommand: Bool

    @Published private(set) var lastPeerText: String = "—"

    @Published private(set) var lastDoseSent: Double? = nil
    @Published private(set) var lastDoseUnit: DoseUnit? = nil
    @Published private(set) var lastSentAt: Date? = nil

    @Published private(set) var lastCommandText: String? = nil
    @Published private(set) var lastResponseText: String? = nil
    @Published private(set) var lastErrorText: String? = nil

    @Published private(set) var isSending: Bool = false
    @Published private(set) var log: [LogEntry] = []

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    // =====================================================
    // MARK: - Persistence Keys
    // =====================================================

    private let defaults: UserDefaults
    private let hostKey = "tepari.gun.host"
    private let portKey = "tepari.gun.port"
    private let enabledKey = "tepari.gun.enabled"
    private let lineEndingKey = "tepari.gun.lineEnding"
    private let autoWrapAngleBracketsKey = "tepari.gun.autoWrapAngleBrackets"
    private let reconnectPerCommandKey = "tepari.gun.reconnectPerCommand"
    private let connectionModeKey = "tepari.gun.connectionMode"

    // =====================================================
    // MARK: - Network
    // =====================================================

    private var connection: NWConnection?
    private var listener: NWListener?
    private var listenerConnection: NWConnection?

    private let networkQueue = DispatchQueue(label: "tepari.gun.network")

    private var isReceiveLoopActive = false
    private var isListenerReceiveLoopActive = false

    private var availabilityTimer: Timer?
    private var availabilityProbe: NWConnection?

    // queued send for persistent mode
    private var pendingFormattedCommand: String?
    private var pendingTrimmedCommand: String?

    // =====================================================
    // MARK: - Init
    // =====================================================

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults

        let savedHost = userDefaults.string(forKey: hostKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let savedPort = userDefaults.object(forKey: portKey) as? Int

        self.host = (savedHost?.isEmpty == false) ? savedHost! : "192.168.4.80"
        self.port = savedPort ?? 2000

        if let raw = userDefaults.string(forKey: lineEndingKey),
           let saved = LineEnding(rawValue: raw) {
            self.lineEnding = saved
        } else {
            self.lineEnding = .none
        }

        if let raw = userDefaults.string(forKey: connectionModeKey),
           let saved = ConnectionMode(rawValue: raw) {
            self.connectionMode = saved
        } else {
            self.connectionMode = .client
        }

        if userDefaults.object(forKey: autoWrapAngleBracketsKey) == nil {
            self.autoWrapAngleBrackets = true
        } else {
            self.autoWrapAngleBrackets = userDefaults.bool(forKey: autoWrapAngleBracketsKey)
        }

        if userDefaults.object(forKey: reconnectPerCommandKey) == nil {
            self.reconnectPerCommand = true
        } else {
            self.reconnectPerCommand = userDefaults.bool(forKey: reconnectPerCommandKey)
        }

        startAvailabilityMonitor()
    }

    deinit {
        availabilityTimer?.invalidate()
        availabilityProbe?.stateUpdateHandler = nil
        availabilityProbe?.cancel()

        connection?.stateUpdateHandler = nil
        connection?.cancel()

        listenerConnection?.stateUpdateHandler = nil
        listenerConnection?.cancel()

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
    }

    // =====================================================
    // MARK: - Public helpers
    // =====================================================

    var isConnected: Bool {
        state == .connected
    }

    var isConfigured: Bool {
        switch connectionMode {
        case .client:
            return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                port > 0 &&
                port <= 65535
        case .listener:
            return port > 0 && port <= 65535
        }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        addLog("Enabled set to \(enabled)")

        if enabled {
            restartAvailabilityMonitor()
        } else {
            stopAvailabilityMonitor()
            isVisible = false
            disconnect(silent: true)
        }
    }

    func updateConnectionMode(_ mode: ConnectionMode) {
        guard connectionMode != mode else { return }
        connectionMode = mode
        defaults.set(mode.rawValue, forKey: connectionModeKey)
        addLog("Connection mode set to \(mode.label)")
        disconnect(silent: true)
        restartAvailabilityMonitor()
    }

    func updateHost(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        host = trimmed
        defaults.set(trimmed, forKey: hostKey)
        addLog("Host updated to \(trimmed)")
        restartAvailabilityMonitor()
    }

    func updatePort(_ value: Int) {
        let safe = min(max(1, value), 65535)
        port = safe
        defaults.set(safe, forKey: portKey)
        addLog("Port updated to \(safe)")
        restartAvailabilityMonitor()
    }

    func updateLineEnding(_ value: LineEnding) {
        lineEnding = value
        defaults.set(value.rawValue, forKey: lineEndingKey)
        addLog("Line ending set to \(value.label)")
    }

    func setAutoWrapAngleBrackets(_ enabled: Bool) {
        autoWrapAngleBrackets = enabled
        defaults.set(enabled, forKey: autoWrapAngleBracketsKey)
        addLog("Auto-wrap < > set to \(enabled)")
    }

    func setReconnectPerCommand(_ enabled: Bool) {
        reconnectPerCommand = enabled
        defaults.set(enabled, forKey: reconnectPerCommandKey)
        addLog("Reconnect per command set to \(enabled)")
    }

    func clearStatus() {
        lastResponseText = nil
        lastErrorText = nil
    }

    func clearLog() {
        log.removeAll()
    }

    // =====================================================
    // MARK: - Connection lifecycle
    // =====================================================

    func connect() {
        clearStatus()

        guard isConfigured else {
            state = .error
            lastErrorText = "Gun host/port not configured."
            addLog("Connect failed: gun host/port not configured")
            return
        }

        switch connectionMode {
        case .client:
            connectAsClient()

        case .listener:
            startListening()
        }
    }

    func disconnect() {
        disconnect(silent: false)
    }

    private func disconnect(silent: Bool) {
        isSending = false
        isReceiveLoopActive = false
        isListenerReceiveLoopActive = false
        isVisible = false
        clearPendingSend()

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        listenerConnection?.stateUpdateHandler = nil
        listenerConnection?.cancel()
        listenerConnection = nil

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        if !silent {
            state = .disconnected
            lastResponseText = "Disconnected"
            lastPeerText = "—"
            addLog("Disconnected")
        }
    }

    private func connectAsClient() {
        disconnect(silent: true)

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            state = .error
            lastErrorText = "Invalid port \(port)."
            addLog("Connect failed: invalid port \(port)")
            return
        }

        state = .connecting
        addLog("Connecting to \(trimmedHost):\(port)")

        let newConnection = NWConnection(
            host: NWEndpoint.Host(trimmedHost),
            port: nwPort,
            using: .tcp
        )

        connection = newConnection
        isReceiveLoopActive = false
        pendingFormattedCommand = nil
        pendingTrimmedCommand = nil

        newConnection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }

            Task { @MainActor in
                switch newState {
                case .setup:
                    self.addLog("TCP setup")

                case .preparing:
                    self.state = .connecting
                    self.addLog("TCP preparing")

                case .ready:
                    self.state = .connected
                    self.isVisible = true
                    self.lastErrorText = nil
                    self.lastResponseText = "Connected to \(trimmedHost):\(self.port)"
                    self.addLog("TCP ready")
                    self.startReceiveLoopIfNeeded()
                    self.flushPendingSendIfNeeded()

                case .waiting(let error):
                    self.state = .error
                    self.isVisible = false
                    self.lastErrorText = "Waiting: \(error.localizedDescription)"
                    self.isSending = false
                    self.addLog("TCP waiting: \(error.localizedDescription)")
                    self.clearPendingSend()

                case .failed(let error):
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = error.localizedDescription
                    self.addLog("TCP failed: \(error.localizedDescription)")
                    self.clearPendingSend()

                case .cancelled:
                    self.isVisible = false
                    if self.state != .error {
                        self.state = .disconnected
                    }
                    self.isSending = false
                    self.addLog("TCP cancelled")
                    self.clearPendingSend()

                @unknown default:
                    self.state = .error
                    self.isVisible = false
                    self.lastErrorText = "Unknown network state."
                    self.isSending = false
                    self.addLog("TCP unknown state")
                    self.clearPendingSend()
                }
            }
        }

        newConnection.start(queue: networkQueue)
    }

    private func startListening() {
        disconnect(silent: true)

        guard let listenPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            state = .error
            lastErrorText = "Invalid listen port \(port)."
            addLog("Listener failed: invalid port \(port)")
            return
        }

        do {
            state = .connecting
            addLog("Starting listener on port \(port)")

            let listener = try NWListener(using: .tcp, on: listenPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }

                Task { @MainActor in
                    switch newState {
                    case .setup:
                        self.addLog("Listener setup")

                    case .waiting(let error):
                        self.state = .error
                        self.isVisible = false
                        self.lastErrorText = error.localizedDescription
                        self.addLog("Listener waiting: \(error.localizedDescription)")

                    case .ready:
                        self.state = .connecting
                        self.isVisible = true
                        self.lastErrorText = nil
                        self.lastResponseText = "Listening on port \(self.port)"
                        self.addLog("Listening on port \(self.port)")

                    case .failed(let error):
                        self.state = .error
                        self.isVisible = false
                        self.lastErrorText = error.localizedDescription
                        self.addLog("Listener failed: \(error.localizedDescription)")

                    case .cancelled:
                        if self.state != .error {
                            self.state = .disconnected
                        }
                        self.isVisible = false
                        self.addLog("Listener cancelled")

                    @unknown default:
                        self.state = .error
                        self.isVisible = false
                        self.lastErrorText = "Unknown listener state."
                        self.addLog("Listener unknown state")
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] newConnection in
                guard let self else { return }

                Task { @MainActor in
                    self.acceptListenerConnection(newConnection)
                }
            }

            listener.start(queue: networkQueue)

        } catch {
            state = .error
            isVisible = false
            lastErrorText = error.localizedDescription
            addLog("Listener start failed: \(error.localizedDescription)")
        }
    }

    private func acceptListenerConnection(_ newConnection: NWConnection) {
        listenerConnection?.stateUpdateHandler = nil
        listenerConnection?.cancel()
        listenerConnection = nil
        isListenerReceiveLoopActive = false

        listenerConnection = newConnection
        lastPeerText = endpointLabel(newConnection.endpoint)
        addLog("Accepted gun connection from \(lastPeerText)")

        newConnection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }

            Task { @MainActor in
                switch newState {
                case .setup:
                    self.addLog("Gun peer setup")

                case .preparing:
                    self.addLog("Gun peer preparing")

                case .ready:
                    self.state = .connected
                    self.isVisible = true
                    self.lastErrorText = nil
                    self.lastResponseText = "Gun connected from \(self.lastPeerText)"
                    self.addLog("Gun peer ready")
                    self.startListenerReceiveLoopIfNeeded()

                case .waiting(let error):
                    self.state = .error
                    self.isVisible = false
                    self.lastErrorText = error.localizedDescription
                    self.isSending = false
                    self.addLog("Gun peer waiting: \(error.localizedDescription)")

                case .failed(let error):
                    self.state = .error
                    self.isVisible = false
                    self.lastErrorText = error.localizedDescription
                    self.isSending = false
                    self.addLog("Gun peer failed: \(error.localizedDescription)")
                    self.listenerConnection = nil
                    self.isListenerReceiveLoopActive = false

                case .cancelled:
                    if self.state != .error {
                        self.state = .connecting
                    }
                    self.isVisible = true
                    self.isSending = false
                    self.addLog("Gun peer cancelled")
                    self.listenerConnection = nil
                    self.isListenerReceiveLoopActive = false
                    self.lastPeerText = "—"

                @unknown default:
                    self.state = .error
                    self.isVisible = false
                    self.lastErrorText = "Unknown peer state."
                    self.isSending = false
                    self.addLog("Gun peer unknown state")
                    self.listenerConnection = nil
                    self.isListenerReceiveLoopActive = false
                }
            }
        }

        newConnection.start(queue: networkQueue)
    }

    // =====================================================
    // MARK: - Dose sending
    // =====================================================

    func sendDose(_ dose: Double, unit: DoseUnit) {
        clearStatus()

        guard isConfigured else {
            state = .error
            lastErrorText = "Gun host/port not configured."
            addLog("Send failed: gun host/port not configured")
            return
        }

        guard dose > 0 else {
            lastErrorText = "Dose must be greater than zero."
            addLog("Send failed: dose <= 0")
            return
        }

        let formattedDose = dose.cleanDoseText
        let command = makeDoseCommand(dose: formattedDose, unit: unit)

        lastDoseSent = dose
        lastDoseUnit = unit
        lastSentAt = Date()

        sendRawCommand(command)
    }

    func sendDoseString(_ doseText: String, unit: DoseUnit) {
        let cleaned = doseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let dose = Double(cleaned) else {
            lastErrorText = "Dose is not a valid number."
            addLog("Send failed: invalid dose string \(doseText)")
            return
        }

        sendDose(dose, unit: unit)
    }

    func sendSelectedTreatment(_ treatment: SessionTreatment, weightKg: Double) {
        clearStatus()

        guard let dose = treatment.calculatedDose(forWeightKg: weightKg) else {
            lastErrorText = "Unable to calculate dose for selected treatment."
            addLog("Send failed: could not calculate dose for treatment \(treatment.product)")
            return
        }

        let unit = treatment.doseUnit ?? .mL
        sendDose(dose, unit: unit)
    }

    func sendRawCommand(_ command: String) {
        switch connectionMode {
        case .client:
            sendCommandInternal(command, forceFreshConnection: reconnectPerCommand)

        case .listener:
            sendListenerCommand(command, alreadyFormatted: false)
        }
    }

    func sendWrappedCommand(_ rawBody: String) {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        switch connectionMode {
        case .client:
            sendCommandInternal("<\(body)>", forceFreshConnection: true, alreadyFormatted: true)

        case .listener:
            sendListenerCommand("<\(body)>", alreadyFormatted: true)
        }
    }

    func sendTestPing() {
        sendRawCommand("PING")
    }

    func sendTestDose25mL() {
        sendDose(25, unit: .mL)
    }

    func sendProbe25() {
        sendRawCommand("25")
    }

    func sendProbeWrapped25() {
        sendWrappedCommand("25")
    }

    func sendProbeWrappedD25() {
        sendWrappedCommand("D25")
    }

    func sendProbeWrappedD250() {
        sendWrappedCommand("D250")
    }

    func sendProbeWrappedD25Point0() {
        sendWrappedCommand("D25.0")
    }

    // =====================================================
    // MARK: - Internal send (client mode)
    // =====================================================

    private func sendCommandInternal(
        _ command: String,
        forceFreshConnection: Bool,
        alreadyFormatted: Bool = false
    ) {
        clearStatus()

        guard isConfigured else {
            state = .error
            lastErrorText = "Gun host/port not configured."
            addLog("Raw send failed: gun host/port not configured")
            return
        }

        let formatted = alreadyFormatted ? command : formatOutgoingCommand(command)
        let trimmedForUI = formatted.trimmingCharacters(in: .whitespacesAndNewlines)

        if forceFreshConnection {
            sendOnFreshConnection(formatted, trimmedForUI: trimmedForUI)
            return
        }

        switch state {
        case .connected:
            write(formatted, trimmedForUI: trimmedForUI, over: connection)

        case .connecting:
            pendingFormattedCommand = formatted
            pendingTrimmedCommand = trimmedForUI
            isSending = true
            addLog("Queued TX until connected: \(trimmedForUI)")

        case .disconnected:
            pendingFormattedCommand = formatted
            pendingTrimmedCommand = trimmedForUI
            isSending = true
            addLog("Connecting before TX: \(trimmedForUI)")
            connectAsClient()

        case .error:
            lastErrorText = "Gun is in error state."
            addLog("Raw send aborted: state = error")
        }
    }

    private func sendOnFreshConnection(_ command: String, trimmedForUI: String) {
        clearPendingSend()
        clearPersistentConnectionForFreshSend()

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            state = .error
            lastErrorText = "Invalid port \(port)."
            addLog("Fresh send failed: invalid port \(port)")
            return
        }

        state = .connecting
        isSending = true
        addLog("Fresh connect for TX to \(trimmedHost):\(port)")

        let freshConnection = NWConnection(
            host: NWEndpoint.Host(trimmedHost),
            port: nwPort,
            using: .tcp
        )

        freshConnection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }

            switch newState {
            case .setup:
                Task { @MainActor in
                    self.addLog("Fresh TCP setup")
                }

            case .preparing:
                Task { @MainActor in
                    self.state = .connecting
                    self.addLog("Fresh TCP preparing")
                }

            case .ready:
                Task { @MainActor in
                    self.state = .connected
                    self.isVisible = true
                    self.lastErrorText = nil
                    self.addLog("Fresh TCP ready")

                    self.writeOneShot(command, trimmedForUI: trimmedForUI, over: freshConnection) {
                        Task { @MainActor in
                            self.addLog("Short-lived command cycle complete")
                            self.state = .disconnected
                            self.isVisible = false
                            self.isSending = false
                        }
                        freshConnection.stateUpdateHandler = nil
                        freshConnection.cancel()
                    }
                }

            case .waiting(let error):
                Task { @MainActor in
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = "Waiting: \(error.localizedDescription)"
                    self.addLog("Fresh TCP waiting: \(error.localizedDescription)")
                }
                freshConnection.stateUpdateHandler = nil
                freshConnection.cancel()

            case .failed(let error):
                Task { @MainActor in
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = error.localizedDescription
                    self.addLog("Fresh TCP failed: \(error.localizedDescription)")
                }
                freshConnection.stateUpdateHandler = nil
                freshConnection.cancel()

            case .cancelled:
                Task { @MainActor in
                    self.addLog("Fresh TCP cancelled")
                    if self.state != .error {
                        self.state = .disconnected
                    }
                    self.isVisible = false
                    self.isSending = false
                }

            @unknown default:
                Task { @MainActor in
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = "Unknown network state."
                    self.addLog("Fresh TCP unknown state")
                }
                freshConnection.stateUpdateHandler = nil
                freshConnection.cancel()
            }
        }

        freshConnection.start(queue: networkQueue)
    }

    // =====================================================
    // MARK: - Internal send (listener mode)
    // =====================================================

    private func sendListenerCommand(_ command: String, alreadyFormatted: Bool) {
        clearStatus()

        let formatted = alreadyFormatted ? command : formatOutgoingCommand(command)
        let trimmedForUI = formatted.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let listenerConnection else {
            lastErrorText = "No gun connected to listener."
            addLog("Listener TX failed: no active gun connection")
            return
        }

        write(formatted, trimmedForUI: trimmedForUI, over: listenerConnection)
    }

    private func clearPersistentConnectionForFreshSend() {
        isReceiveLoopActive = false
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func write(_ formatted: String, trimmedForUI: String, over connection: NWConnection?) {
        guard let connection else {
            state = .error
            isSending = false
            lastErrorText = "No TCP connection available."
            addLog("TX failed: no active connection")
            return
        }

        isSending = true
        lastCommandText = trimmedForUI
        addLog("TX: \(trimmedForUI)")
        addLog("TX hex: \(Data(formatted.utf8).hexString)")

        let payload = Data(formatted.utf8)

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = error.localizedDescription
                    self.addLog("TX failed: \(error.localizedDescription)")
                } else {
                    self.lastSentAt = Date()
                    self.lastResponseText = "Sent \(payload.count) bytes"
                    self.isSending = false
                    self.addLog("TX ok (\(payload.count) bytes)")
                }
            }
        })
    }

    private func writeOneShot(
        _ formatted: String,
        trimmedForUI: String,
        over connection: NWConnection,
        completion: @escaping () -> Void
    ) {
        isSending = true
        lastCommandText = trimmedForUI
        addLog("TX: \(trimmedForUI)")
        addLog("TX hex: \(Data(formatted.utf8).hexString)")

        let payload = Data(formatted.utf8)

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.state = .error
                    self.isVisible = false
                    self.isSending = false
                    self.lastErrorText = error.localizedDescription
                    self.addLog("TX failed: \(error.localizedDescription)")
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                } else {
                    self.lastSentAt = Date()
                    self.lastResponseText = "Sent \(payload.count) bytes"
                    self.addLog("TX ok (\(payload.count) bytes)")
                    self.isSending = false

                    self.readOneShotReply(on: connection) {
                        completion()
                    }
                }
            }
        })
    }

    private func readOneShotReply(on connection: NWConnection, completion: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.addLog("RX failed: \(error.localizedDescription)")
                    completion()
                    return
                }

                if let data, !data.isEmpty {
                    let utf8 = String(decoding: data, as: UTF8.self)
                    let text = utf8.trimmingCharacters(in: .whitespacesAndNewlines)

                    self.lastResponseText = text.isEmpty ? data.hexString : text

                    if !text.isEmpty {
                        self.addLog("RX: \(text)")
                    } else {
                        self.addLog("RX bytes: \(data.count)")
                    }

                    self.addLog("RX hex: \(data.hexString)")
                }

                if isComplete {
                    self.addLog("RX complete / peer closed")
                    completion()
                    return
                }

                completion()
            }
        }
    }

    private func flushPendingSendIfNeeded() {
        guard state == .connected else { return }
        guard let formatted = pendingFormattedCommand,
              let trimmed = pendingTrimmedCommand else { return }

        clearPendingSend()
        write(formatted, trimmedForUI: trimmed, over: connection)
    }

    private func clearPendingSend() {
        pendingFormattedCommand = nil
        pendingTrimmedCommand = nil
    }

    private func formatOutgoingCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        let wrapped: String
        if autoWrapAngleBrackets && !trimmed.hasPrefix("<") && !trimmed.hasSuffix(">") {
            wrapped = "<\(trimmed)>"
        } else {
            wrapped = trimmed
        }

        return wrapped + lineEnding.suffix
    }

    // =====================================================
    // MARK: - Receive loop (client mode)
    // =====================================================

    private func startReceiveLoopIfNeeded() {
        guard !isReceiveLoopActive else { return }
        isReceiveLoopActive = true
        receiveNext()
    }

    private func receiveNext() {
        guard let connection else {
            isReceiveLoopActive = false
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.lastErrorText = error.localizedDescription
                    self.addLog("RX failed: \(error.localizedDescription)")
                    self.state = .error
                    self.isVisible = false
                    self.isReceiveLoopActive = false
                    self.isSending = false
                    return
                }

                self.handleIncomingData(data)

                if isComplete {
                    self.addLog("RX complete / peer closed")
                    self.isReceiveLoopActive = false
                    self.isSending = false

                    if self.state != .error {
                        self.state = .disconnected
                    }

                    self.isVisible = false
                    self.connection?.stateUpdateHandler = nil
                    self.connection = nil
                    self.clearPendingSend()
                    return
                }

                self.receiveNext()
            }
        }
    }

    // =====================================================
    // MARK: - Receive loop (listener mode)
    // =====================================================

    private func startListenerReceiveLoopIfNeeded() {
        guard !isListenerReceiveLoopActive else { return }
        isListenerReceiveLoopActive = true
        receiveNextFromListenerPeer()
    }

    private func receiveNextFromListenerPeer() {
        guard let listenerConnection else {
            isListenerReceiveLoopActive = false
            return
        }

        listenerConnection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.lastErrorText = error.localizedDescription
                    self.addLog("Listener RX failed: \(error.localizedDescription)")
                    self.state = .error
                    self.isVisible = false
                    self.isListenerReceiveLoopActive = false
                    self.isSending = false
                    return
                }

                self.handleIncomingData(data)

                if isComplete {
                    self.addLog("Listener RX complete / peer closed")
                    self.isListenerReceiveLoopActive = false
                    self.isSending = false
                    self.listenerConnection?.stateUpdateHandler = nil
                    self.listenerConnection = nil
                    self.lastPeerText = "—"

                    if self.state != .error {
                        self.state = .connecting
                        self.isVisible = true
                        self.lastResponseText = "Listening on port \(self.port)"
                    }
                    return
                }

                self.receiveNextFromListenerPeer()
            }
        }
    }

    private func handleIncomingData(_ data: Data?) {
        guard let data, !data.isEmpty else { return }

        let utf8 = String(decoding: data, as: UTF8.self)
        let text = utf8.trimmingCharacters(in: .whitespacesAndNewlines)

        lastResponseText = text.isEmpty ? data.hexString : text

        if !text.isEmpty {
            addLog("RX: \(text)")
        } else {
            addLog("RX bytes: \(data.count)")
        }

        addLog("RX hex: \(data.hexString)")
    }

    // =====================================================
    // MARK: - Availability monitor
    // =====================================================

    private func startAvailabilityMonitor() {
        stopAvailabilityMonitor()

        guard isEnabled, isConfigured else {
            isVisible = false
            return
        }

        switch connectionMode {
        case .client:
            probeAvailability()

            availabilityTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.probeAvailability()
                }
            }

        case .listener:
            isVisible = listener != nil || listenerConnection != nil || state == .connected || state == .connecting
        }
    }

    private func restartAvailabilityMonitor() {
        startAvailabilityMonitor()
    }

    private func stopAvailabilityMonitor() {
        availabilityTimer?.invalidate()
        availabilityTimer = nil

        availabilityProbe?.stateUpdateHandler = nil
        availabilityProbe?.cancel()
        availabilityProbe = nil
    }

    private func probeAvailability() {
        guard isEnabled, isConfigured else {
            isVisible = false
            return
        }

        guard connectionMode == .client else {
            isVisible = listener != nil || listenerConnection != nil
            return
        }

        if state == .connected {
            isVisible = true
            return
        }

        availabilityProbe?.stateUpdateHandler = nil
        availabilityProbe?.cancel()
        availabilityProbe = nil

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            isVisible = false
            return
        }

        let probe = NWConnection(
            host: NWEndpoint.Host(trimmedHost),
            port: nwPort,
            using: .tcp
        )

        availabilityProbe = probe

        probe.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                Task { @MainActor in
                    if self.availabilityProbe === probe {
                        self.isVisible = true
                        probe.stateUpdateHandler = nil
                        probe.cancel()
                        self.availabilityProbe = nil
                    }
                }

            case .failed(_), .waiting(_), .cancelled:
                Task { @MainActor in
                    if self.availabilityProbe === probe {
                        self.isVisible = false
                        probe.stateUpdateHandler = nil
                        probe.cancel()
                        self.availabilityProbe = nil
                    }
                }

            default:
                break
            }
        }

        probe.start(queue: networkQueue)

        networkQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                if self.availabilityProbe === probe {
                    self.isVisible = false
                    probe.stateUpdateHandler = nil
                    probe.cancel()
                    self.availabilityProbe = nil
                }
            }
        }
    }

    // =====================================================
    // MARK: - Protocol builder
    // =====================================================

    private func makeDoseCommand(dose: String, unit: DoseUnit) -> String {
        _ = unit
        return "<D\(dose)>"
    }

    // =====================================================
    // MARK: - Logging
    // =====================================================

    private func addLog(_ message: String) {
        log.append(.init(timestamp: Date(), message: message))
        if log.count > 500 {
            log.removeFirst(log.count - 500)
        }
    }

    private func endpointLabel(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return endpoint.debugDescription
        }
    }
}

// =====================================================
// MARK: - Small helpers
// =====================================================

private extension Double {
    var cleanDoseText: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        } else if (self * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", self)
        } else {
            return String(format: "%.2f", self)
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
