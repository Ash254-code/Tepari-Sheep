import SwiftUI

struct DraftingHomeView: View {

    var body: some View {
        NavigationStack {
            List {

                Section("Drafting") {
                    NavigationLink {
                        DraftDashboardView()
                    } label: {
                        DraftingRow(
                            icon: "arrow.triangle.branch",
                            title: "Live Controls",
                            subtitle: "Gate mapping, manual routing and drafter status"
                        )
                    }

                    NavigationLink {
                        DraftRuleSetsView()
                    } label: {
                        DraftingRow(
                            icon: "list.bullet.rectangle",
                            title: "Rule Sets",
                            subtitle: "Create and edit drafting rules"
                        )
                    }

                    NavigationLink {
                        DrafterHardwareView()
                    } label: {
                        DraftingRow(
                            icon: "switch.2",
                            title: "Hardware",
                            subtitle: "Configure drafter connection and test outputs"
                        )
                    }
                }

                Section("Bench Test – WiFi Relay") {
                    relayTestButton(gate: 1)
                    relayTestButton(gate: 2)
                    relayTestButton(gate: 3)
                    relayTestButton(gate: 4)

                    Button {
                        DraftWifiController.holdGate(5)
                    } label: {
                        DraftingRow(
                            icon: "lock.fill",
                            title: "Catch",
                            subtitle: "Turn catch relay on"
                        )
                    }

                    Button {
                        DraftWifiController.releaseGate(5)
                    } label: {
                        DraftingRow(
                            icon: "lock.open.fill",
                            title: "Release",
                            subtitle: "Turn catch relay off"
                        )
                    }
                }
            }
            .navigationTitle("Drafting")
            .onAppear {
                DraftWifiController.startDiscovery()
            }
        }
    }

    @ViewBuilder
    private func relayTestButton(gate: Int) -> some View {
        Button {
            DraftWifiController.fireGate(gate)
        } label: {
            DraftingRow(
                icon: "wifi",
                title: "Fire Gate \(gate)",
                subtitle: "Select gate \(gate) via ESP32"
            )
        }
    }
}

// =====================================================
// MARK: - Row UI
// =====================================================

private struct DraftingRow: View {

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// =====================================================
// MARK: - Rule Sets Placeholder
// =====================================================

private struct DraftRuleSetsView: View {
    var body: some View {
        ContentUnavailableView(
            "Rule Sets",
            systemImage: "list.bullet.rectangle",
            description: Text("Create and edit drafting rules here.")
        )
        .navigationTitle("Rule Sets")
    }
}

// =====================================================
// MARK: - Hardware
// =====================================================

private struct DrafterHardwareView: View {

    @AppStorage("drafter_base_url") private var drafterBaseURL: String = ""

    @State private var isConnected: Bool = false
    @State private var statusRefreshTask: Task<Void, Never>? = nil

    var body: some View {
        Form {
            Section("Drafter Status") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(isConnected ? "Connected" : "Not Connected")
                        .font(.headline)
                }

                if !drafterBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(drafterBaseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Refresh Status") {
                    refreshStatus()
                }
                .buttonStyle(.bordered)
            }

            Section("WiFi Drafter") {
                TextField("Base URL (auto-discovered)", text: $drafterBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button("Test Gate 1") {
                    DraftWifiController.fireGate(1)
                }
                .buttonStyle(.borderedProminent)

                Button("Test Gate 2") {
                    DraftWifiController.fireGate(2)
                }
                .buttonStyle(.bordered)

                Button("Test Gate 3") {
                    DraftWifiController.fireGate(3)
                }
                .buttonStyle(.bordered)

                Button("Test Gate 4") {
                    DraftWifiController.fireGate(4)
                }
                .buttonStyle(.bordered)
            }

            Section("Catch Control") {
                Button("Catch") {
                    DraftWifiController.holdGate(5)
                }
                .buttonStyle(.borderedProminent)

                Button("Release") {
                    DraftWifiController.releaseGate(5)
                }
                .buttonStyle(.bordered)

                Button("All Off") {
                    DraftWifiController.releaseAllGates()
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Hardware")
        .onAppear {
            DraftWifiController.startDiscovery()
            refreshStatus()
            startPolling()
        }
        .onDisappear {
            statusRefreshTask?.cancel()
            statusRefreshTask = nil
        }
    }

    private func refreshStatus() {
        DraftWifiController.startDiscovery()

        let trimmed = drafterBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        isConnected = !trimmed.isEmpty
    }

    private func startPolling() {
        statusRefreshTask?.cancel()

        statusRefreshTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    refreshStatus()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
