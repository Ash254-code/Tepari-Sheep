import SwiftUI

struct SessionLayoutScanDraftView: View {

    @EnvironmentObject private var drafter: DrafterController

    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void

    private var reservedBottomHeight: CGFloat {
        isPhone ? 96 : 0
    }

    // MARK: Real summaries (NO more recalculation)

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

    // MARK: Body

    var body: some View {

        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                draftTile
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutScanDraftHeaderHUD(
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
    }

    // MARK: Draft Tile

    private var draftTile: some View {

        GlassCard {

            VStack(spacing: 14) {

                HStack {
                    Label("Draft", systemImage: "arrow.triangle.branch")
                        .font(.headline)

                    Spacer()

                    Text(drafter.isMoving ? "Moving" : "Ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                DraftArrowIndicator(
                    position: nextPositionPreview,
                    isMoving: drafter.isMoving,
                    maxArrowSize: isPhone ? 120 : 180
                )
                .frame(maxWidth: .infinity)

                Text(nextRuleDisplay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                draftTotals

            }
            .padding(16)
        }
    }

    // MARK: Totals

    private var draftTotals: some View {

        HStack(spacing: 10) {

            draftCountTile("Left", leftSummary, color: .blue)
            draftCountTile("Straight", straightSummary, color: .green)
            draftCountTile("Right", rightSummary, color: .purple)
            draftCountTile("Far Right", farRightSummary, color: .orange)

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

            Text("\(summary.count)")
                .font(.system(size: isPhone ? 22 : 28, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(summary.averageWeightKg.map { String(format: "%.1f kg", $0) } ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.22))
        )
    }

    // MARK: Bottom actions

    private var bottomActions: some View {

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
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

//
// MARK: Header HUD
//

private struct SessionLayoutScanDraftHeaderHUD: View {

    let eid: String
    let sessionName: String
    let scannedCount: Int

    var body: some View {

        HStack(spacing: 12) {

            SessionLayoutScanDraftGlassChip {

                HStack(spacing: 12) {

                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(eid == "—" ? "Scan EID" : eid)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }

            Spacer()

            SessionLayoutScanDraftGlassChip {

                HStack(spacing: 10) {

                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text(sessionName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            SessionLayoutScanDraftGlassChip {

                HStack(spacing: 12) {

                    Text("Tally")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Text("\(scannedCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct SessionLayoutScanDraftGlassChip<Content: View>: View {

    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    private let chipHeight: CGFloat = 56

    var body: some View {

        content
            .frame(height: chipHeight)
            .padding(.horizontal, 18)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.14), lineWidth: 1)
            )
    }
}
