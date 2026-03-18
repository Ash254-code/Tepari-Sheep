import SwiftUI
import UIKit

struct TepariGunConnectivityView: View {

    @EnvironmentObject private var tepariGun: TepariGunManager
    @EnvironmentObject private var gunListener: GunListener

    @State private var hostText: String = ""
    @State private var portText: String = ""
    @State private var manualCommandText: String = ""
    @State private var lastTriedPacketText: String = ""

    @State private var sendTwice: Bool = false
    @State private var sendThreeTimes: Bool = false
    @State private var delayBeforeSendMs: Double = 0
    @State private var gapBetweenRepeatsMs: Double = 300
    @State private var appendCR: Bool = false
    @State private var appendLF: Bool = false
    @State private var forceWrapped: Bool = false

    private let nearbyDosePackets: [String] = [
        "<170>", "<175>", "<180>", "<185>", "<190>", "<195>", "<200>",
        "170", "175", "180", "185", "190", "195", "200"
    ]

    private let simplePackets: [String] = [
        "<25>", "<250>", "<285>", "25", "250", "285"
    ]

    private let dPackets: [String] = [
        "<D17>", "<D17.0>", "<D18>", "<D18.0>", "<D19>", "<D19.0>", "<D20>", "<D20.0>",
        "<D21>", "<D21.0>", "<D25>", "<D25.0>", "<D250>"
    ]

    private let structuredPackets: [String] = [
        "<R0403170>", "<R0403180>", "<R0403190>", "<R0403195>", "<R0403200>", "<R0403210>", "<R0403250>",
        "<W0403170>", "<W0403180>", "<W0403190>", "<W0403210>", "<W0403250>",
        "<S0403170>", "<S0403180>", "<S0403190>", "<S0403210>", "<S0403250>",
        "<R1403170>", "<R1403180>", "<R1403190>", "<R1403210>", "<R1403250>"
    ]

