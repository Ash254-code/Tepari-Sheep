import SwiftUI
import Foundation

/// Fleece Weigh layout:
/// - Stick reader scans EID (your transport/vm is already doing this)
/// - Fleece goes on scales
/// - When stable, operator taps CAPTURE to save fleece weight for the current EID
///
/// ✅ This view does NOT assume *how* you persist fleece weight (field name, record model, etc).
/// Instead it takes `onCaptureFleeceWeight` so you can wire it to whatever store API you decide.
struct SessionLayoutFleeceWeighView: View {

    @EnvironmentObject private var store: LocalDataStore
    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>

    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void

    /// ✅ Wire this in SessionView:
    /// onCaptureFleeceWeight: { eid, kg in store.setFleeceWeight(sessionID: vm.activeSession.id, eidRaw: eid, kg: kg) }
    let onCaptureFleeceWeight: (_ eidRaw: String, _ fleeceKg: Double) -> Void

    /// Optional: allow opening Treatments from iPhone bottom bar if you want.
    let onOpenTreatments: (() -> Void)?

    // ---------------------------------------------------------
    // MARK: - Derived state
    // ---------------------------------------------------------

    private var canScan: Bool { activeTypes.contains(.scan) || activeTypes.contains(.fleeceWeigh) }
    private var canTreat: Bool { activeTypes.contains(.treatment) }
    private var canTraits: Bool { activeTypes.contains(.traitInput) }

    private var hasEID: Bool {
        !vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fleeceKg: Double { vm.currentWeight }

    private var canCapture: Bool {
        hasEID && vm.isStable
    }

    // Show last few session records as “previous” context (we don’t assume fleece field exists yet)
    private var recordsNewestFirst: [AnimalRecord] {
        store.records(for: vm.activeSession.id)
    }

    private var previousRows: [AnimalRecord] {
        Array(recordsNewestFirst.prefix(5))
    }

    // ---------------------------------------------------------
    // MARK: - Body
    // ---------------------------------------------------------

    var body: some View {
        VStack(spacing: 0) {

            headerBar

            Divider().opacity(0.25)
                .padding(.top, 8)

            VStack(spacing: 12) {

                topRow

                captureCard

                if canTraits {
                    traitsHintCard
                }

                if canTreat {
                    treatmentsHintCard
                }

                previousCard

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isPhone {
                phoneBottomActions
            }
        }
        .safeAreaPadding(.bottom, 0)

        // “Display” = full list (reuse your existing full list view if you have one;
        // here we just show a compact list so this file compiles standalone).
        .fullScreenCover(isPresented: $showDetails) {
            NavigationStack {
                ZStack {
                    GlassBackground().ignoresSafeArea()
                    List {
                        Section {
                            Text(vm.activeSession.name)
                                .font(.headline)
                        }
                        Section("Scans (Most recent first)") {
                            ForEach(Array(recordsNewestFirst.enumerated()), id: \.offset) { _, r in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(r.eidRaw)
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text("Fleece weight capture is wired via onCaptureFleeceWeight (no field assumed here).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Fleece Weigh")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDetails = false }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------
    // MARK: - Header / Top
    // ---------------------------------------------------------

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(vm.isStable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(vm.activeSession.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Fleece Weigh")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 12) {

            if canScan {
                EIDDisplayView(
                    eid: "—",
                    farmID: nil
                )
            } else {
                GlassCard {
                    HStack(spacing: 10) {
                        Image(systemName: "tshirt")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("No scanning in this session")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Tally")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(scannedCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
        }
    }

    // ---------------------------------------------------------
    // MARK: - Capture
    // ---------------------------------------------------------

    private var captureCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Label("Capture fleece weight", systemImage: "scalemass")
                        .font(.headline)
                    Spacer()
                    Text(vm.isStable ? "Stable" : "Unstable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vm.isStable ? .green : .secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(fleeceKgText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("kg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Button {
                    guard canCapture else { return }
                    onCaptureFleeceWeight(vm.currentEID, fleeceKg)
                    onSyncCoordinator()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(canCapture ? "CAPTURE" : (hasEID ? "WAIT FOR STABLE" : "SCAN EID"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canCapture ? Color.blue.opacity(0.95) : Color.gray.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Tip: Scan with stick reader, place fleece on scales, wait for Stable, then hit CAPTURE.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fleeceKgText: String {
        // keep simple formatting (you can refine once you confirm scale protocol precision)
        if abs(fleeceKg.rounded() - fleeceKg) < 0.0001 {
            return String(Int(fleeceKg.rounded()))
        }
        return String(format: "%.2f", fleeceKg)
    }

    // ---------------------------------------------------------
    // MARK: - Optional hint cards
    // ---------------------------------------------------------

    private var traitsHintCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Traits (optional)")
                    .font(.headline)
                Text("If Trait Input is enabled for this fleece session, we can add a compact traits panel here (micron/staple/custom).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var treatmentsHintCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Treatments (optional)")
                    .font(.headline)
                Text("Treatments can be available via the dock (iPad) or a button below (iPhone).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ---------------------------------------------------------
    // MARK: - Previous
    // ---------------------------------------------------------

    private var previousCard: some View {
        Button {
            showDetails = true
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Previous", systemImage: "clock")
                            .font(.headline)
                        Spacer()
                        Text("Tap to view all")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let r = previousRows.first {
                        HStack(spacing: 10) {
                            Image(systemName: "tag")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text(r.eidRaw)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ---------------------------------------------------------
    // MARK: - iPhone bottom actions
    // ---------------------------------------------------------

    private var phoneBottomActions: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.25)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SessionWideTile(
                        title: "New Session",
                        systemImage: "plus.circle",
                        dotColor: nil,
                        height: 54,
                        enabled: true,
                        action: onStartNewSession
                    )

                    SessionWideTile(
                        title: "Display",
                        systemImage: "chevron.up",
                        dotColor: nil,
                        height: 54,
                        enabled: true
                    ) {
                        showDetails = true
                    }
                }

                HStack(spacing: 10) {
                    SessionWideTile(
                        title: "Treatments",
                        systemImage: "cross.case.fill",
                        dotColor: nil,
                        height: 54,
                        enabled: canTreat && onOpenTreatments != nil
                    ) {
                        onOpenTreatments?()
                    }

                    SessionWideTile(
                        title: "Undo",
                        systemImage: "arrow.uturn.backward",
                        dotColor: nil,
                        height: 54,
                        enabled: false,
                        action: { }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}
