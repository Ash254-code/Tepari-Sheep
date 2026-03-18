import Foundation
import Combine
import CoreBluetooth

@MainActor
final class StickReaderManager: NSObject, ObservableObject {

    // =====================================================
    // MARK: - Public UI State
    // =====================================================

    @Published var state: ConnectionState = .disconnected
    @Published var isScanning: Bool = false

    /// Stable list for UI (updated on a timer, not every packet)
    @Published private(set) var discovered: [DiscoveredDevice] = []

    @Published private(set) var connectedName: String = "—"
    @Published private(set) var lastScannedEID: String = "—"

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }
    @Published private(set) var log: [LogEntry] = []

    struct DiscoveredDevice: Identifiable {
        let id: UUID
        var name: String
        var rssi: Int
        var order: Int          // first-seen order (stable)
        var lastSeen: Date
    }

    // =====================================================
    // MARK: - BLE Internals
    // =====================================================

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]

    /// High-frequency store updated on every didDiscover callback
    private var liveDevices: [UUID: DiscoveredDevice] = [:]
    private var nextOrder: Int = 0

    /// Throttle UI updates
    private var uiTimer: Timer?
    private let uiUpdateInterval: TimeInterval = 0.4

    /// Auto-stop scanning
    private var autoStopTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // =====================================================
    // MARK: - Public API
    // =====================================================

    func startScan(durationSeconds: Double = 5.0) {
        guard central.state == .poweredOn else {
            state = .error("Bluetooth not available")
            append("[ERROR] StartScan failed: Bluetooth not powered on")
            return
        }

        // Reset scan session UI
        isScanning = true
        state = .scanning
        append("[INFO] Scanning…")

        // Keep old results visible but “freshen” quickly:
        // (or uncomment next 2 lines if you prefer clearing each scan)
        // liveDevices.removeAll()
        // discovered.removeAll()

        // Start scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        // Throttle UI list updates
        startUITimer()

        // Auto-stop after N seconds (so list calms down)
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            self.stopScan()
        }
    }

    func stopScan() {
        autoStopTask?.cancel()
        autoStopTask = nil

        central.stopScan()
        isScanning = false

        // If we’re not connected, return to disconnected state
        if state == .scanning { state = .disconnected }

        stopUITimer()
        append("[INFO] Scan stopped")
        pushUIListSnapshot() // final snapshot
    }

    func connect(to id: UUID) {
        guard let p = peripherals[id] else {
            append("[WARN] Connect failed: peripheral missing \(id)")
            return
        }

        stopScan() // usually best UX: stop scanning when connecting
        state = .connecting
        append("[INFO] Connecting to \(p.name ?? "Unknown") (\(id))")
        central.connect(p, options: nil)
    }

    func disconnect() {
        // Cancel any active connection
        if let connected = peripherals.values.first(where: { $0.state == .connected }) {
            central.cancelPeripheralConnection(connected)
        } else {
            state = .disconnected
            connectedName = "—"
        }
        append("[INFO] Disconnect")
    }

    func clearLog() {
        log.removeAll()
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func append(_ message: String) {
        log.append(LogEntry(message: message))
        if log.count > 300 {
            log.removeFirst(log.count - 300)
        }
    }

    private func startUITimer() {
        stopUITimer()
        uiTimer = Timer.scheduledTimer(withTimeInterval: uiUpdateInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pushUIListSnapshot()
            }
        }
    }

    private func stopUITimer() {
        uiTimer?.invalidate()
        uiTimer = nil
    }

    private func pushUIListSnapshot() {
        // Drop “stale” devices not seen recently (keeps list cleaner)
        let now = Date()
        let staleCutoff: TimeInterval = 4.0

        liveDevices = liveDevices.filter { (_, d) in
            now.timeIntervalSince(d.lastSeen) <= staleCutoff
        }

        // Stable sort: by first-seen order (no jumping)
        let snapshot = liveDevices.values
            .sorted { $0.order < $1.order }

        discovered = snapshot
    }
}

// =====================================================
// MARK: - CBCentralManagerDelegate
// =====================================================

extension StickReaderManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .error = state {
                state = .disconnected
            }
        case .poweredOff:
            state = .error("Bluetooth is Off")
        case .unauthorized:
            state = .error("Bluetooth permission denied")
        default:
            state = .error("Bluetooth not available")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let id = peripheral.identifier
        peripherals[id] = peripheral

        let name =
            peripheral.name ??
            (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ??
            "Unknown"

        let rssiInt = RSSI.intValue
        let now = Date()

        if var existing = liveDevices[id] {
            existing.name = name
            existing.rssi = rssiInt
            existing.lastSeen = now
            liveDevices[id] = existing
        } else {
            liveDevices[id] = DiscoveredDevice(
                id: id,
                name: name,
                rssi: rssiInt,
                order: nextOrder,
                lastSeen: now
            )
            nextOrder += 1
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        connectedName = peripheral.name ?? "Connected"
        append("[STATE] Connected: \(connectedName)")
        // Next step later: discover services/characteristics and subscribe to notify
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        state = .error(error?.localizedDescription ?? "Failed to connect")
        append("[ERROR] Fail connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        state = .disconnected
        connectedName = "—"
        append("[STATE] Disconnected")
    }
}

