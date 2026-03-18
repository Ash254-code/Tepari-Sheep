import SwiftUI

/// ✅ T1 Diagnostics
/// This view remains the same functionality-wise, but it’s now clearly positioned
/// as diagnostics for the Te Pari T1 (Wi-Fi TCP).
///
/// Racewell + Tru-Test stick will get their own diagnostics screens later.
struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var settings: AppSettings

    @State private var manualCommand = ""

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // =====================================================
                    // T1 Setup Reminder
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Te Pari T1")
                                .font(.headline)

                            Text("For live yards use, set Method to Wi-Fi (TCP) and connect to the T1 access point (or yard Wi-Fi if configured).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                transport.useT1Defaults()
                            } label: {
                                Label("Use T1 Defaults (TCP t1.local:2000)", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // =====================================================
                    // Weighing / Demo Helpers
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weighing / Demo")
                                .font(.headline)

                            // Always show Stable Hold here (you kept saying it's "missing")
                            Stepper(
                                "Stable Hold: \(settings.stableHoldMilliseconds) ms",
                                value: $settings.stableHoldMilliseconds,
                                in: 0...4000,
                                step: 50
                            )
                            .font(.subheadline)

                            Divider().opacity(0.35)

                            // Force stable only makes sense in Demo
                            if transport.method == .demo {
                                Toggle("Force Stable", isOn: $settings.forceStable)
                                    .font(.subheadline)
                            } else {
                                Text("Force Stable is available in Demo mode.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // =====================================================
                    // Connection State
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connection")
                                .font(.headline)

                            StatusRow("Method", transport.method.label)
                            StatusRow("State", transport.state.label)

                            if transport.method == .tcp {
                                StatusRow("Host", transport.host)
                                StatusRow("Port", "\(transport.port)")
                                StatusRow("Uptime", transport.connectionUptimeString)
                                StatusRow("Last Receive", transport.lastReceiveString)
                                StatusRow("Silent For", transport.silenceDurationString)
                            } else {
                                Text("Tip: T1 diagnostics are most useful in Wi-Fi (TCP) mode.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // =====================================================
                    // Live Traffic
                    // =====================================================
                    if transport.method == .tcp {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Live Traffic")
                                    .font(.headline)

                                StatusRow("Bytes/sec", transport.bytesPerSecondString)
                                StatusRow("Lines/sec", transport.linesPerSecondString)
                                StatusRow("Total Bytes", transport.totalBytesString)
                                StatusRow("Total Lines", "\(transport.totalLines)")
                            }
                        }
                    }

                    // =====================================================
                    // Stability Metrics
                    // =====================================================
                    if transport.method == .tcp {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Stability")
                                    .font(.headline)

                                StatusRow("Reconnects", "\(transport.reconnectCount)")
                                StatusRow("Watchdog Triggers", "\(transport.watchdogTriggerCount)")
                            }
                        }
                    }

                    // =====================================================
                    // Polling Controls (live adjustable)
                    // =====================================================
                    if transport.method == .tcp {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Polling Control")
                                    .font(.headline)

                                Toggle("Request Required (Poll)", isOn: $transport.requestModeEnabled)

                                Stepper(
                                    "Interval: \(transport.pollIntervalString)",
                                    value: $transport.pollIntervalSeconds,
                                    in: 0.05...10.0,
                                    step: 0.05
                                )
                                .font(.subheadline)

                                Picker("Request Format", selection: $transport.requestFormat) {
                                    Text("ASCII <C1>").tag(TCPTransport.RequestFormat.asciiAngleC1)
                                    Text("Binary 0xC1").tag(TCPTransport.RequestFormat.binaryC1)
                                    Text("ASCII <E21>").tag(TCPTransport.RequestFormat.asciiE21)
                                    Text("Custom ASCII").tag(TCPTransport.RequestFormat.customASCII)
                                }
                                .pickerStyle(.menu)

                                if transport.requestFormat == .customASCII {
                                    TextField("Custom Command", text: $transport.customASCIICommand)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                }

                                Picker("Line Ending", selection: $transport.pollLineEnding) {
                                    Text("None").tag(TCPTransport.LineEnding.none)
                                    Text("CR").tag(TCPTransport.LineEnding.cr)
                                    Text("LF").tag(TCPTransport.LineEnding.lf)
                                    Text("CRLF").tag(TCPTransport.LineEnding.crlf)
                                }
                                .pickerStyle(.segmented)

                                Divider().opacity(0.35)

                                Toggle("Keepalive Enabled", isOn: $transport.keepAliveEnabled)

                                Stepper(
                                    "Keepalive: \(Int(transport.keepAliveIntervalSeconds)) s",
                                    value: $transport.keepAliveIntervalSeconds,
                                    in: 1...30,
                                    step: 1
                                )
                                .font(.subheadline)

                                Divider().opacity(0.35)

                                Toggle("Burst Variants on Connect", isOn: $transport.burstBothPollVariantsOnConnect)

                                Stepper(
                                    "Burst Ticks: \(transport.burstTicksAfterConnect)",
                                    value: $transport.burstTicksAfterConnect,
                                    in: 0...30,
                                    step: 1
                                )
                                .font(.subheadline)
                            }
                        }
                    }

                    // =====================================================
                    // Manual Commands
                    // =====================================================
                    if transport.method == .tcp {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Manual Command")
                                    .font(.headline)

                                TextField("Enter ASCII command", text: $manualCommand)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)

                                HStack {
                                    Button("Send") {
                                        transport.sendManualASCII(manualCommand)
                                        manualCommand = ""
                                    }
                                    .buttonStyle(GlassButtonStyle())

                                    Button("Send 0xC1") {
                                        transport.sendBinaryC1()
                                    }
                                    .buttonStyle(GlassButtonStyle())

                                    Button("Probe") {
                                        transport.sendProbeSequence()
                                    }
                                    .buttonStyle(GlassButtonStyle())
                                }
                            }
                        }
                    }

                    // =====================================================
                    // Control Actions
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Actions")
                                .font(.headline)

                            HStack {
                                Button("Force Reconnect") {
                                    transport.forceReconnect()
                                }
                                .buttonStyle(GlassButtonStyle())

                                Button("Reset Metrics") {
                                    transport.resetDiagnostics()
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .navigationTitle("T1 Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper

private struct StatusRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
