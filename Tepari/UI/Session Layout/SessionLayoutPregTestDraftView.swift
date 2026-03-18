import SwiftUI
import Foundation

struct SessionLayoutPregTestDraftView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var drafter: DrafterController
    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void
    let onOpenTreatments: () -> Void

    private var canTreat: Bool { activeTypes.contains(.treatment) }
    private let pregFetusKey = "pregFetusCount"

    private var reservedBottomHeight: CGFloat {
        isPhone ? 96 : 0
    }

    // MARK: Records

    private var sessionRecords: [AnimalRecord] {
        store.records(for: vm.activeSession.id)
    }

    private var recordsNewestFirst: [AnimalRecord] {
        Array(sessionRecords.reversed())
    }

    private var previousRows: [AnimalRecord] {
        Array(recordsNewestFirst.prefix(3))
    }

    // MARK: Draft counts

    private func count(for pos: DraftPosition) -> Int {
        sessionRecords.filter { $0.draftResult == pos }.count
    }

    private var leftCount: Int { count(for: .left) }
    private var straightCount: Int { count(for: .straight) }
    private var rightCount: Int { count(for: .right) }
    private var farRightCount: Int { count(for: .farRight) }

    // MARK: Next

    private var nextPositionPreview: DraftPosition {
        vm.nextDraftPosition
    }

    private var nextRuleDisplay: String {
        let t = (vm.nextDraftRuleName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Default" : t
    }

    // MARK: Preg selection

    private var selectedFetusCount: Int? {
        guard let raw = vm.draftCustomTraits[pregFetusKey],
              let n = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return n
    }

    private var selectedLabel: String {
        guard let n = selectedFetusCount else { return "Selected: —" }
        return "Selected: \(n)"
    }

    // MARK: Body

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            mainBody
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutPregTestDraftHeaderHUD(
                eid: vm.currentEID,
                sessionName: vm.activeSession.name,
                scannedCount: scannedCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.thinMaterial)
            .overlay(Divider().opacity(0.20), alignment: .bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPhone {
                phoneBottomActions
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(.thinMaterial)
                    .overlay(Divider().opacity(0.25), alignment: .top)
            }
        }
        .onAppear {
            vm.drafterController = drafter
            onSyncCoordinator()
        }
        .onChange(of: vm.currentEID) { _, _ in
            vm.setDraftCustomTrait(id: pregFetusKey, value: "")
        }
        .onChange(of: drafter.isMoving) { _, moving in
            if moving == false {
                vm.setDraftCustomTrait(id: pregFetusKey, value: "")
            }
        }
        .fullScreenCover(isPresented: $showDetails) {
            NavigationStack {
                SessionLayoutPregTestDraftFullRecordListView(
                    sessionName: vm.activeSession.name,
                    recordsNewestFirst: recordsNewestFirst,
                    pregFetusKey: pregFetusKey
                )
                .navigationTitle("All Animals")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDetails = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mainBody: some View {
        if canTreat {
            SessionThreeTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight,
                verticalSpacing: 12,
                horizontalSpacing: 12,
                topTileHeightRatio: isPhone ? 0.44 : 0.46
            ) {
                draftPanel
            } bottomLeadingContent: {
                pregPanel
            } bottomTrailingContent: {
                treatmentsInfoCard
            }
        } else {
            SessionTwoTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight,
                interTileSpacing: 12
            ) {
                draftPanel
            } bottomContent: {
                pregPanel
            }
        }
    }

    // MARK: Draft

    private var draftPanel: some View {
        SessionLayoutPregTestDraftPanel(
            title: "Draft",
            systemImage: "arrow.triangle.branch",
            trailingText: nextRuleDisplay
        ) {
            Group {
                if isPhone {
                    VStack(spacing: 10) {
                        DraftArrowIndicator(
                            position: nextPositionPreview,
                            isMoving: drafter.isMoving,
                            maxArrowSize: 126
                        )
                        .frame(maxWidth: .infinity)

                        GateTotalsStrip(
                            left: leftCount,
                            straight: straightCount,
                            right: rightCount,
                            farRight: farRightCount,
                            layout: .singleRow
                        )
                    }
                } else {
                    GeometryReader { inner in
                        let w = inner.size.width
                        let totalsMax: CGFloat = 560
                        let gap: CGFloat = 14
                        let compactTotals = w < 980

                        let totalsW = min(totalsMax, max(320, w * (compactTotals ? 0.50 : 0.46)))
                        let arrowW = max(0, w - totalsW - gap)

                        HStack(spacing: gap) {
                            VStack {
                                Spacer(minLength: 0)

                                let maxSquare = min(arrowW, inner.size.height - 28)

                                SoftPulse(isActive: drafter.isMoving, amount: 0.008, duration: 1.6) {
                                    DraftArrowIndicator(
                                        position: nextPositionPreview,
                                        isMoving: false,
                                        maxArrowSize: max(140, maxSquare)
                                    )
                                    .frame(width: maxSquare, height: maxSquare)
                                }

                                Spacer(minLength: 0)
                            }
                            .frame(width: arrowW)

                            GateTotalsStrip(
                                left: leftCount,
                                straight: straightCount,
                                right: rightCount,
                                farRight: farRightCount,
                                layout: compactTotals ? .grid2x2 : .singleRow
                            )
                            .frame(width: totalsW)
                        }
                        .frame(width: w, height: inner.size.height, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Preg

    private var pregPanel: some View {
        SessionLayoutPregTestDraftPanel(
            title: "Preg Testing",
            systemImage: "waveform.path.ecg",
            trailingText: selectedLabel
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Press 0 / 1 / 2 to record fetus count and draft immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    fetusButton(0, "Dry")
                    fetusButton(1, "Single")
                    fetusButton(2, "Twins")
                }

                Divider().opacity(0.18)

                Button {
                    showDetails = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Animals")
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            Text("Tap to view all")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if previousRows.isEmpty {
                            Text("—")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(previousRows, id: \.id) { r in
                                HStack(spacing: 8) {
                                    Text(r.eidRaw)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer(minLength: 6)

                                    Text(pregLine(r))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func fetusButton(_ n: Int, _ subtitle: String) -> some View {
        let selected = selectedFetusCount == n

        return Button {
            vm.setDraftCustomTrait(id: pregFetusKey, value: "\(n)")
            vm.manualPregDraft(fetusCount: n)
            onSyncCoordinator()
        } label: {
            VStack(spacing: 6) {
                Text("\(n)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? .white.opacity(0.9) : .secondary.opacity(0.9))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Color.blue.opacity(0.95) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(selected ? 0.14 : 0.10), lineWidth: 1)
        )
    }

    // MARK: Treatments

    private var treatmentsInfoCard: some View {
        SessionLayoutPregTestDraftPanel(
            title: "Treatment",
            systemImage: "cross.case.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Treatments apply automatically when the animal is recorded, if configured in the session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                Spacer(minLength: 0)

                Button {
                    onOpenTreatments()
                } label: {
                    Text("Open Treatments")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Bottom actions

    private var phoneBottomActions: some View {
        HStack(spacing: 10) {
            SessionWideTile(
                title: "New Session",
                systemImage: "plus.circle",
                height: 54,
                enabled: true,
                action: onStartNewSession
            )

            SessionWideTile(
                title: "Display",
                systemImage: "chevron.up",
                height: 54,
                enabled: true
            ) {
                showDetails = true
            }

            SessionWideTile(
                title: "Treatments",
                systemImage: "cross.case.fill",
                height: 54,
                enabled: canTreat,
                action: onOpenTreatments
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: Helpers

    private func pregLine(_ r: AnimalRecord) -> String {
        guard let raw = r.customTraits?[pregFetusKey],
              let n = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "Preg: —" }
        switch n {
        case 0: return "Preg: 0"
        case 1: return "Preg: 1"
        case 2: return "Preg: 2"
        default: return "Preg: \(n)"
        }
    }
}

// MARK: - Shared panel

private struct SessionLayoutPregTestDraftPanel<Content: View>: View {
    let title: String
    let systemImage: String?
    let trailingText: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        trailingText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingText = trailingText
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.headline)

                    Spacer(minLength: 8)

                    if let trailingText, !trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(trailingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Divider().opacity(0.18)

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }
}

// MARK: - Full list

private struct SessionLayoutPregTestDraftFullRecordListView: View {
    let sessionName: String
    let recordsNewestFirst: [AnimalRecord]
    let pregFetusKey: String

    var body: some View {
        List(recordsNewestFirst, id: \.id) { r in
            VStack(alignment: .leading, spacing: 6) {
                Text(r.eidRaw)
                    .font(.system(.body, design: .monospaced).weight(.semibold))

                Text(pregLine(r))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(GlassBackground().ignoresSafeArea())
    }

    private func pregLine(_ r: AnimalRecord) -> String {
        guard let raw = r.customTraits?[pregFetusKey],
              let n = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "Preg: —" }
        switch n {
        case 0: return "Preg: 0"
        case 1: return "Preg: 1"
        case 2: return "Preg: 2"
        default: return "Preg: \(n)"
        }
    }
}

// MARK: - Header HUD

private struct SessionLayoutPregTestDraftHeaderHUD: View {
    let eid: String
    let sessionName: String
    let scannedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            SessionLayoutPregTestDraftGlassChip {
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

            SessionLayoutPregTestDraftGlassChip {
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

            SessionLayoutPregTestDraftGlassChip {
                HStack(spacing: 12) {
                    Text("Tally")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("\(scannedCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct SessionLayoutPregTestDraftGlassChip<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    private let chipHeight: CGFloat = 56

    var body: some View {
        content
            .frame(height: chipHeight)
            .padding(.horizontal, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.14), lineWidth: 1)
            )
    }
}

// MARK: - Gate totals

private enum GateTotalsLayout {
    case singleRow
    case grid2x2
}

private struct GateTotalsStrip: View {
    let left: Int
    let straight: Int
    let right: Int
    let farRight: Int
    let layout: GateTotalsLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Draft Totals")
                .font(.headline)

            switch layout {
            case .singleRow:
                HStack(spacing: 10) {
                    GateMiniTile(title: "Left", dot: .blue, value: left)
                    GateMiniTile(title: "Straight", dot: .green, value: straight)
                    GateMiniTile(title: "Right", dot: .purple, value: right)
                    GateMiniTile(title: "Far Right", dot: .orange, value: farRight)
                }

            case .grid2x2:
                let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    GateMiniTile(title: "Left", dot: .blue, value: left)
                    GateMiniTile(title: "Straight", dot: .green, value: straight)
                    GateMiniTile(title: "Right", dot: .purple, value: right)
                    GateMiniTile(title: "Far Right", dot: .orange, value: farRight)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct GateMiniTile: View {
    let title: String
    let dot: Color
    let value: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(dot.opacity(scheme == .dark ? 0.28 : 0.22), lineWidth: 1)
        )
    }
}

// MARK: - Pulse wrapper

private struct SoftPulse<Content: View>: View {
    let isActive: Bool
    let amount: CGFloat
    let duration: Double
    @ViewBuilder var content: () -> Content

    @State private var pulseOn: Bool = false

    var body: some View {
        content()
            .scaleEffect(isActive ? (pulseOn ? (1.0 + amount) : 1.0) : 1.0)
            .onAppear { pulseOn = false }
            .onChange(of: isActive) { _, active in
                pulseOn = active
            }
            .animation(
                isActive
                ? .easeInOut(duration: duration).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
                value: pulseOn
            )
    }
}