    var body: some View {
        ZStack {
            GlassBackground()

            List {

                Section("Connection Mode") {
                    Picker("Mode", selection: Binding(
                        get: { tepariGun.connectionMode },
                        set: { newMode in
                            tepariGun.updateConnectionMode(newMode)

                            if newMode == .client {
                                gunListener.stop()
                            } else {
                                tepariGun.disconnect()
                            }
                        }
                    )) {
                        ForEach(TepariGunManager.ConnectionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isListenerMode {
                        Text("Use this with the gun in Custom WiFi mode. The gun connects to this iPad on port 2000.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Use this with the gun in Fusion mode. The iPad connects directly to the gun IP.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Gun Status") {
                    HStack {
                        Text("Enabled")
                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { tepariGun.isEnabled },
                            set: { tepariGun.setEnabled($0) }
                        ))
                        .labelsHidden()
                    }

                    HStack {
                        Text("State")
                        Spacer()
                        Text(activeStateText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeStatusColor)
                    }

                    HStack {
                        Text(isListenerMode ? "Listening" : "Reachable")
                        Spacer()
                        Text(activeReachabilityText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeReachabilityColor)
                    }

                    HStack {
                        Text("Connected")
                        Spacer()
                        Text(activeConnectedText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeConnectedColor)
                    }

                    if isListenerMode {
                        HStack {
                            Text("Last Peer")
                            Spacer()
                            Text(gunListener.lastPeer)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }

                    if !isListenerMode {
                        HStack {
                            Text("Host")
                            Spacer()

                            TextField("192.168.3.80", text: $hostText)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(width: 170)
                                .onSubmit {
                                    commitHost()
                                }
                        }
                    }

                    HStack {
                        Text(isListenerMode ? "Listen Port" : "Port")
                        Spacer()

                        TextField("2000", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .onChange(of: portText) { _, newValue in
                                let digits = newValue.filter(\.isNumber)
                                if digits != newValue {
                                    portText = digits
                                }
                            }
                            .onSubmit {
                                commitPort()
                            }
                    }
                }

                Section("Connection Behaviour") {
                    if !isListenerMode {
                        HStack {
                            Text("Reconnect Per Command")
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { tepariGun.reconnectPerCommand },
                                set: { tepariGun.setReconnectPerCommand($0) }
                            ))
                            .labelsHidden()
                        }
                    } else {
                        HStack {
                            Text("Listener Queue")
                            Spacer()
                            Text("On")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Auto-wrap < >")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { tepariGun.autoWrapAngleBrackets },
                            set: { tepariGun.setAutoWrapAngleBrackets($0) }
                        ))
                        .labelsHidden()
                    }

                    Picker("Line Ending", selection: Binding(
                        get: { tepariGun.lineEnding },
                        set: { tepariGun.updateLineEnding($0) }
                    )) {
                        ForEach(TepariGunManager.LineEnding.allCases) { ending in
                            Text(ending.label).tag(ending)
                        }
                    }
                }

                Section("Protocol Test Bench") {
                    HStack {
                        Text("Force Wrap Test Packet")
                        Spacer()
                        Toggle("", isOn: $forceWrapped)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Append CR")
                        Spacer()
                        Toggle("", isOn: $appendCR)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Append LF")
                        Spacer()
                        Toggle("", isOn: $appendLF)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Send Twice")
                        Spacer()
                        Toggle("", isOn: $sendTwice)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Send Three Times")
                        Spacer()
                        Toggle("", isOn: $sendThreeTimes)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Delay Before Send")
                            Spacer()
                            Text("\(Int(delayBeforeSendMs)) ms")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $delayBeforeSendMs, in: 0...3000, step: 50)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Gap Between Repeats")
                            Spacer()
                            Text("\(Int(gapBetweenRepeatsMs)) ms")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $gapBetweenRepeatsMs, in: 100...3000, step: 50)
                    }

                    Button("Reset Test Bench") {
                        sendTwice = false
                        sendThreeTimes = false
                        delayBeforeSendMs = 0
                        gapBetweenRepeatsMs = 300
                        appendCR = false
                        appendLF = false
                        forceWrapped = false
                    }
                    .buttonStyle(.bordered)
                }

                Section("Control") {
                    Button {
                        if isListenerMode {
                            commitPort()
                            startListener()
                        } else {
                            commitHost()
                            commitPort()
                            tepariGun.connect()
                        }
                    } label: {
                        HStack {
                            Label(
                                isListenerMode ? "Start Listening" : "Connect to Gun",
                                systemImage: "dot.radiowaves.left.and.right"
                            )
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPrimaryControlDisabled)

                    Button(role: .destructive) {
                        if isListenerMode {
                            gunListener.stop()
                        } else {
                            tepariGun.disconnect()
                        }
                    } label: {
                        Label(
                            isListenerMode ? "Stop Listening" : "Disconnect",
                            systemImage: "xmark.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSecondaryControlDisabled)
                }

                if isListenerMode {
                    Section("Custom WiFi Setup") {
                        Text("Set the gun to Custom WiFi.")
                        Text("SSID: your Wi-Fi network")
                        Text("Password: your Wi-Fi password")
                        Text("Host IP: this iPad’s current IP")
                        Text("Port: 2000")
                        Text("Then press Start Listening here and wait for the gun to connect.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quick Tests • Simple") {
                    quickPacketButton("<250>")
                    quickPacketButton("<285>")
                    quickPacketButton("<25>")
                    quickPacketButton("25")
                    quickPacketButton("250")
                    quickPacketButton("285")
                }

                Section("Quick Tests • Nearby Dose Values") {
                    ForEach(nearbyDosePackets, id: \.self) { packet in
                        quickPacketButton(packet)
                    }
                }

                Section("Quick Tests • D Format") {
                    ForEach(dPackets, id: \.self) { packet in
                        quickPacketButton(packet)
                    }
                }

                Section("Quick Tests • Structured Guesses") {
                    ForEach(structuredPackets, id: \.self) { packet in
                        quickPacketButton(packet)
                    }
                }

                Section("Quick Tests • Utility") {
                    Button {
                        runPacket("PING")
                    } label: {
                        Label("Send PING", systemImage: "paperplane")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        runPacket("<R0403250>")
                    } label: {
                        Label("Send 25.0 mL (R04 format)", systemImage: "paperplane")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if isListenerMode {
                            runPacket("<250>")
                            lastTriedPacketText = "<250>"
                        } else {
                            tepariGun.sendTestDose25mL()
                            lastTriedPacketText = "25 mL via dose builder"
                        }
                    } label: {
                        Label(
                            isListenerMode ? "Send <250>" : "Send 25 mL via dose builder",
                            systemImage: "syringe.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("Manual Command") {
                    TextField("Enter exact packet", text: $manualCommandText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textSelection(.enabled)
                        .lineLimit(1...5)

                    Button {
                        sendManualCommand()
                    } label: {
                        HStack {
                            Label(isSendingText, systemImage: "paperplane.fill")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tepariGun.isEnabled)

                    if !lastTriedPacketText.isEmpty {
                        HStack {
                            Text("Last tried")
                            Spacer()
                            Text(lastTriedPacketText)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    Button {
                        guard !lastTriedPacketText.isEmpty else { return }
                        runPacket(lastTriedPacketText)
                    } label: {
                        Label("Repeat Last Packet", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(lastTriedPacketText.isEmpty || !tepariGun.isEnabled)

                    Text("Goal: test exact strings, suffixes and timing. TX ok only means bytes left the iPad, not that the gun accepted the dose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Suggested Test Order") {
                    if isListenerMode {
                        Text("1. Put gun in Custom WiFi")
                        Text("2. Start Listening on port 2000")
                        Text("3. Wait for Last Peer to appear")
                        Text("4. Then try <250> first")
                        Text("5. Pull trigger and watch the gun screen")
                    } else {
                        Text("1. Reconnect Per Command ON")
                        Text("2. Auto-wrap OFF")
                        Text("3. Line Ending None")
                        Text("4. Try <250>, <D250>, <D25.0>")
                        Text("5. Then try CR / LF suffixes")
                        Text("6. Pull trigger between tests and watch the gun screen")
                    }
                }

                Section("Last TX") {
                    HStack {
                        Text("Command")
                        Spacer()
                        Text(activeLastCommandText)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Time")
                        Spacer()
                        if let at = activeLastSentAt {
                            Text(at, style: .time)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Dose Sent")
                        Spacer()
                        if let dose = tepariGun.lastDoseSent, !isListenerMode {
                            let unitText = tepariGun.lastDoseUnit?.rawValue ?? ""
                            Text("\(formatDose(dose)) \(unitText)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Last Response") {
                    HStack {
                        Text("Response")
                        Spacer()
                        Text(activeLastResponseText)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }

                if isListenerMode {
                    Section("Listener Decode") {
                        HStack {
                            Text("Last Packet")
                            Spacer()
                            Text(gunListener.lastPacket ?? "—")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text("Trigger Dose")
                            Spacer()
                            if let dose = gunListener.lastTriggerDoseML {
                                Text("\(formatDose(dose)) mL")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("Trigger Time")
                            Spacer()
                            if let at = gunListener.lastTriggerAt {
                                Text(at, style: .time)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Diagnostics") {
                    if let err = activeLastErrorText, !err.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Error")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(err)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }

                    Button("Clear Status", role: .destructive) {
                        if isListenerMode {
                            gunListener.clearStatus()
                        } else {
                            tepariGun.clearStatus()
                        }
                    }
                }

                Section("Log") {
                    HStack(spacing: 10) {
                        Button("Clear Log", role: .destructive) {
                            if isListenerMode {
                                gunListener.clearLog()
                            } else {
                                tepariGun.clearLog()
                            }
                        }

                        Spacer()

                        Button {
                            UIPasteboard.general.string = formattedLogText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(activeLogCount == 0)
                    }

                    if activeLogCount == 0 {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                    } else if isListenerMode {
                        ForEach(gunListener.log.suffix(160)) { entry in
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
                    } else {
                        ForEach(tepariGun.log.suffix(160)) { entry in
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
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Tepari Dosing Gun")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hostText = tepariGun.host
            portText = String(tepariGun.port)

            if manualCommandText.isEmpty {
                manualCommandText = "<250>"
            }
        }
        .onChange(of: tepariGun.connectionMode) { _, _ in
            hostText = tepariGun.host
            portText = String(tepariGun.port)
        }
    }

    private var isListenerMode: Bool {
        tepariGun.connectionMode == .listener
    }

    private var activeStateText: String {
        if isListenerMode {
            return gunListener.state.label
        } else {
            return tepariGun.state.label
        }
    }

    private var activeStatusColor: Color {
        if isListenerMode {
            switch gunListener.state {
            case .listening: return .green
            case .starting: return .orange
            case .error: return .red
            case .stopped: return .secondary
            }
        } else {
            switch tepariGun.state {
            case .connected: return .green
            case .connecting: return .orange
            case .error: return .red
            case .disconnected: return .secondary
            }
        }
    }

    private var activeReachabilityText: String {
        if isListenerMode {
            return gunListener.state == .listening ? "Yes" : "No"
        } else {
            return tepariGun.isVisible ? "Yes" : "No"
        }
    }

    private var activeReachabilityColor: Color {
        if isListenerMode {
            return gunListener.state == .listening ? .green : .secondary
        } else {
            return tepariGun.isVisible ? .green : .secondary
        }
    }

    private var activeConnectedText: String {
        if isListenerMode {
            return gunListener.lastPeer == "—" ? "No" : "Yes"
        } else {
            return tepariGun.isConnected ? "Yes" : "No"
        }
    }

    private var activeConnectedColor: Color {
        if isListenerMode {
            return gunListener.lastPeer == "—" ? .secondary : .green
        } else {
            return tepariGun.isConnected ? .green : .secondary
        }
    }

    private var isPrimaryControlDisabled: Bool {
        if isListenerMode {
            return !tepariGun.isEnabled || gunListener.state == .starting || gunListener.state == .listening
        } else {
            return !tepariGun.isConfigured || tepariGun.state == .connecting
        }
    }

    private var isSecondaryControlDisabled: Bool {
        if isListenerMode {
            return gunListener.state == .stopped
        } else {
            return tepariGun.state == .disconnected && !tepariGun.isVisible
        }
    }

    private var isSendingText: String {
        if isListenerMode {
            return "Send Manual Command"
        } else {
            return tepariGun.isSending ? "Sending…" : "Send Manual Command"
        }
    }

    private var activeLastCommandText: String {
        if isListenerMode {
            return gunListener.lastSentText ?? "—"
        } else {
            return tepariGun.lastCommandText ?? "—"
        }
    }

    private var activeLastSentAt: Date? {
        if isListenerMode {
            return gunListener.lastSentAt
        } else {
            return tepariGun.lastSentAt
        }
    }

    private var activeLastResponseText: String {
        if isListenerMode {
            return gunListener.lastMessageText ?? "—"
        } else {
            return tepariGun.lastResponseText ?? "—"
        }
    }

    private var activeLastErrorText: String? {
        if isListenerMode {
            return gunListener.lastErrorText
        } else {
            return tepariGun.lastErrorText
        }
    }

    private var activeLogCount: Int {
        if isListenerMode {
            return gunListener.log.count
        } else {
            return tepariGun.log.count
        }
    }

    private var formattedLogText: String {
        if isListenerMode {
            return gunListener.log
                .map { entry in
                    let time = entry.timestamp.formatted(date: .omitted, time: .standard)
                    return "[\(time)] \(entry.message)"
                }
                .joined(separator: "\n")
        } else {
            return tepariGun.log
                .map { entry in
                    let time = entry.timestamp.formatted(date: .omitted, time: .standard)
                    return "[\(time)] \(entry.message)"
                }
                .joined(separator: "\n")
        }
    }

    private func quickPacketButton(_ packet: String) -> some View {
        Button {
            runPacket(packet)
        } label: {
            Label("Send \(packet)", systemImage: "paperplane")
        }
        .buttonStyle(.bordered)
    }

    private func runPacket(_ rawPacket: String) {
        let prepared = preparePacket(rawPacket)
        lastTriedPacketText = prepared

        let repeatCount: Int = sendThreeTimes ? 3 : (sendTwice ? 2 : 1)
        let startDelay = delayBeforeSendMs / 1000.0
        let repeatGap = gapBetweenRepeatsMs / 1000.0

        for index in 0..<repeatCount {
            let delay = startDelay + (Double(index) * repeatGap)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if isListenerMode {
                    gunListener.sendRaw(prepared)
                } else {
                    tepariGun.sendRawCommand(prepared)
                }
            }
        }
    }

    private func preparePacket(_ rawPacket: String) -> String {
        var out = rawPacket.trimmingCharacters(in: .whitespacesAndNewlines)

        if forceWrapped && !out.hasPrefix("<") && !out.hasSuffix(">") {
            out = "<\(out)>"
        }

        if appendCR {
            out += "\r"
        }
        if appendLF {
            out += "\n"
        }

        return out
    }

    private func sendManualCommand() {
        let cmd = manualCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        runPacket(cmd)
    }

    private func commitHost() {
        let trimmed = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        hostText = trimmed
        tepariGun.updateHost(trimmed)
    }

    private func commitPort() {
        let digits = portText.filter(\.isNumber)
        let port = Int(digits) ?? 2000
        let safe = min(max(1, port), 65535)
        portText = String(safe)
        tepariGun.updatePort(safe)
    }

    private func startListener() {
        let digits = portText.filter(\.isNumber)
        let portValue = UInt16(digits) ?? 2000
        gunListener.start(port: portValue)
    }

    private func formatDose(_ dose: Double) -> String {
        if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", dose)
        } else if (dose * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", dose)
        } else {
            return String(format: "%.2f", dose)
        }
    }
}
