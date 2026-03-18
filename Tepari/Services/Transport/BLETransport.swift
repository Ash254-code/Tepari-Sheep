import Foundation
import CoreBluetooth

/// ✅ BLETransport (legacy placeholder)
///
/// This currently exists so TransportManager can offer a “Bluetooth (BLE)” method,
/// but the Te Pari T1 connection is Wi-Fi (TCP) and Racewell/Tru-Test will later
/// have their own dedicated managers.
///
/// We’re keeping this file (so nothing breaks), and improving it slightly:
/// - clearer state messaging
/// - safe scanning start/stop hooks
/// - minimal discovery list (optional callback) for future Stick Reader UI
///
/// NOTE: This does NOT yet implement a full Tru-Test stick reader integration.
/// We’ll do that via a dedicated StickReaderManager soon.
final class BLETransport: NSObject, TransportProtocol {

    // =========================================================
    // MARK: - TransportProtocol
    // =========================================================

    var onReceiveLine: ((String) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?

    var isConnected: Bool { peripheral != nil && peripheral?.state == .connected }

    // =========================================================
    // MARK: - BLE Core
    // =========================================================

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    /// Optional: surface discovered peripherals for future UI.
    /// (Not used anywhere yet.)
    var onDiscover: ((CBPeripheral, NSNumber?) -> Void)?

    /// Scanning state
    private var isScanning: Bool = false

    /// If you later want to filter by advertised name (e.g. “Tru-Test”), set this.
    var nameFilterContains: String? = nil

    override init() {
        super.init()
        // queue: nil usually means main, but we still enforce main delivery in emitState/emitLine
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func connect() {
        // This “connect” currently means “begin scanning”.
        guard central.state == .poweredOn else {
            emitState(.error("Bluetooth is not powered on"))
            return
        }

        startScan()
    }

    func disconnect() {
        stopScan()

        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        emitState(.disconnected)
    }

    // =========================================================
    // MARK: - Scan helpers (for future Stick UI)
    // =========================================================

    func startScan() {
        guard central.state == .poweredOn else {
            emitState(.error("Bluetooth is not powered on"))
            return
        }

        if isScanning { return }

        isScanning = true
        emitState(.scanning)

        // No service filter yet; we discover broadly.
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        central.stopScan()

        // If we’re not connected, reflect idle state as disconnected
        if !isConnected {
            emitState(.disconnected)
        }
    }

    // =========================================================
    // MARK: - Main-thread delivery
    // =========================================================

    private func emitState(_ state: ConnectionState) {
        DispatchQueue.main.async { [onStateChange] in
            onStateChange?(state)
        }
    }

    private func emitLine(_ line: String) {
        DispatchQueue.main.async { [onReceiveLine] in
            onReceiveLine?(line)
        }
    }
}

// =========================================================
// MARK: - CBCentralManagerDelegate
// =========================================================

extension BLETransport: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // remain idle until user taps Connect/Scan
            if !isConnected && !isScanning {
                emitState(.disconnected)
            }
        case .poweredOff:
            emitState(.error("Bluetooth is off"))
        case .unauthorized:
            emitState(.error("Bluetooth permission not granted"))
        case .unsupported:
            emitState(.error("Bluetooth not supported on this device"))
        case .resetting:
            emitState(.reconnecting)
        case .unknown:
            emitState(.error("Bluetooth state unknown"))
        @unknown default:
            emitState(.error("Bluetooth state unknown"))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // Optional name filter
        if let filter = nameFilterContains?.lowercased(), !filter.isEmpty {
            let name = (peripheral.name ?? "").lowercased()
            if !name.contains(filter) { return }
        }

        onDiscover?(peripheral, RSSI)

        // For now we do NOT auto-connect. The future Stick Reader screen will let you pick.
        // If you want temporary “auto connect to first discovered” behaviour later, we can add it.
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral
        stopScan()
        emitState(.connected)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        emitState(.error(error?.localizedDescription ?? "Failed to connect"))
        stopScan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        if let error {
            emitState(.error("Disconnected: \(error.localizedDescription)"))
        } else {
            emitState(.disconnected)
        }
    }
}
