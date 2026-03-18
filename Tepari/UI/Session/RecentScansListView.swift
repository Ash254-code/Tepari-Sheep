import SwiftUI

struct RecentScansListView: View {
    let records: ArraySlice<AnimalRecord>

    var body: some View {
        if records.isEmpty {
            Text("No scans yet.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        } else {
            VStack(spacing: 10) {
                ForEach(records) { r in
                    HStack {
                        Text(r.eidRaw)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer()

                        Text("\(DecimalWeightFormatter.oneDecimal(r.lockedWeight)) kg")
                            .font(.subheadline.weight(.semibold))

                        Text(r.recordedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    .padding(.vertical, 6)

                    Divider().opacity(0.25)
                }
            }
        }
    }
}
