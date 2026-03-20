import Foundation
import Combine

@MainActor
final class RacewellManager: ObservableObject {

    // -------------------------------------------------
    // MARK: State
    // -------------------------------------------------

    @Published var state: ConnectionState = .disconnected
    @Published var pauseIsOn: Bool = false

    // -------------------------------------------------
    // MARK: Log
    // -------------------------------------------------

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    @Published private(set) var log: [LogEntry] = []

    private var connectionPollTask: Task<Void, Never>?

    private func append(_ message: String) {
        log.append(LogEntry(timestamp: Date(), message: message))
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
    }

    // -------------------------------------------------
    // MARK: Lifecycle
    // -------------------------------------------------

    init() {
        startConnectionPolling()
    }

    deinit {
        connectionPollTask?.cancel()
    }

    private func startConnectionPolling() {
        connectionPollTask?.cancel()

        connectionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refreshConnectionState()
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshConnectionState() {
        let discovered = DraftWifiController.hasDiscoveredDrafter()

        switch state {
        case .connecting:
            if discovered {
                state = .connected
                append("[STATE] Connected")
            }

        case .connected:
            if !discovered {
                state = .disconnected
                append("[STATE] Disconnected")
            }

        case .disconnected:
            if discovered {
                state = .connected
                append("[STATE] Connected")
            }

        case .error:
            if discovered {
                state = .connected
                append("[STATE] Connected")
            }

        case .reconnecting:
            if discovered {
                state = .connected
                append("[STATE] Connected")
            }

        case .scanning:
            if discovered {
                state = .connected
                append("[STATE] Connected")
            }
        }
    }

    private func flashDisconnectedError(_ message: String) {
        state = .error(message)
        append("[ERROR] \(message)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if case .error = self.state {
                self.state = DraftWifiController.hasDiscoveredDrafter() ? .connected : .disconnected
            }
        }
    }

    private func ensureConnectedForAction(_ message: String) -> Bool {
        guard DraftWifiController.hasDiscoveredDrafter() else {
            flashDisconnectedError(message)
            return false
        }

        if state != .connected {
            state = .connected
        }

        return true
    }

    private func pulseRelay(_ relay: Int, for seconds: Double, label: String) {
        guard ensureConnectedForAction("\(label) pressed while disconnected") else { return }

        append("[TX] \(label) ON")
        DraftWifiController.holdGate(relay)
        append("[INFO] Relay \(relay) ON for \(seconds.cleanText)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            DraftWifiController.releaseGate(relay)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.append("[TX] \(label) OFF")
            self?.append("[INFO] Relay \(relay) released")
        }
    }

    // -------------------------------------------------
    // MARK: Public API
    // -------------------------------------------------

    func connect() {
        guard state != .connected, state != .connecting else { return }

        state = .connecting
        append("[INFO] Connecting…")

        DraftWifiController.startDiscovery()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }

            if DraftWifiController.hasDiscoveredDrafter() {
                self.state = .connected
                self.append("[STATE] Connected")
            } else {
                self.flashDisconnectedError("Drafter not found")
            }
        }
    }

    func disconnect() {
        DraftWifiController.stopDiscovery()
        guard state != .disconnected else { return }
        state = .disconnected
        append("[STATE] Disconnected")
    }

    // -------------------------------------------------
    // MARK: Gates
    // -------------------------------------------------

    func leftGate() {
        guard ensureConnectedForAction("Left gate pressed while disconnected") else { return }

        DraftWifiController.releaseGate(2)
        DraftWifiController.holdGate(1)

        append("[TX] Left Gate")
        append("[INFO] Relay 1 latched ON, Relay 2 OFF")
    }

    func centreGate() {
        guard ensureConnectedForAction("Centre gate pressed while disconnected") else { return }

        DraftWifiController.releaseGate(1)
        DraftWifiController.releaseGate(2)

        append("[TX] Centre Gate")
        append("[INFO] Relay 1 and Relay 2 OFF")
    }

    func rightGate() {
        guard ensureConnectedForAction("Right gate pressed while disconnected") else { return }

        DraftWifiController.releaseGate(1)
        DraftWifiController.holdGate(2)

        append("[TX] Right Gate")
        append("[INFO] Relay 2 latched ON, Relay 1 OFF")
    }

    // -------------------------------------------------
    // MARK: Catch / Release
    // -------------------------------------------------

    func catchPulse() {
        pulseRelay(3, for: 3.0, label: "Catch")
    }

    func releasePulse() {
        pulseRelay(4, for: 3.0, label: "Release")
    }

    // -------------------------------------------------
    // MARK: Tilt
    // -------------------------------------------------

    func tiltUpOn() {
        guard ensureConnectedForAction("Tilt Up pressed while disconnected") else { return }

        DraftWifiController.holdGate(5)
        append("[TX] Tilt Up ON")
        append("[INFO] Relay 5 ON")
    }

    func tiltUpOff() {
        guard DraftWifiController.hasDiscoveredDrafter() else { return }

        DraftWifiController.releaseGate(5)
        append("[TX] Tilt Up OFF")
        append("[INFO] Relay 5 OFF")
    }

    func tiltDownOn() {
        guard ensureConnectedForAction("Tilt Down pressed while disconnected") else { return }

        DraftWifiController.holdGate(6)
        append("[TX] Tilt Down ON")
        append("[INFO] Relay 6 ON")
    }

    func tiltDownOff() {
        guard DraftWifiController.hasDiscoveredDrafter() else { return }

        DraftWifiController.releaseGate(6)
        append("[TX] Tilt Down OFF")
        append("[INFO] Relay 6 OFF")
    }

    // -------------------------------------------------
    // MARK: Pause
    // -------------------------------------------------

    func togglePause() {
        guard ensureConnectedForAction("Pause pressed while disconnected") else { return }

        pauseIsOn.toggle()

        if pauseIsOn {
            DraftWifiController.holdGate(7)
            append("[TX] Pause ON")
            append("[INFO] Relay 7 latched ON")
        } else {
            DraftWifiController.releaseGate(7)
            append("[TX] Pause OFF")
            append("[INFO] Relay 7 OFF")
        }
    }

    // -------------------------------------------------
    // MARK: Misc
    // -------------------------------------------------

    func allOff() {
        guard ensureConnectedForAction("All Off pressed while disconnected") else { return }

        pauseIsOn = false
        DraftWifiController.releaseAllGates()

        append("[TX] All Off")
        append("[INFO] Sent WiFi all off")
    }

    func refreshStatus() {
        DraftWifiController.startDiscovery()
        DraftWifiController.fetchStatus()
        refreshConnectionState()
    }

    func clearLog() {
        log.removeAll()
        append("[INFO] Log cleared")
    }
}

private extension Double {
    var cleanText: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        } else if (self * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", self)
        } else {
            return String(format: "%.2f", self)
        }
    }
}
