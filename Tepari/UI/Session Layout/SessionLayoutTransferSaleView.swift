import SwiftUI

struct SessionLayoutTransferSaleView: View {

    @EnvironmentObject private var store: LocalDataStore

    @ObservedObject var vm: SessionViewModel

    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            HStack(alignment: .center, spacing: 10) {
                Circle().fill(Color.green).frame(width: 8, height: 8)

                Text(vm.activeSession.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Tally")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(scannedCount)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Divider().opacity(0.25)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {

                    EIDDisplayView(
                        eid: "—",
                        farmID: nil
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transfer / Sale")
                                .font(.headline)

                            Text("Dedicated layout bucket for Transfer and Sale sessions. Next: plug in PIC fields / sale reference / confirm actions here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showDetails {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent Scans")
                                    .font(.headline)

                                RecentScansListView(
                                    records: store.records(for: vm.activeSession.id).prefix(12)
                                )
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }

            VStack(spacing: 10) {
                Divider().opacity(0.25)

                if isPhone {
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
                            title: showDetails ? "Hide" : "Display",
                            systemImage: showDetails ? "chevron.down" : "chevron.up",
                            dotColor: nil,
                            height: 54,
                            enabled: true
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showDetails.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    let ipadButtonHeight: CGFloat = 96

                    HStack(spacing: 10) {
                        Button("New Session") { onStartNewSession() }
                            .frame(maxWidth: .infinity)
                            .frame(height: ipadButtonHeight)
                            .glassButton(.compact)

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showDetails.toggle()
                            }
                        } label: {
                            Label(
                                showDetails ? "Hide" : "Display",
                                systemImage: showDetails ? "chevron.down" : "chevron.up"
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: ipadButtonHeight)
                        .glassButton(.compact)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .safeAreaPadding(.bottom, isPhone ? 0 : 90)
        .onAppear { onSyncCoordinator() }
    }
}
