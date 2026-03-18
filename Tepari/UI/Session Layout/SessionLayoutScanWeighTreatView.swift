import SwiftUI

struct SessionLayoutScanWeighTreatView: View {

    @EnvironmentObject private var tepariGun: TepariGunManager

    @ObservedObject var vm: SessionViewModel

    @Binding var showWeighMode: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onOpenTreatments: () -> Void

    @State private var lastAutoSentSignature: String? = nil

    private var selectedTreatmentName: String {
        vm.selectedSessionTreatment?.product ?? "—"
    }

    private var doseText: String {
        vm.calculatedDoseText ?? "—"
    }

    private var treatmentStatusText: String {
        if vm.sessionTreatments.isEmpty {
            return "No treatments configured for this session."
        }
        if vm.currentEID == "—" {
            return "Scan an animal to prepare treatment dose."
        }
        if vm.hasDoseReadyWeight || vm.isLocked {
            return vm.calculatedDoseText != nil
                ? "Calculated from locked weight."
                : "Dose unavailable for selected treatment."
        }
        return "Dose appears once weight locks."
    }

    private var currentDoseReadyWeight: Double? {
        guard vm.isLocked || vm.hasDoseReadyWeight else { return nil }
        return vm.currentWeight
    }

    private var currentAutoSendSignature: String? {
        guard tepariGun.isEnabled else { return nil }

        let eid = vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eid.isEmpty, eid != "—" else { return nil }

        guard let treatment = vm.selectedSessionTreatment else { return nil }
        guard let doseText = vm.calculatedDoseText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseText.isEmpty,
              doseText != "—" else { return nil }
        guard let weight = currentDoseReadyWeight else { return nil }

        let weightText = String(format: "%.2f", weight)
        return "\(eid)|\(treatment.id.uuidString)|\(doseText)|\(weightText)"
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            SessionTwoTileTemplateView(
                horizontalPadding: 16,
                topPadding: 12,
                bottomPadding: 8,
                reservedBottomHeight: 0,
                interTileSpacing: 14
            ) {
                weightPanel
            } bottomContent: {
                treatmentPanel
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutScanWeighTreatHeaderHUD(
                eid: vm.currentEID,
                farmID: vm.activeSession.farmID,
                sessionName: vm.activeSession.name,
                scannedCount: scannedCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.thinMaterial)
            .overlay(Divider().opacity(0.20), alignment: .bottom)
        }
        .onAppear {
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.currentEID) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.selectedSessionTreatmentID) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.calculatedDoseText) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.currentWeight) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.isLocked) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.hasDoseReadyWeight) { _, _ in
            autoSendDoseIfNeeded()
        }
    }

    private var weightPanel: some View {
        SessionLayoutScanWeighTreatPanel(
            title: "Weight",
            systemImage: "scalemass.fill",
            subtitle: "Live scale"
        ) {
            SessionWeightBoard(
                weight: vm.currentWeight,
                locked: vm.isLocked,
                stable: vm.isStable,
                onWeighMode: { showWeighMode = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showWeighMode = true
        }
    }

    private var treatmentPanel: some View {
        SessionLayoutScanWeighTreatPanel(
            title: "Treatment",
            systemImage: "cross.case.fill",
            subtitle: "Current dose"
        ) {
            VStack(alignment: .leading, spacing: 10) {

                HStack(spacing: 8) {
                    Text(selectedTreatmentName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)

                    Button("Open") {
                        onOpenTreatments()
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("Dose")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(doseText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                HStack {
                    Text("Tally")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text("\(scannedCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                Text(treatmentStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if vm.sessionTreatments.isEmpty {
                onOpenTreatments()
            }
        }
    }

    private func autoSendDoseIfNeeded() {
        guard let signature = currentAutoSendSignature else {
            if vm.currentEID == "—" || vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastAutoSentSignature = nil
            }
            return
        }

        guard signature != lastAutoSentSignature else { return }
        guard !tepariGun.isSending else { return }
        guard let treatment = vm.selectedSessionTreatment,
              let weight = currentDoseReadyWeight else { return }

        lastAutoSentSignature = signature
        tepariGun.sendSelectedTreatment(treatment, weightKg: weight)
    }
}

private struct SessionLayoutScanWeighTreatPanel<Content: View>: View {
    let title: String
    let systemImage: String?
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)

                        if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Spacer(minLength: 8)
                }

                Divider().opacity(0.18)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }
}

private struct SessionLayoutScanWeighTreatHeaderHUD: View {
    @EnvironmentObject private var store: LocalDataStore

    let eid: String
    let farmID: UUID?
    let sessionName: String
    let scannedCount: Int

    private var hasEID: Bool {
        eid != "—" && !eid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mobTintColor: Color? {
        guard hasEID,
              let hex = store.mobColorHexForEID(eid, farmID: farmID) else { return nil }
        return Color(hex: hex)
    }

    private var mobTintOpacity: Double {
        0.26
    }

    var body: some View {
        HStack(spacing: 12) {
            SessionLayoutScanWeighTreatGlassChip(tintColor: mobTintColor?.opacity(mobTintOpacity)) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(eid == "—" ? "Scan EID" : eid)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }

            Spacer()

            SessionLayoutScanWeighTreatGlassChip {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text(sessionName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            SessionLayoutScanWeighTreatGlassChip {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tally")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("\(scannedCount)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

private struct SessionLayoutScanWeighTreatGlassChip<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    let tintColor: Color?
    let content: Content

    private let chipHeight: CGFloat = 56

    init(
        tintColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tintColor = tintColor
        self.content = content()
    }

    var body: some View {
        content
            .frame(height: chipHeight)
            .padding(.horizontal, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        scheme == .dark
                        ? AnyShapeStyle(.thinMaterial)
                        : AnyShapeStyle(Color(.systemBackground))
                    )
                    .overlay {
                        if let tintColor {
                            Capsule(style: .continuous)
                                .fill(tintColor)
                        }
                    }
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        scheme == .dark
                        ? Color.white.opacity(0.18)
                        : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.22 : 0.10),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}
private extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: "#", with: "")

        guard raw.count == 6 || raw.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value) else { return nil }

        let r, g, b, a: Double

        if raw.count == 8 {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
            a = Double(value & 0x000000FF) / 255.0
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
            a = 1.0
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
