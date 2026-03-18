import SwiftUI

struct SessionGenericFullRecordListView: View {

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

                                HStack(spacing: 10) {

                                    if r.lockedWeight > 0 {
                                        Text(String(format: "%.1f kg", r.lockedWeight))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let pos = r.draftResult {
                                        Text(positionLabel(pos))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .font(.subheadline)
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
