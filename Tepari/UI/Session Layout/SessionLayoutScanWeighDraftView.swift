import SwiftUI

struct SessionLayoutScanWeighDraftView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var drafter: DrafterController

    @ObservedObject var vm: SessionViewModel

    @Binding var showWeighMode: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int
    let onGoToDraftTab: () -> Void

    private var recordsNewestFirst: [AnimalRecord] {
        Array(store.records(for: vm.activeSession.id).reversed())
    }

    private var leftSummary: SessionViewModel.DraftGateSummary {
        vm.draftLeftSummary
    }

    private var straightSummary: SessionViewModel.DraftGateSummary {
        vm.draftStraightSummary
    }

    private var rightSummary: SessionViewModel.DraftGateSummary {
        vm.draftRightSummary
    }

    private var farRightSummary: SessionViewModel.DraftGateSummary {
        vm.draftFarRightSummary
    }

    private var nextPositionPreview: DraftPosition {
        vm.nextDraftPosition
    }

    private var nextRuleDisplay: String {
        let t = (vm.nextDraftRuleName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Default" : t
    }

    private var weightSubtitle: String {
        vm.currentEID == "—" ? "Scan animal to weigh" : "Live weight for current animal"
    }

    private var draftSubtitle: String {
        drafter.isMoving ? "Drafting now" : "Next draft decision"
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            SessionTwoTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: 0,
                interTileSpacing: 14
            ) {
                weightPanel
            } bottomContent: {
                draftPanel
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutScanWeighDraftHeaderHUD(
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
        .fullScreenCover(isPresented: $showDetails) {
            NavigationStack {
                SessionLayoutScanWeighDraftFullRecordListView(
                    sessionName: vm.activeSession.name,
                    recordsNewestFirst: recordsNewestFirst
                )
                .navigationTitle("Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDetails = false }
                    }
                }
            }
        }
    }

    private var weightPanel: some View {
        SessionLayoutScanWeighDraftPanel(
            title: "Weight",
            systemImage: "scalemass.fill",
            subtitle: weightSubtitle
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SessionWeightBoard(
                    weight: vm.currentWeight,
                    locked: vm.isLocked,
                    stable: vm.isStable,
                    onWeighMode: { showWeighMode = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Text("Tally")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text("\(scannedCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showWeighMode = true
        }
    }

    private var draftPanel: some View {
        SessionLayoutScanWeighDraftPanel(
            title: "Draft",
            systemImage: "arrow.triangle.branch",
            subtitle: draftSubtitle
        ) {
            VStack(spacing: 8) {
                DraftArrowIndicator(
                    position: nextPositionPreview,
                    isMoving: drafter.isMoving,
                    maxArrowSize: isPhone ? 88 : 132
                )
                .frame(maxWidth: .infinity)

                Text(nextRuleDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 8) {
                    draftCountTile("Left", leftSummary, color: .blue)
                    draftCountTile("Straight", straightSummary, color: .green)
                    draftCountTile("Right", rightSummary, color: .purple)
                    draftCountTile("Far Right", farRightSummary, color: .orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onGoToDraftTab()
        }
    }

    private func draftCountTile(
        _ title: String,
        _ summary: SessionViewModel.DraftGateSummary,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(summary.count)")
                .font(.system(size: isPhone ? 18 : 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(summary.averageWeightKg.map { String(format: "%.1f kg", $0) } ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SessionLayoutScanWeighDraftPanel<Content: View>: View {
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
        }
    }
}

private struct SessionLayoutScanWeighDraftFullRecordListView: View {
    let sessionName: String
    let recordsNewestFirst: [AnimalRecord]

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()

            List {
                Section {
                    Text(sessionName)
                        .font(.headline)
                }

                Section("Scans (Most recent first)") {
                    if recordsNewestFirst.isEmpty {
                        Text("No animals recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recordsNewestFirst.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(r.eidRaw)
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                HStack(spacing: 10) {
                                    if r.lockedWeight > 0 {
                                        Text(String(format: "%.1f kg", r.lockedWeight))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let pos = r.draftResult {
                                        Text(positionLabel(pos))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func positionLabel(_ p: DraftPosition) -> String {
        switch p {
        case .left: return "Left"
        case .straight: return "Straight"
        case .right: return "Right"
        case .farRight: return "Far Right"
        }
    }
}

private struct SessionLayoutScanWeighDraftHeaderHUD: View {
    let eid: String
    let sessionName: String
    let scannedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            SessionLayoutScanWeighDraftGlassChip {
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

            SessionLayoutScanWeighDraftGlassChip {
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

            SessionLayoutScanWeighDraftGlassChip {
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

private struct SessionLayoutScanWeighDraftGlassChip<Content: View>: View {
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
