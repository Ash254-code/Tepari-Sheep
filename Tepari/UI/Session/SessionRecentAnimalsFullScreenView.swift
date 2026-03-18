import SwiftUI

struct SessionRecentAnimalsFullScreenView: View {
    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    private var sessionID: UUID? { coordinator.activeSessionID }

    private var records: [AnimalRecord] {
        guard let id = sessionID else { return [] }
        return store.records(for: id)
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Animals")
                                    .font(.title3.weight(.bold))

                                Spacer()

                                Text("\(records.count)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Divider().opacity(0.35)

                            RecentScansListView(records: ArraySlice(records))
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
