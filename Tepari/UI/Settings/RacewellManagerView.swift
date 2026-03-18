import Foundation
import Combine

@MainActor
final class RacewellManager: ObservableObject {

    // -------------------------------------------------
    // MARK: State
    // -------------------------------------------------

    @Published var state: ConnectionState = .disconnected

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

    func testGate(_ gate: Int) {
        guard (1...4).contains(gate) else {
            append("[WARN] Invalid gate \(gate)")
            return
        }

        guard DraftWifiController.hasDiscoveredDrafter() else {
            flashDisconnectedError("Gate \(gate) pressed while disconnected")
            return
        }

        if state != .connected {
            state = .connected
        }

        append("[TX] Gate \(gate)")
        DraftWifiController.holdGate(gate)
        append("[INFO] Sent WiFi gate \(gate)")
    }

    func catchOn() {
        guard DraftWifiController.hasDiscoveredDrafter() else {
            flashDisconnectedError("Catch pressed while disconnected")
            return
        }

        if state != .connected {
            state = .connected
        }

        append("[TX] Catch")
        DraftWifiController.holdGate(5)
        append("[INFO] Sent WiFi catch")
    }

    func releaseCatch() {
        guard DraftWifiController.hasDiscoveredDrafter() else {
            flashDisconnectedError("Release pressed while disconnected")
            return
        }

        if state != .connected {
            state = .connected
        }

        append("[TX] Release")
        DraftWifiController.releaseGate(5)
        append("[INFO] Sent WiFi release")
    }

    func allOff() {
        guard DraftWifiController.hasDiscoveredDrafter() else {
            flashDisconnectedError("All Off pressed while disconnected")
            return
        }

        if state != .connected {
            state = .connected
        }

        append("[TX] All Off")
        DraftWifiController.releaseAllGates()
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
