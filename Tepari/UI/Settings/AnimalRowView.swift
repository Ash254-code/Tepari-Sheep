import SwiftUI

struct AnimalRowView: View, Equatable {

    let row: AnimalDataViewModel.AnimalRowModel
    let isSelected: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text(row.animal.eidRaw)
                .font(.headline)

            HStack {
                Text(row.mobName)
                Text(row.className)
                Text(row.totalLambsText)
            }

            Text(row.lastScanText)
                .foregroundStyle(.secondary)
        }
    }
}
