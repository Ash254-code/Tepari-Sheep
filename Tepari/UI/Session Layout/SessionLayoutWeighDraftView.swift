import SwiftUI

struct SessionLayoutWeighDraftView: View {

    @EnvironmentObject private var drafter: DrafterController

    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>

    @Binding var showWeighMode: Bool
    @Binding var showZeroConfirmation: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let isTCPConnected: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void
    let onGoToDraftTab: () -> Void

    private var reservedBottomHeight: CGFloat {
        isPhone ? 96 : 0
    }

    private var showWeigh: Bool {
        activeTypes.contains(.weigh) || activeTypes.contains(.fleeceWeigh)
    }

    private var showDraft: Bool {
        activeTypes.contains(.draft)
    }

    private var isScanDraftOnly: Bool {
        showDraft && !showWeigh
    }

    private var nextPositionPreview: DraftPosition {
        vm.nextDraftPosition
    }

    private var nextRuleDisplay: String {
        let t = (vm.nextDraftRuleName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Default" : t
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

    private func openDetails() {
        showDetails = true
    }

    private func goToDraftTab() {
        guard showDraft else { return }
        onGoToDraftTab()
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            mainBody
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionHeaderHUD(
                eid: vm.currentEID,
                sessionName: vm.activeSession.name,
                scannedCount: scannedCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.thinMaterial)
            .overlay(Divider().opacity(0.20), alignment: .bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPhone {
                bottomActions
                    .padding(.bottom, 12)
                    .background(.thinMaterial)
                    .overlay(Divider().opacity(0.25), alignment: .top)
            }
        }
        .onAppear {
            onSyncCoordinator()
        }
        .fullScreenCover(isPresented: $showDetails) {
            RecentAnimalsFullScreenView(
                sessionName: vm.activeSession.name,
                records: []
            )
        }
    }

    @ViewBuilder
    private var mainBody: some View {
        if showWeigh && showDraft {
            SessionTwoTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight,
                interTileSpacing: 12
            ) {
                draftPanel
            } bottomContent: {
                weightPanel
            }
        } else if showWeigh {
            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                weightPanel
            }
        } else if isScanDraftOnly {
            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                draftPanel
            }
        } else {
            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                scanStatusCard
            }
        }
    }

    private var draftPanel: some View {
        SessionLayoutWeighDraftPanel(
            title: "Draft",
            systemImage: "arrow.triangle.branch",
            subtitle: nextRuleDisplay
        ) {
            VStack(spacing: 10) {
                DraftArrowIndicator(
                    position: nextPositionPreview,
                    isMoving: drafter.isMoving,
                    maxArrowSize: isPhone ? 126 : 180
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GateTotalsStrip(
                    left: leftSummary,
                    straight: straightSummary,
                    right: rightSummary,
                    farRight: farRightSummary,
                    layout: isPhone ? .singleRow : .grid2x2
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            goToDraftTab()
        }
    }

    private var weightPanel: some View {
        SessionLayoutWeighDraftPanel(
            title: "Weight",
            systemImage: "scalemass.fill",
            subtitle: "Live scale"
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
            if showWeigh {
                showWeighMode = true
            } else {
                openDetails()
            }
        }
    }

    private var scanStatusCard: some View {
        SessionLayoutWeighDraftPanel(
            title: "Scan Session",
            systemImage: "qrcode.viewfinder",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(vm.currentEID == "—" ? "Scan an EID to begin." : "Scanned: \(vm.currentEID)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bottomActions: some View {
        Group {
            if isPhone {
                VStack(spacing: 10) {
                    if showWeigh {
                        SessionActionsPhoneGrid(
                            isTCPConnected: isTCPConnected,
                            isLocked: vm.isLocked,
                            showDetails: showDetails,
                            onReweigh: { vm.reweigh() },
                            onZero: {
                                guard isTCPConnected && !vm.isLocked else { return }
                                vm.zeroNow()
                                withAnimation { showZeroConfirmation = true }
                            },
                            onNewSession: onStartNewSession,
                            onToggleDetails: {
                                openDetails()
                            }
                        )
                        .padding(.horizontal, 16)
                    } else {
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
                                openDetails()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
            } else {
                EmptyView()
            }
        }
    }
}

private struct SessionLayoutWeighDraftPanel<Content: View>: View {
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

private struct RecentAnimalsFullScreenView: View {
    @Environment(\.dismiss) private var dismiss

    let sessionName: String
    let records: [AnimalRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if records.isEmpty {
                        Text("No animals recorded yet.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    } else {
                        RecentScansListView(records: records.prefix(200))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .background(GlassBackground().ignoresSafeArea())
            .navigationTitle(sessionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SessionHeaderHUD: View {
    let eid: String
    let sessionName: String
    let scannedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            GlassChip {
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

            GlassChip {
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

            GlassChip {
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

private enum GateTotalsLayout {
    case singleRow
    case grid2x2
}

private struct GateTotalsStrip: View {
    let left: SessionViewModel.DraftGateSummary
    let straight: SessionViewModel.DraftGateSummary
    let right: SessionViewModel.DraftGateSummary
    let farRight: SessionViewModel.DraftGateSummary
    let layout: GateTotalsLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Draft Totals")
                .font(.headline)

            switch layout {
            case .singleRow:
                HStack(spacing: 10) {
                    GateMiniTile(title: "Left", dot: .blue, summary: left)
                    GateMiniTile(title: "Straight", dot: .green, summary: straight)
                    GateMiniTile(title: "Right", dot: .purple, summary: right)
                    GateMiniTile(title: "Far Right", dot: .orange, summary: farRight)
                }

            case .grid2x2:
                let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    GateMiniTile(title: "Left", dot: .blue, summary: left)
                    GateMiniTile(title: "Straight", dot: .green, summary: straight)
                    GateMiniTile(title: "Right", dot: .purple, summary: right)
                    GateMiniTile(title: "Far Right", dot: .orange, summary: farRight)
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
    let summary: SessionViewModel.DraftGateSummary

    @Environment(\.colorScheme) private var scheme

    private var avgText: String {
        guard let avg = summary.averageWeightKg else { return "—" }
        return String(format: "%.1f", avg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dot)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text("\(summary.count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text("Avg")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(avgText == "—" ? "—" : "\(avgText) kg")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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

private struct GlassChip<Content: View>: View {
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
