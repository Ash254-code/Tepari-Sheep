import SwiftUI
import Foundation

struct SessionTreatmentsInfoView: View {
    @EnvironmentObject private var store: LocalDataStore
    let sessionID: UUID

    private var treatments: [SessionTreatment] {
        store.treatments(for: sessionID)
    }

    var body: some View {
        List {
            Section {
                Text("These treatments are applied automatically whenever an animal is scanned in this session.")
                    .foregroundStyle(.secondary)
            }

            if treatments.isEmpty {
                Section("Selected") {
                    Text("No treatments selected for this session.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Selected") {
                    ForEach(Array(treatments.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.product)
                                .font(.headline)

                            let dose = t.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !dose.isEmpty {
                                Text("Dose: \(dose)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            let w = t.withholding.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !w.isEmpty {
                                Text("Withholding: \(w) days")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
