import SwiftUI

struct SessionSummaryView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator

    private var sessionID: UUID? { coordinator.activeSessionID }

    private var records: [AnimalRecord] {
        guard let id = sessionID else { return [] }
        return store.records(for: id)
    }

    // MARK: - Stats

    private var totalCount: Int { records.count }

    private var weights: [Double] {
        records.map(\.lockedWeight).filter { $0 > 0 }
    }

    private var avgWeight: Double? {
        guard !weights.isEmpty else { return nil }
        return weights.reduce(0, +) / Double(weights.count)
    }

    private var minWeight: Double? { weights.min() }
    private var maxWeight: Double? { weights.max() }

    private var lastScanDate: Date? {
        records.map(\.recordedAt).max()
    }

    private var draftedRecords: [AnimalRecord] {
        records.filter { $0.draftResult != nil }
    }

    private var undraftedCount: Int {
        records.filter { $0.draftResult == nil }.count
    }

    // MARK: - Real gate summaries

    private struct GateSummary: Identifiable {
        let position: DraftPosition
        let count: Int
        let avgWeight: Double?
        let minWeight: Double?
        let maxWeight: Double?

        var id: Int { position.rawValue }

        var title: String {
            switch position {
            case .left: return "Left"
            case .straight: return "Straight"
            case .right: return "Right"
            case .farRight: return "Far Right"
            }
        }

        var color: Color {
            switch position {
            case .left: return .blue
            case .straight: return .green
            case .right: return .purple
            case .farRight: return .orange
            }
        }
    }

    private func gateSummary(for position: DraftPosition) -> GateSummary {
        let gateRecords = records.filter { $0.draftResult == position }
        let gateWeights = gateRecords.map(\.lockedWeight).filter { $0 > 0 }

        let avg: Double? = gateWeights.isEmpty ? nil : gateWeights.reduce(0, +) / Double(gateWeights.count)

        return GateSummary(
            position: position,
            count: gateRecords.count,
            avgWeight: avg,
            minWeight: gateWeights.min(),
            maxWeight: gateWeights.max()
        )
    }

    private var gateSummaries: [GateSummary] {
        [
            gateSummary(for: .left),
            gateSummary(for: .straight),
            gateSummary(for: .right),
            gateSummary(for: .farRight)
        ]
    }

    private var maxGateCount: Int {
        max(gateSummaries.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    headerCard

                    if sessionID == nil {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Active Session")
                                    .font(.headline)
                                Text("Go to the Session tab and start/select a session first.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if records.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Scans Yet")
                                    .font(.headline)
                                Text("Scan a few animals in the Session tab and summary will appear here.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        statsCard
                        gatesCard
                    }

                    Spacer(minLength: 10)
                }
                .padding()
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Session Summary")
                    .font(.title3.weight(.bold))

                if let id = sessionID {
                    Text("Active session: \(id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No active session selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Overview")
                    .font(.headline)

                Divider().opacity(0.35)

                statRow("Total scanned", "\(totalCount)")
                statRow("Drafted", "\(draftedRecords.count)")
                statRow("Not drafted", "\(undraftedCount)")
                statRow("Average weight", avgWeight.map { "\(fmt1($0)) kg" } ?? "—")

                statRow("Min / Max", {
                    if let mn = minWeight, let mx = maxWeight {
                        return "\(fmt1(mn)) / \(fmt1(mx)) kg"
                    }
                    return "—"
                }())

                statRow("Last scan", lastScanDate.map { fmtDateTime($0) } ?? "—")
            }
        }
    }

    private var gatesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Draft Gates")
                    .font(.headline)

                Text("These totals come from the actual recorded draft result for each animal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().opacity(0.35)

                ForEach(gateSummaries) { gate in
                    VStack(alignment: .leading, spacing: 8) {
                        barRow(
                            title: gate.title,
                            value: gate.count,
                            maxValue: maxGateCount,
                            color: gate.color
                        )

                        HStack(spacing: 14) {
                            compactStat("Avg", gate.avgWeight.map { "\(fmt1($0)) kg" } ?? "—")
                            compactStat("Min", gate.minWeight.map { "\(fmt1($0)) kg" } ?? "—")
                            compactStat("Max", gate.maxWeight.map { "\(fmt1($0)) kg" } ?? "—")
                        }
                        .padding(.leading, 2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - UI helpers

    private func barRow(title: String, value: Int, maxValue: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.system(size: 14))

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let frac = CGFloat(value) / CGFloat(max(maxValue, 1))
                let fillW = max(0, min(w * frac, w))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.10))

                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: fillW)
                }
            }
            .frame(height: 10)
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.system(size: 14))
    }

    private func compactStat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Formatting

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func fmtDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy  h:mm a"
        return f.string(from: d)
    }
}
