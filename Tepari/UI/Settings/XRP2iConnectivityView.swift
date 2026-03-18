import SwiftUI
import Combine
import CoreBluetooth

// =====================================================
// MARK: - XRP2i Connectivity View (Apple Glass style)
// =====================================================

struct XRP2iConnectivityView: View {

    @EnvironmentObject private var xrp2i: XRP2iManager

    @State private var showTroubleshooting: Bool = false
    @State private var showAdvanced: Bool = false

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    headerCard
                    primaryActionCard
                    devicesCard
                    statusCard

                    if xrp2i.state.isConnectedLike {
                        liveReadCard
                    }

                    helpCard
                    bottomPillsCard

                    if showTroubleshooting {
                        troubleshootingCard
                    }

                    if showAdvanced {
                        advancedCard
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
        }
        .navigationTitle("XRP2i Panel Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    xrp2i.disconnect()
                } label: {
                    Image(systemName: "xmark.circle")
                        .imageScale(.large)
                }
                .disabled(!xrp2i.state.isConnectedLike)
            }
        }
        .onAppear {
            xrp2i.ensureBluetoothStarted()
            if xrp2i.autoStartOnAppear {
                // if we have a saved device, try it first
                xrp2i.startSimpleAutoConnect()
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Panel Reader (Bluetooth)")
                            .font(.headline)
                        Text("Scan • connect • continuous tag reads")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    StatusPill(
                        text: xrp2i.state.shortLabel,
                        color: xrp2i.state.tint
                    )
                }

                if let msg = xrp2i.userHint, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var primaryActionCard: some View {
        GlassCard {
            VStack(spacing: 12) {

                Button {
                    xrp2i.startSimpleAutoConnect()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: xrp2i.state.primaryIcon)
                            .font(.system(size: 16, weight: .semibold))

                        Text(xrp2i.state.primaryActionTitle)
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        if xrp2i.state.isBusy {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!xrp2i.state.canStart)

                HStack(spacing: 10) {
                    Button {
                        xrp2i.retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!xrp2i.state.canRetry)

                    Button {
                        xrp2i.toggleDemoReads()
                    } label: {
                        Label(
                            xrp2i.demoReadsEnabled ? "Demo On" : "Demo Off",
                            systemImage: xrp2i.demoReadsEnabled ? "sparkles" : "sparkles.slash"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Text("Tip: If it won’t connect, tap Scan Bluetooth and pick the device. If it still fails, open Troubleshoot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    // ✅ NEW: Scan button + device lists
    private var devicesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text("Devices")
                        .font(.headline)
                    Spacer()
                    Text(xrp2i.isScanning ? "Scanning…" : "Ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Scan button
                Button {
                    xrp2i.startScan()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                        Text(xrp2i.isScanning ? "Scanning…" : "Scan Bluetooth")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if xrp2i.isScanning { ProgressView() }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .disabled(!xrp2i.canScan)

                if !xrp2i.savedDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previously connected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(xrp2i.savedDevices) { d in
                            Button {
                                xrp2i.connectSavedDevice(d)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(d.id)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    xrp2i.forgetSavedDevice(id: d.id)
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                            }
                        }

                        Button(role: .destructive) {
                            xrp2i.forgetAllSavedDevices()
                        } label: {
                            Label("Forget all saved devices", systemImage: "trash.slash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }

                if !xrp2i.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nearby")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(xrp2i.discoveredDevices) { d in
                            Button {
                                xrp2i.connectDiscoveredDevice(d)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("RSSI \(d.rssi)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if xrp2i.savedDevices.isEmpty && xrp2i.discoveredDevices.isEmpty {
                    Text("Tap Scan Bluetooth. Keep the XRP2i powered on and within ~2m for first pairing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("Status")
                        .font(.headline)
                    Spacer()
                    Text(xrp2i.state.detailLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.22)

                statusRow("Bluetooth", value: xrp2i.bluetoothStatusLabel, ok: xrp2i.bluetoothOK)
                statusRow("Permission", value: xrp2i.permissionStatusLabel, ok: xrp2i.permissionOK)
                statusRow("Device", value: xrp2i.connectedDeviceLabel, ok: xrp2i.state.isConnectedLike)

                if let err = xrp2i.lastError, !err.isEmpty {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(14)
        }
    }

    private var liveReadCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("Live Reads")
                        .font(.headline)
                    Spacer()
                    Text(xrp2i.isStreaming ? "Streaming" : "Idle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.22)

                HStack {
                    Text("Last EID")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(xrp2i.lastEID)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }

                if !xrp2i.recentEIDs.isEmpty {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(xrp2i.recentEIDs.prefix(6), id: \.self) { eid in
                            Text(eid)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        xrp2i.clearReads()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        xrp2i.toggleStreaming()
                    } label: {
                        Label(
                            xrp2i.isStreaming ? "Stop" : "Start",
                            systemImage: xrp2i.isStreaming ? "stop.circle" : "play.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!xrp2i.state.isConnectedLike)
                }
            }
            .padding(14)
        }
    }

    private var helpCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("Help")
                        .font(.headline)
                    Spacer()
                    Text("Quick guide")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("If it won’t connect: 1) Bluetooth ON, 2) XRP2i powered, 3) Scan Bluetooth and tap the device, 4) Try power-cycle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var bottomPillsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("More")
                        .font(.headline)
                    Spacer()
                    Text("Tap to expand")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    pillToggle(
                        title: "Troubleshoot",
                        systemImage: "lifepreserver",
                        isOn: showTroubleshooting
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                            showTroubleshooting.toggle()
                            if showTroubleshooting { showAdvanced = false }
                        }
                    }

                    pillToggle(
                        title: "Advanced",
                        systemImage: "slider.horizontal.3",
                        isOn: showAdvanced
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                            showAdvanced.toggle()
                            if showAdvanced { showTroubleshooting = false }
                        }
                    }

                    Button {
                        xrp2i.disconnect()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Disconnect")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .disabled(!xrp2i.state.isConnectedLike)
                    .opacity(xrp2i.state.isConnectedLike ? 1 : 0.5)
                }
            }
            .padding(14)
        }
    }

    private func pillToggle(
        title: String,
        systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.primary : Color.secondary)
        .background(
            Capsule(style: .continuous)
                .fill(isOn ? Color.primary.opacity(0.10) : Color.white.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(isOn ? 0.22 : 0.14), lineWidth: 1)
        )
    }

    private var troubleshootingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Label("Troubleshooting", systemImage: "lifepreserver")
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        text: xrp2i.troubleshootStep.title,
                        color: .secondary
                    )
                }

                Text(xrp2i.troubleshootStep.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().opacity(0.22)

                VStack(spacing: 10) {
                    troubleshootRow(step: .turnOnBluetooth, isCurrent: xrp2i.troubleshootStep == .turnOnBluetooth)
                    troubleshootRow(step: .grantPermission, isCurrent: xrp2i.troubleshootStep == .grantPermission)
                    troubleshootRow(step: .powerCycleReader, isCurrent: xrp2i.troubleshootStep == .powerCycleReader)
                    troubleshootRow(step: .moveCloser, isCurrent: xrp2i.troubleshootStep == .moveCloser)
                    troubleshootRow(step: .scanAgain, isCurrent: xrp2i.troubleshootStep == .scanAgain)
                }

                HStack(spacing: 10) {
                    Button {
                        xrp2i.advanceTroubleshooting()
                    } label: {
                        Label("Next Step", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        xrp2i.resetTroubleshooting()
                    } label: {
                        Label("Start Over", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if !xrp2i.log.isEmpty {
                    Divider().opacity(0.22)

                    Text("Log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(xrp2i.log.suffix(6)) { entry in
                            HStack(alignment: .top) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    Button("Clear Log", role: .destructive) {
                        xrp2i.clearLog()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var advancedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                }

                Toggle("Auto-start on screen open", isOn: $xrp2i.autoStartOnAppear)
                Toggle("Auto-reconnect", isOn: $xrp2i.autoReconnectEnabled)

                Stepper(
                    "Scan timeout: \(Int(xrp2i.scanTimeoutSeconds))s",
                    value: $xrp2i.scanTimeoutSeconds,
                    in: 3...30,
                    step: 1
                )

                Button {
                    xrp2i.forgetAllSavedDevices()
                } label: {
                    Label("Forget all saved devices", systemImage: "trash.slash")
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
    }

    // MARK: - Small helpers

    private func statusRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func troubleshootRow(step: XRP2iTroubleshootStep, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.short)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(isCurrent ? 0.08 : 0.04))
        )
    }
}

// =====================================================
// MARK: - XRP2i Manager (REAL BLE scan/connect + saved list)
// =====================================================

@MainActor
final class XRP2iManager: NSObject, ObservableObject {

    // MARK: - Models

    struct DiscoveredDevice: Identifiable, Equatable {
        let id: String           // UUID string
        let name: String
        let rssi: Int
    }

    struct SavedDevice: Identifiable, Codable, Equatable {
        let id: String           // UUID string
        let name: String
        let lastSeen: Date
    }

    // MARK: - State

    enum State: Equatable {
        case idle
        case scanning
        case connecting(name: String?)
        case connected(name: String?)
        case ready(name: String?)
        case error(message: String)

        var isBusy: Bool {
            switch self {
            case .scanning, .connecting: return true
            default: return false
            }
        }

        var canStart: Bool {
            switch self {
            case .idle, .error, .connected, .ready: return true
            case .scanning, .connecting: return false
            }
        }

        var canRetry: Bool {
            switch self {
            case .error: return true
            default: return false
            }
        }

        var shortLabel: String {
            switch self {
            case .idle: return "Idle"
            case .scanning: return "Scanning"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .ready: return "Ready"
            case .error: return "Error"
            }
        }

        var detailLabel: String {
            switch self {
            case .idle: return "Not connected"
            case .scanning: return "Searching for XRP2i…"
            case .connecting(let name): return "Pairing \(name ?? "device")…"
            case .connected(let name): return "\(name ?? "Device") connected"
            case .ready(let name): return "\(name ?? "Device") streaming"
            case .error(let msg): return msg
            }
        }

        var tint: Color {
            switch self {
            case .ready, .connected: return .green
            case .scanning, .connecting: return .orange
            case .error: return .red
            case .idle: return .secondary
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .idle: return "Connect"
            case .scanning: return "Scanning…"
            case .connecting: return "Connecting…"
            case .connected: return "Start Streaming"
            case .ready: return "Reconnect"
            case .error: return "Try Again"
            }
        }

        var primaryIcon: String {
            switch self {
            case .idle: return "bolt.horizontal.circle"
            case .scanning: return "magnifyingglass"
            case .connecting: return "link"
            case .connected: return "antenna.radiowaves.left.and.right"
            case .ready: return "checkmark.seal"
            case .error: return "exclamationmark.triangle"
            }
        }

        var isConnectedLike: Bool {
            switch self {
            case .connected, .ready: return true
            default: return false
            }
        }
    }

    @Published private(set) var state: State = .idle

    // UI toggles
    @Published var autoStartOnAppear: Bool = true
    @Published var autoReconnectEnabled: Bool = true
    @Published var scanTimeoutSeconds: Double = 10

    // System status
    @Published private(set) var bluetoothOK: Bool = false
    @Published private(set) var permissionOK: Bool = true // CoreBluetooth doesn’t expose "denied"; we treat power-on as OK.

    // Connection identity
    @Published private(set) var connectedDeviceName: String? = nil
    @Published private(set) var lastError: String? = nil
    @Published private(set) var userHint: String? = "Tap Scan Bluetooth, then select your XRP2i."

    // Scan results
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var isScanning: Bool = false

    // Saved devices
    @Published private(set) var savedDevices: [SavedDevice] = []

    // Streaming reads
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var lastEID: String = "—"
    @Published private(set) var recentEIDs: [String] = []
    @Published var demoReadsEnabled: Bool = false

    // Log
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }
    @Published private(set) var log: [LogEntry] = []

    // Troubleshooting
    @Published private(set) var troubleshootStep: XRP2iTroubleshootStep = .turnOnBluetooth

    // MARK: - Internals (CoreBluetooth)

    private var central: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral? = nil
    private var notifyCharacteristics: [CBCharacteristic] = []

    private var scanStopTask: Task<Void, Never>? = nil
    private var demoTask: Task<Void, Never>? = nil

    // Persistence key
    private let savedKey = "xrp2i.savedDevices.v1"

    // MARK: - Init

    override init() {
        super.init()
        loadSavedDevices()
        ensureBluetoothStarted()
    }

    // MARK: - Derived labels

    var bluetoothStatusLabel: String { bluetoothOK ? "On" : "Off" }
    var permissionStatusLabel: String { permissionOK ? "Granted" : "Needed" }
    var connectedDeviceLabel: String { connectedDeviceName ?? "—" }

    var canScan: Bool {
        bluetoothOK && !isScanning
    }

    // MARK: - Public setup

    func ensureBluetoothStarted() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        }
    }

    // MARK: - Main “simple” flow

    func startSimpleAutoConnect() {
        lastError = nil
        ensureBluetoothStarted()

        guard bluetoothOK else {
            fail("Bluetooth is off (or not ready yet).")
            troubleshootStep = .turnOnBluetooth
            return
        }

        // If already connected, ensure streaming
        switch state {
        case .connected, .ready:
            toggleStreaming(true)
            return
        default:
            break
        }

        // Try last saved device first
        if let first = savedDevices.first,
           let uuid = UUID(uuidString: first.id),
           let p = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            logLine("Auto-connecting saved device: \(first.name)")
            connectPeripheral(p)
            return
        }

        // Otherwise scan
        startScan()
    }

    func retry() {
        lastError = nil
        state = .idle
        startSimpleAutoConnect()
    }

    func disconnect() {
        logLine("Disconnect requested")
        stopScan()

        demoTask?.cancel()
        demoTask = nil

        isStreaming = false
        notifyCharacteristics.removeAll()

        if let p = connectedPeripheral {
            central.cancelPeripheralConnection(p)
        }

        connectedPeripheral = nil
        connectedDeviceName = nil
        state = .idle
    }

    // MARK: - Scan

    func startScan() {
        lastError = nil
        ensureBluetoothStarted()

        guard bluetoothOK else {
            fail("Bluetooth is off (or not ready yet).")
            troubleshootStep = .turnOnBluetooth
            return
        }

        stopScan()
        discoveredDevices.removeAll()
        isScanning = true
        state = .scanning
        logLine("BLE scan started")

        // Scan for everything for now (until you know the service UUID)
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Auto stop
        scanStopTask?.cancel()
        scanStopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.scanTimeoutSeconds * 1_000_000_000))
            await MainActor.run { self.stopScan() }
        }
    }

    func stopScan() {
        if isScanning {
            central.stopScan()
            logLine("BLE scan stopped")
        }
        isScanning = false
        if case .scanning = state { state = .idle }
        scanStopTask?.cancel()
        scanStopTask = nil
    }

    // MARK: - Connect selection

    func connectDiscoveredDevice(_ d: DiscoveredDevice) {
        guard let uuid = UUID(uuidString: d.id),
              let p = peripheralsByID[uuid] else {
            fail("Device not available anymore. Try scanning again.")
            return
        }
        connectPeripheral(p)
    }

    func connectSavedDevice(_ d: SavedDevice) {
        guard let uuid = UUID(uuidString: d.id) else { return }

        let retrieved = central.retrievePeripherals(withIdentifiers: [uuid])
        if let p = retrieved.first {
            connectPeripheral(p)
            return
        }

        // If not retrievable, scan and hope it appears
        startScan()
        logLine("Saved device not immediately found; scanning…")
    }

    private func connectPeripheral(_ p: CBPeripheral) {
        stopScan()

        connectedPeripheral = p
        connectedPeripheral?.delegate = self

        let name = p.name ?? "Device"
        connectedDeviceName = name
        state = .connecting(name: name)
        logLine("Connecting to \(name) (\(p.identifier.uuidString))")

        central.connect(p, options: nil)
    }

    // MARK: - Saved devices

    func forgetSavedDevice(id: String) {
        savedDevices.removeAll { $0.id == id }
        persistSavedDevices()
        logLine("Forgot saved device \(id)")
    }

    func forgetAllSavedDevices() {
        savedDevices.removeAll()
        persistSavedDevices()
        logLine("Forgot all saved devices")
    }

    private func saveDevice(peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        let name = peripheral.name ?? "XRP2i"

        // move-to-front / update last seen
        savedDevices.removeAll { $0.id == id }
        savedDevices.insert(.init(id: id, name: name, lastSeen: Date()), at: 0)
        savedDevices = Array(savedDevices.prefix(12))
        persistSavedDevices()
    }

    private func loadSavedDevices() {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) else {
            savedDevices = []
            return
        }
        savedDevices = decoded
    }

    private func persistSavedDevices() {
        if let data = try? JSONEncoder().encode(savedDevices) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    // MARK: - Streaming reads

    func toggleStreaming() {
        toggleStreaming(!isStreaming)
    }

    func toggleStreaming(_ on: Bool) {
        guard state.isConnectedLike else { return }

        isStreaming = on
        state = on ? .ready(name: connectedDeviceName) : .connected(name: connectedDeviceName)
        logLine(on ? "Streaming started" : "Streaming stopped")

        if demoReadsEnabled && on {
            startDemoReads()
        } else {
            stopDemoReads()
        }
    }

    func clearReads() {
        lastEID = "—"
        recentEIDs.removeAll()
    }

    func toggleDemoReads() {
        demoReadsEnabled.toggle()
        logLine(demoReadsEnabled ? "Demo reads enabled" : "Demo reads disabled")

        if demoReadsEnabled && isStreaming {
            startDemoReads()
        } else {
            stopDemoReads()
        }
    }

    // MARK: - Troubleshooting

    func resetTroubleshooting() {
        troubleshootStep = .turnOnBluetooth
    }

    func advanceTroubleshooting() {
        troubleshootStep = troubleshootStep.next
        if troubleshootStep == .scanAgain {
            startScan()
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Logging / errors

    private func fail(_ message: String) {
        lastError = message
        state = .error(message: message)
        logLine("ERROR: \(message)")
    }

    private func logLine(_ s: String) {
        log.append(.init(timestamp: Date(), message: s))
        if log.count > 300 { log.removeFirst(log.count - 300) }
        print("XRP2i:", s)
    }

    // MARK: - Demo reads

    private func startDemoReads() {
        stopDemoReads()
        demoTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(1.2 * 1_000_000_000))
                guard self.isStreaming else { continue }
                let eid = self.makeDemoEID()
                await MainActor.run { self.ingestEID(eid) }
            }
        }
    }

    private func stopDemoReads() {
        demoTask?.cancel()
        demoTask = nil
    }

    private func ingestEID(_ eid: String) {
        lastEID = eid
        recentEIDs.insert(eid, at: 0)
        recentEIDs = Array(recentEIDs.prefix(30))
        logLine("EID: \(eid)")
    }

    private func makeDemoEID() -> String {
        let n = Int.random(in: 1_000_000_000_000_000...9_999_999_999_999_999)
        return "\(n)"
    }

    // MARK: - Best-effort payload parsing
    private func parseEID(from data: Data) -> String? {
        // Try ASCII first
        if let s = String(data: data, encoding: .utf8) {
            let digits = s.filter(\.isNumber)
            if digits.count >= 10 {
                return String(digits.prefix(16))
            }
        }

        // Fallback: digits from bytes
        let hex = data.map { String(format: "%02X", $0) }.joined()
        let digits = hex.filter(\.isNumber)
        if digits.count >= 10 {
            return String(digits.prefix(16))
        }
        return nil
    }
}

// =====================================================
// MARK: - CBCentralManagerDelegate / CBPeripheralDelegate
// =====================================================

extension XRP2iManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.bluetoothOK = true
                self.userHint = "Tap Scan Bluetooth, then select your XRP2i."
            default:
                self.bluetoothOK = false
                self.userHint = "Turn Bluetooth on to connect."
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let name = (peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (peripheral.name ?? "Unknown")
                : "Unknown"

            self.peripheralsByID[peripheral.identifier] = peripheral

            let device = DiscoveredDevice(
                id: peripheral.identifier.uuidString,
                name: name,
                rssi: RSSI.intValue
            )

            // Update / insert (de-dupe)
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredDevices[idx] = device
            } else {
                self.discoveredDevices.append(device)
            }

            // Optional: keep strongest first
            self.discoveredDevices.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            let name = peripheral.name ?? "Device"
            self.connectedPeripheral = peripheral
            self.connectedDeviceName = name
            self.state = .connected(name: name)
            self.logLine("Connected: \(name)")

            self.saveDevice(peripheral: peripheral)

            // Discover everything for now (until you know services)
            peripheral.discoverServices(nil)

            // Start streaming mode
            self.toggleStreaming(true)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.fail("Failed to connect. \(error?.localizedDescription ?? "")")
            self.connectedPeripheral = nil
            self.connectedDeviceName = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.logLine("Disconnected. \(error?.localizedDescription ?? "")")
            self.connectedPeripheral = nil
            self.connectedDeviceName = nil
            self.notifyCharacteristics.removeAll()
            self.isStreaming = false
            self.state = .idle

            if self.autoReconnectEnabled, self.autoStartOnAppear {
                self.startSimpleAutoConnect()
            }
        }
    }
}

