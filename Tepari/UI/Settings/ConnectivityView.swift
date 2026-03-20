import SwiftUI

/// ✅ Connectivity hub (secondary menu)
/// Devices get their own pages:
/// - T1 Scale (Wi-Fi TCP)
/// - Racewell Drafter (manager-backed)
/// - Tru-Test Stick Reader (BLE scan + pick + connect + EID sniff + log)
/// - XRP2i Panel Reader (stub)
/// - Tepari Dosing Gun
///
/// Later, the Session Wizard will simply “pick” from whatever is configured here.
struct ConnectivityView: View {

    var body: some View {
        ZStack {
            GlassBackground()

            List {

                Section("Devices") {

                    NavigationLink {
                        T1ConnectivityView()
                    } label: {
                        SettingsLikeRow(
                            title: "T1 Scale with integrated EID",
                            subtitle: "Wi-Fi TCP connection, weight locking and diagnostics",
                            systemImage: "scalemass.fill"
                        )
                    }

                    NavigationLink {
                        RacewellConnectivityView()
                    } label: {
                        SettingsLikeRow(
                            title: "Racewell Drafter",
                            subtitle: "Connect + gate test + log",
                            systemImage: "arrow.trianglehead.branch"
                        )
                    }

                    NavigationLink {
                        StickReaderConnectivityView()
                    } label: {
                        SettingsLikeRow(
                            title: "Stick Reader",
                            subtitle: "BLE scan + pick + connect + tag scan",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }

                    NavigationLink {
                        XRP2iConnectivityView()
                    } label: {
                        SettingsLikeRow(
                            title: "XRP2i Panel Reader",
                            subtitle: "Panel antenna + continuous tag read",
                            systemImage: "rectangle.connected.to.line.below"
                        )
                    }

                    NavigationLink {
                        TepariGunConnectivityView()
                    } label: {
                        SettingsLikeRow(
                            title: "Tepari Dosing Gun",
                            subtitle: "Dose trigger + animal ID integration",
                            systemImage: "syringe.fill"
                        )
                    }
                }

                Section("How this will work") {
                    Text("Set up devices here first. Later, the session wizard will ask “Weigh?” “Draft?” “Scan tags?” and use the configured devices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("⚡ Connectivity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =====================================================
// MARK: - T1 (existing connectivity screen moved here)
// =====================================================

struct T1ConnectivityView: View {

    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var settings: AppSettings

    @State private var didCaptureDefaults = false

    @State private var defaultStableWindowMs: Int = 1200
    @State private var defaultStableToleranceKg: Double = 0.40
    @State private var defaultHoldTimeMs: Int = 300
    @State private var defaultDisplaySmoothing: Double = 0.75
    @State private var defaultSnapBigChangesKg: Double = 2.0
    @State private var defaultMinRelockChangeKg: Double = 0.5
    @State private var defaultForceStable: Bool = false

    @State private var defaultPollIntervalSeconds: Double = 1.0
    @State private var defaultKeepAliveIntervalSeconds: Double = 5.0
    @State private var defaultBurstTicksAfterConnect: Int = 0
    @State private var defaultWatchdogSilenceSeconds: Double = 10.0

    @State private var defaultRequestRequired: Bool = false
    @State private var defaultKeepAliveEnabled: Bool = false
    @State private var defaultBurstVariantsOnConnect: Bool = false
    @State private var defaultWatchdogEnabled: Bool = false

    var body: some View {
        ZStack {
            GlassBackground()

            List {

                Section("Quick Setup") {
                    Button {
                        transport.useT1Defaults()
                    } label: {
                        Label("Use T1 Defaults (TCP t1.local:2000)", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)

                    Text("For T1, use Wi-Fi (TCP). Demo is for testing without hardware.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    Picker("Method", selection: $transport.method) {
                        ForEach(TransportManager.Method.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if transport.method == .tcp {
                        HStack {
                            Text("Host")
                            Spacer()

                            TextField("t1.local", text: $transport.host)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 220)
                        }

                        HStack {
                            Text("Port")
                            Spacer()

                            TextField(
                                "2000",
                                text: Binding(
                                    get: { String(transport.port) },
                                    set: { newValue in
                                        let digits = newValue.filter(\.isNumber)
                                        if let value = UInt16(digits) {
                                            transport.port = value
                                        } else if digits.isEmpty {
                                            transport.port = 2000
                                        }
                                    }
                                )
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(stateText)
                            .foregroundStyle(statusColor)
                            .font(.subheadline.weight(.semibold))
                    }

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            transport.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(transport.state == .disconnected)

                        Button {
                            transport.connect()
                        } label: {
                            ZStack {
                                Text("Connect")
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)

                                HStack {
                                    Spacer()
                                    if transport.state == .connecting || transport.state == .reconnecting {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(transport.state == .connected || transport.state == .connecting || transport.state == .reconnecting)
                    }
                }

                if transport.method == .tcp {
                    Section("Scale Actions") {

                        Button {
                            transport.sendZeroCommand()
                        } label: {
                            Label("ZERO / TARE", systemImage: "scalemass.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isTCPConnected)

                        Text("Use this when the platform is empty. Sends the T1 zero/tare command.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Weight Stability") {

                        Picker("Stability Source", selection: $settings.stabilitySource) {
                            ForEach(AppSettings.StabilitySource.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }

                        DefaultMarkedSliderRow(
                            title: "Stable Window",
                            valueText: "\(settings.inferredStableWindowMs) ms",
                            value: Binding(
                                get: { Double(settings.inferredStableWindowMs) },
                                set: { settings.inferredStableWindowMs = Int($0.rounded()) }
                            ),
                            range: 300...2500,
                            step: 100,
                            defaultValue: Double(defaultStableWindowMs)
                        )

                        DefaultMarkedSliderRow(
                            title: "Stable Tolerance",
                            valueText: String(format: "%.2f kg", settings.inferredStableMaxDeltaKg),
                            value: $settings.inferredStableMaxDeltaKg,
                            range: 0.10...2.00,
                            step: 0.05,
                            defaultValue: defaultStableToleranceKg
                        )

                        DefaultMarkedSliderRow(
                            title: "Hold Time",
                            valueText: "\(settings.stableHoldMilliseconds) ms",
                            value: Binding(
                                get: { Double(settings.stableHoldMilliseconds) },
                                set: { settings.stableHoldMilliseconds = Int($0.rounded()) }
                            ),
                            range: 0...2000,
                            step: 50,
                            defaultValue: Double(defaultHoldTimeMs)
                        )

                        DefaultMarkedSliderRow(
                            title: "Display Smoothing",
                            valueText: String(format: "%.2f", settings.displaySmoothingAlpha),
                            value: $settings.displaySmoothingAlpha,
                            range: 0.05...1.00,
                            step: 0.05,
                            defaultValue: defaultDisplaySmoothing
                        )

                        DefaultMarkedSliderRow(
                            title: "Snap Big Changes",
                            valueText: String(format: "%.1f kg", settings.displaySnapJumpKg),
                            value: $settings.displaySnapJumpKg,
                            range: 0.5...10.0,
                            step: 0.1,
                            defaultValue: defaultSnapBigChangesKg
                        )

                        DefaultMarkedSliderRow(
                            title: "Min Re-Lock Change",
                            valueText: String(format: "%.1f kg", settings.minRelockChangeKg),
                            value: $settings.minRelockChangeKg,
                            range: 0.0...3.0,
                            step: 0.1,
                            defaultValue: defaultMinRelockChangeKg
                        )

                        Toggle("Force Stable", isOn: $settings.forceStable)

                        Button("Restore Defaults") {
                            restoreDefaults()
                        }
                        .buttonStyle(.bordered)

                        Text("Red marker = saved default position. Restore Defaults returns all sliders and toggles on this T1 screen to those values.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("Higher window, tolerance and hold time make locking calmer. Min Re-Lock Change stops tiny weight shifts from saving again for the same animal.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Polling / Request Mode") {

                        Toggle("Request Required", isOn: $transport.requestModeEnabled)

                        DefaultMarkedSliderRow(
                            title: "Poll Interval",
                            valueText: transport.pollIntervalString,
                            value: $transport.pollIntervalSeconds,
                            range: 0.05...10,
                            step: 0.05,
                            defaultValue: defaultPollIntervalSeconds
                        )

                        Picker("Request Format", selection: $transport.requestFormat) {
                            Text("ASCII <C1>").tag(TCPTransport.RequestFormat.asciiAngleC1)
                            Text("Binary 0xC1").tag(TCPTransport.RequestFormat.binaryC1)
                            Text("ASCII <E21>").tag(TCPTransport.RequestFormat.asciiE21)
                            Text("Custom ASCII").tag(TCPTransport.RequestFormat.customASCII)
                        }

                        if transport.requestFormat == .customASCII {
                            TextField("Custom Command", text: $transport.customASCIICommand)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Picker("Line Ending", selection: $transport.pollLineEnding) {
                            Text("None").tag(TCPTransport.LineEnding.none)
                            Text("CR").tag(TCPTransport.LineEnding.cr)
                            Text("LF").tag(TCPTransport.LineEnding.lf)
                            Text("CRLF").tag(TCPTransport.LineEnding.crlf)
                        }
                    }

                    Section("Keepalive") {

                        Toggle("Enabled", isOn: $transport.keepAliveEnabled)

                        DefaultMarkedSliderRow(
                            title: "Interval",
                            valueText: "\(Int(transport.keepAliveIntervalSeconds)) s",
                            value: $transport.keepAliveIntervalSeconds,
                            range: 1...30,
                            step: 1,
                            defaultValue: defaultKeepAliveIntervalSeconds
                        )
                    }

                    Section("Burst Probes") {

                        Toggle("Burst Variants On Connect", isOn: $transport.burstBothPollVariantsOnConnect)

                        DefaultMarkedSliderRow(
                            title: "Burst Ticks",
                            valueText: "\(transport.burstTicksAfterConnect)",
                            value: Binding(
                                get: { Double(transport.burstTicksAfterConnect) },
                                set: { transport.burstTicksAfterConnect = Int($0.rounded()) }
                            ),
                            range: 0...30,
                            step: 1,
                            defaultValue: Double(defaultBurstTicksAfterConnect)
                        )

                        Button {
                            transport.sendProbeSequence()
                        } label: {
                            Label("Send Probe Sequence", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isTCPConnected)
                    }

                    Section("Watchdog") {

                        Toggle("Enabled", isOn: $transport.watchdogEnabled)

                        DefaultMarkedSliderRow(
                            title: "Silence Timeout",
                            valueText: "\(Int(transport.watchdogSilenceSeconds)) s",
                            value: $transport.watchdogSilenceSeconds,
                            range: 2...120,
                            step: 1,
                            defaultValue: defaultWatchdogSilenceSeconds
                        )
                    }
                }

                Section("Diagnostics") {
                    NavigationLink("T1 Diagnostics") {
                        ConnectionDiagnosticsView()
                    }
                    NavigationLink("T1 Raw Log") {
                        RawLogView()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("T1 Scale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            captureDefaultsIfNeeded()
        }
    }

    private var isTCPConnected: Bool {
        transport.method == .tcp && transport.state == .connected
    }

    private var stateText: String {
        switch transport.state {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch transport.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private func captureDefaultsIfNeeded() {
        guard !didCaptureDefaults else { return }
        didCaptureDefaults = true

        defaultStableWindowMs = settings.inferredStableWindowMs
        defaultStableToleranceKg = settings.inferredStableMaxDeltaKg
        defaultHoldTimeMs = settings.stableHoldMilliseconds
        defaultDisplaySmoothing = settings.displaySmoothingAlpha
        defaultSnapBigChangesKg = settings.displaySnapJumpKg
        defaultMinRelockChangeKg = settings.minRelockChangeKg
        defaultForceStable = settings.forceStable

        defaultPollIntervalSeconds = transport.pollIntervalSeconds
        defaultKeepAliveIntervalSeconds = transport.keepAliveIntervalSeconds
        defaultBurstTicksAfterConnect = transport.burstTicksAfterConnect
        defaultWatchdogSilenceSeconds = transport.watchdogSilenceSeconds

        defaultRequestRequired = transport.requestModeEnabled
        defaultKeepAliveEnabled = transport.keepAliveEnabled
        defaultBurstVariantsOnConnect = transport.burstBothPollVariantsOnConnect
        defaultWatchdogEnabled = transport.watchdogEnabled
    }

    private func restoreDefaults() {
        settings.inferredStableWindowMs = defaultStableWindowMs
        settings.inferredStableMaxDeltaKg = defaultStableToleranceKg
        settings.stableHoldMilliseconds = defaultHoldTimeMs
        settings.displaySmoothingAlpha = defaultDisplaySmoothing
        settings.displaySnapJumpKg = defaultSnapBigChangesKg
        settings.minRelockChangeKg = defaultMinRelockChangeKg
        settings.forceStable = defaultForceStable

        transport.requestModeEnabled = defaultRequestRequired
        transport.pollIntervalSeconds = defaultPollIntervalSeconds
        transport.keepAliveEnabled = defaultKeepAliveEnabled
        transport.keepAliveIntervalSeconds = defaultKeepAliveIntervalSeconds
        transport.burstBothPollVariantsOnConnect = defaultBurstVariantsOnConnect
        transport.burstTicksAfterConnect = defaultBurstTicksAfterConnect
        transport.watchdogEnabled = defaultWatchdogEnabled
        transport.watchdogSilenceSeconds = defaultWatchdogSilenceSeconds
    }
}

// =====================================================
// MARK: - Default-marked slider row
// =====================================================

private struct DefaultMarkedSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                Slider(
                    value: $value,
                    in: range,
                    step: step
                )

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let usableWidth = max(0, width - 28)
                    let fraction = sliderFraction(defaultValue)
                    let x = 14 + (usableWidth * fraction)

                    Rectangle()
                        .fill(.red)
                        .frame(width: 2, height: 18)
                        .position(x: x, y: proxy.size.height / 2)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 28)
        }
    }

    private func sliderFraction(_ v: Double) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// =====================================================
// MARK: - Racewell (manager-backed)
// =====================================================

struct RacewellConnectivityView: View {

    @EnvironmentObject private var racewell: RacewellManager

    private let gateColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            GlassBackground()

            List {

                Section("Status") {
                    StatusIndicatorView(title: "Racewell", state: racewell.state)

                    HStack {
                        Text("Drafter")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Section("Connection") {
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            racewell.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(racewell.state == .disconnected)

                        Button {
                            racewell.connect()
                        } label: {
                            ZStack {
                                Text("Connect")
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)

                                HStack {
                                    Spacer()
                                    if racewell.state == .connecting || racewell.state == .reconnecting {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            racewell.state == .connected ||
                            racewell.state == .connecting ||
                            racewell.state == .reconnecting
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    Button {
                        racewell.refreshStatus()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Section("Gate Test") {
                    LazyVGrid(columns: gateColumns, spacing: 12) {
                        gateButton(
                            title: "Left",
                            systemImage: "arrowshape.left.fill",
                            tint: .blue
                        ) {
                            racewell.leftGate()
                        }

                        gateButton(
                            title: "Centre",
                            systemImage: "minus.rectangle.fill",
                            tint: .indigo
                        ) {
                            racewell.centreGate()
                        }

                        gateButton(
                            title: "Right",
                            systemImage: "arrowshape.right.fill",
                            tint: .blue
                        ) {
                            racewell.rightGate()
                        }
                    }
                    .padding(.vertical, 4)

                    Text("Left turns relay 1 on. Right turns relay 2 on. Centre turns relay 1 and 2 off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Catch / Release") {
                    HStack(spacing: 12) {
                        actionButton(
                            title: "Catch",
                            systemImage: "lock.fill",
                            tint: .green
                        ) {
                            racewell.catchPulse()
                        }

                        actionButton(
                            title: "Release",
                            systemImage: "lock.open.fill",
                            tint: .orange
                        ) {
                            racewell.releasePulse()
                        }
                    }

                    Text("Catch and Release pulse for 3 seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tilt Control") {
                    HStack(spacing: 12) {
                        MomentaryPressButton(
                            title: "Tilt Up",
                            systemImage: "arrow.up",
                            tint: .teal,
                            onPress: { racewell.tiltUpOn() },
                            onRelease: { racewell.tiltUpOff() }
                        )

                        MomentaryPressButton(
                            title: "Tilt Down",
                            systemImage: "arrow.down",
                            tint: .teal,
                            onPress: { racewell.tiltDownOn() },
                            onRelease: { racewell.tiltDownOff() }
                        )
                    }

                    Text("Tilt controls are active only while your finger is pressing the button.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Pause") {
                    Button {
                        racewell.togglePause()
                    } label: {
                        Label(
                            racewell.pauseIsOn ? "Pause On" : "Pause Off",
                            systemImage: racewell.pauseIsOn ? "pause.circle.fill" : "pause.circle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(racewell.pauseIsOn ? .red : .purple)

                    Text("Pause is a latching toggle on relay 7.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Safety") {
                    Button(role: .destructive) {
                        racewell.allOff()
                    } label: {
                        Label("All Off", systemImage: "power")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                }

                Section("Log") {
                    if racewell.log.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(racewell.log.suffix(40)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }

                            Divider().opacity(0.2)
                        }
                    }

                    Button("Clear Log", role: .destructive) {
                        racewell.clearLog()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Racewell Drafter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            racewell.refreshStatus()
        }
    }

    private var statusText: String {
        switch racewell.state {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch racewell.state {
        case .connected: return .green
        case .connecting, .reconnecting, .scanning: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    @ViewBuilder
    private func gateButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)

                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

private struct MomentaryPressButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPressed ? tint.opacity(0.95) : tint.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isPressed ? tint : tint.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(isPressed ? .white : tint)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            onRelease()
                        }
                    }
            )
    }
}

// =====================================================
// MARK: - Stick Reader (BLE scan + pick + connect + EID)
// =====================================================

struct StickReaderConnectivityView: View {

    @EnvironmentObject private var stick: StickReaderManager

    var body: some View {
        ZStack {
            GlassBackground()

            List {

                Section("Status") {
                    StatusIndicatorView(title: "Stick Reader", state: stick.state)

                    HStack {
                        Text("Connected")
                        Spacer()
                        Text(stick.connectedName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Section("Scan") {

                    if stick.isScanning {
                        Button(role: .destructive) {
                            stick.stopScan()
                        } label: {
                            HStack {
                                Label("Stop Scan", systemImage: "stop.circle")
                                Spacer()
                                ProgressView()
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            stick.startScan()
                        } label: {
                            Label("Start Scan", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if stick.discovered.isEmpty {
                        Text(stick.isScanning ? "Scanning… bring the stick closer / wake it up." : "No devices found yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap a device to connect.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !stick.discovered.isEmpty {
                    Section("Nearby Devices") {
                        ForEach(stick.discovered) { d in
                            Button {
                                stick.connect(to: d.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(d.id.uuidString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text("\(d.rssi)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(stick.state == .connecting || stick.state == .reconnecting)
                        }
                    }
                }

                Section("Connection") {
                    Button(role: .destructive) {
                        stick.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(stick.state == .disconnected && stick.connectedName == "—")

                    Text("Once connected, scan a tag. If the reader streams EIDs over BLE notify, the app will show it below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tag Scan") {
                    HStack {
                        Text("Last EID")
                        Spacer()
                        Text(stick.lastScannedEID)
                            .font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)
                    }

                    Text("If this stays blank, check the Log below for RX bytes. We can then lock onto the correct characteristic/format.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Log") {
                    if stick.log.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stick.log.suffix(60)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            Divider().opacity(0.2)
                        }
                    }

                    Button("Clear Log", role: .destructive) {
                        stick.clearLog()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Tru-Test Stick")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// =====================================================
// MARK: - Small row helper (keeps the hub tidy)
// =====================================================

private struct SettingsLikeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
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
