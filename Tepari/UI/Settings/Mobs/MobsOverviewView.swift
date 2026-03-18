import SwiftUI

// =====================================================
// MARK: - Mobs Overview (grouped by farm)
// =====================================================

struct MobsOverviewView: View {
    @EnvironmentObject private var store: LocalDataStore

    @State private var mobSheetTarget: MobSheetTarget? = nil

    private struct MobSheetTarget: Identifiable, Equatable {
        let farmID: UUID
        let editMobID: UUID?

        var id: String {
            "\(farmID.uuidString)|\(editMobID?.uuidString ?? "new")"
        }
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // Top header card
                    GlassCard {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mobs")
                                    .font(.headline.weight(.semibold))
                                Text("All mobs grouped by farm")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }

                    // Farms -> each farm has its mobs inside
                    ForEach(store.farms) { farm in
                        FarmMobsCard(
                            farmName: farm.name,
                            farmPIC: farm.pic,
                            mobs: store.mobs(for: farm.id),
                            onAddMob: {
                                mobSheetTarget = MobSheetTarget(
                                    farmID: farm.id,
                                    editMobID: nil
                                )
                            },
                            onEditMob: { mob in
                                mobSheetTarget = MobSheetTarget(
                                    farmID: farm.id,
                                    editMobID: mob.id
                                )
                            },
                            onDeleteMob: { mob in
                                store.deleteMob(mob.id)
                            }
                        )
                    }

                    if store.farms.isEmpty {
                        GlassCard {
                            Text("No farms yet. Add a farm first, then create mobs inside it.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Mobs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $mobSheetTarget) { target in
            NavigationStack {
                MobSetupView(
                    farmID: target.farmID,
                    editMobID: target.editMobID
                )
                .environmentObject(store)
            }
        }
    }
}

// =====================================================
// MARK: - Farm Card (with mobs inside)
// =====================================================

private struct FarmMobsCard: View {
    let farmName: String
    let farmPIC: String
    let mobs: [LocalDataStore.Mob]

    let onAddMob: () -> Void
    let onEditMob: (LocalDataStore.Mob) -> Void
    let onDeleteMob: (LocalDataStore.Mob) -> Void

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var anchorYear: Int {
        currentYear + 1
    }

    private func inferredYearFromColourHex(_ hex: String) -> Int? {
        guard let mobColour = MobColour.from(hex: hex) else { return nil }
        let years = YearColourCycle.yearsList(referenceDate: Date())
        return years.first { YearColourCycle.colour(for: $0, anchorYear: anchorYear) == mobColour }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                // Header row (farm title left, add button fixed right)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(farmName)
                            .font(.headline.weight(.semibold))

                        if !farmPIC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("PIC: \(farmPIC)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Button(action: onAddMob) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                            Text("Add Mob")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minWidth: 160, alignment: .center)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.18)

                if mobs.isEmpty {
                    Text("No mobs yet for this farm.")
                        .foregroundStyle(.secondary)
                } else {
                    FlowWrapLayout(spacing: 10, lineSpacing: 10) {
                        ForEach(mobs) { mob in
                            let colour = MobColour.from(hex: mob.colorHex) ?? .green
                            let year = inferredYearFromColourHex(mob.colorHex)
                            let label = year == nil ? mob.name : "\(mob.name)-\(year!)"

                            MobNamePill(name: label, colour: colour)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onEditMob(mob)
                                }
                                .contextMenu {
                                    Button {
                                        onEditMob(mob)
                                    } label: {
                                        Label("Edit Mob", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteMob(mob)
                                    } label: {
                                        Label("Delete Mob", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
// MARK: - Flow Wrap Layout (pills wrap to next line)
// =====================================================

private struct FlowWrapLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {

        let maxWidth = proposal.width ?? .greatestFiniteMagnitude

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += (x == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: proposal.width ?? maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width

        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > bounds.minX, (x + size.width) > (bounds.minX + maxWidth) {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            s.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