extension XRP2iManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.logLine("Service discovery error: \(error.localizedDescription)")
                return
            }
            guard let services = peripheral.services else { return }
            self.logLine("Services: \(services.count)")
            for s in services {
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.logLine("Char discovery error: \(error.localizedDescription)")
                return
            }
            guard let chars = service.characteristics else { return }
            self.logLine("Chars for \(service.uuid): \(chars.count)")

            // Best-effort: subscribe to anything that notifies
            for c in chars where c.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: c)
                self.notifyCharacteristics.append(c)
                self.logLine("Subscribed notify: \(c.uuid)")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.logLine("Notify error: \(error.localizedDescription)")
                return
            }
            guard self.isStreaming else { return }
            guard let data = characteristic.value, !data.isEmpty else { return }

            if let eid = self.parseEID(from: data) {
                self.ingestEID(eid)
            } else {
                // keep log light
                self.logLine("RX \(data.count) bytes from \(characteristic.uuid)")
            }
        }
    }
}

// =====================================================
// MARK: - Troubleshooting steps
// =====================================================

enum XRP2iTroubleshootStep: CaseIterable, Equatable {
    case turnOnBluetooth
    case grantPermission
    case powerCycleReader
    case moveCloser
    case scanAgain

    var title: String {
        switch self {
        case .turnOnBluetooth: return "Bluetooth"
        case .grantPermission: return "Permission"
        case .powerCycleReader: return "Power"
        case .moveCloser: return "Distance"
        case .scanAgain: return "Scan"
        }
    }

    var short: String {
        switch self {
        case .turnOnBluetooth: return "Turn Bluetooth on"
        case .grantPermission: return "Allow Bluetooth access"
        case .powerCycleReader: return "Restart the reader"
        case .moveCloser: return "Bring reader closer"
        case .scanAgain: return "Scan again"
        }
    }

    var body: String {
        switch self {
        case .turnOnBluetooth:
            return "Open iPad Settings → Bluetooth → turn it ON."
        case .grantPermission:
            return "If prompted, tap Allow. If you denied earlier: iPad Settings → Privacy & Security → Bluetooth → enable Tepari."
        case .powerCycleReader:
            return "Power the XRP2i off, wait 5 seconds, then power it back on."
        case .moveCloser:
            return "For first pairing, keep the reader within 1–2 metres of the iPad."
        case .scanAgain:
            return "Tap Scan Bluetooth, then select the device again."
        }
    }

    var next: XRP2iTroubleshootStep {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self) else { return .turnOnBluetooth }
        let next = all.index(after: i)
        return next < all.endIndex ? all[next] : .turnOnBluetooth
    }
}

// =====================================================
// MARK: - Small UI bits
// =====================================================

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }
}
