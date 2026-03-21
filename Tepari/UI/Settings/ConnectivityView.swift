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
                Section {
                    ConnectivityIntroCard(
                        title: "Connectivity",
                        subtitle: "Set up and test connected hardware used by weighing, drafting, scanning and dosing sessions.",
                        systemImage: "bolt.horizontal.circle.fill",
                        tint: .yellow
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Devices") {
                    NavigationLink {
                        T1ConnectivityView()
                    } label: {
                        ConnectivityMenuRow(
                            title: "T1 Scale with integrated EID",
                            subtitle: "Wi-Fi TCP connection, weight locking and diagnostics",
                            systemImage: "scalemass.fill",
                            tint: .blue
                        )
                    }

                    NavigationLink {
                        RacewellConnectivityView()
                    } label: {
                        ConnectivityMenuRow(
                            title: "Racewell Drafter",
                            subtitle: "Connect, gate test and relay controls",
                            systemImage: "arrow.triangle.branch",
                            tint: .orange
                        )
                    }

                    NavigationLink {
                        StickReaderConnectivityView()
                    } label: {
                        ConnectivityMenuRow(
                            title: "Stick Reader",
                            subtitle: "BLE scan, connect and tag reads",
                            systemImage: "dot.radiowaves.left.and.right",
                            tint: .green
                        )
                    }

                    NavigationLink {
                        XRP2iConnectivityView()
                    } label: {
                        ConnectivityMenuRow(
                            title: "XRP2i Panel Reader",
                            subtitle: "Panel antenna and continuous tag read",
                            systemImage: "rectangle.connected.to.line.below",
                            tint: .purple
                        )
                    }

                    NavigationLink {
                        TepariGunConnectivityView()
                    } label: {
                        ConnectivityMenuRow(
                            title: "Tepari Dosing Gun",
                            subtitle: "Dose trigger and animal ID integration",
                            systemImage: "syringe.fill",
                            tint: .pink
                        )
                    }
                }

                Section("How this works") {
                    Text("Set up devices here first. Later, the session wizard can ask what functions are needed and use the configured devices automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
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
                Section {
                    ConnectivityHeaderCard(
                        title: "T1 Scale",
                        subtitle: "Wi-Fi TCP connection, commands, stability tuning and diagnostics.",
                        systemImage: "scalemass.fill",
                        tint: .blue
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Quick Setup") {
                    Button {
                        transport.useT1Defaults()
                    } label: {
                        Label("Use T1 Defaults (TCP t1.local:2000)", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("For T1, use Wi-Fi TCP. Demo mode is for testing without hardware.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    ConnectivityStatusRow(
                        title: "Scale",
                        value: stateText,
                        tint: statusColor
                    )

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
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isTCPConnected)

                        Text("Use this when the platform is empty. Sends the T1 zero or tare command.")
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
                    NavigationLink {
                        ConnectionDiagnosticsView()
                    } label: {
                        ConnectivityInlineRow(
                            title: "T1 Diagnostics",
                            subtitle: "Connection details and inspection tools",
                            systemImage: "stethoscope",
                            tint: .blue
                        )
                    }

                    NavigationLink {
                        RawLogView()
                    } label: {
                        ConnectivityInlineRow(
                            title: "T1 Raw Log",
                            subtitle: "Incoming and outgoing transport data",
                            systemImage: "doc.text.magnifyingglass",
                            tint: .indigo
                        )
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
                Section {
                    ConnectivityHeaderCard(
                        title: "Racewell Drafter",
                        subtitle: "Connection status, gate tests, tilt controls and relay actions.",
                        systemImage: "arrow.triangle.branch",
                        tint: .orange
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    StatusIndicatorView(title: "Racewell", state: racewell.state)

                    ConnectivityStatusRow(
                        title: "Drafter",
                        value: statusText,
                        tint: statusColor
                    )
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

                    Button {
                        racewell.refreshStatus()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                Section {
                    ConnectivityHeaderCard(
                        title: "Stick Reader",
                        subtitle: "BLE device scan, connection state and live EID reads.",
                        systemImage: "dot.radiowaves.left.and.right",
                        tint: .green
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    StatusIndicatorView(title: "Stick Reader", state: stick.state)

                    ConnectivityStatusRow(
                        title: "Connected",
                        value: stick.connectedName,
                        tint: .secondary
                    )
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if stick.discovered.isEmpty {
                        Text(stick.isScanning ? "Scanning… bring the stick closer or wake it up." : "No devices found yet.")
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
                                ConnectivityDiscoveredDeviceRow(
                                    title: d.name,
                                    subtitle: d.id.uuidString,
                                    trailing: "\(d.rssi)",
                                    systemImage: "dot.radiowaves.left.and.right",
                                    tint: .green
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(stick.state == .connecting || stick.state == .reconnecting)
                        }
                    }
                }

                Section("Connection") {
                    Button(role: .destructive) {
                        stick.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                    Text("If this stays blank, check the log below for RX bytes. That will help lock onto the right characteristic or format.")
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
// MARK: - Styling helpers
// =====================================================

private struct ConnectivityIntroCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 52, height: 52)

                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct ConnectivityHeaderCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct ConnectivityMenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 42, height: 42)

                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct ConnectivityInlineRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 34, height: 34)

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ConnectivityStatusRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(title)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ConnectivityDiscoveredDeviceRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 34, height: 34)

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
