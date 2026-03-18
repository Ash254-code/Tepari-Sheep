import SwiftUI

struct SessionSetupChooseScannerStepView: View {

    @Binding var scannerType: LocalDataStore.ScannerType?

    private let options: [LocalDataStore.ScannerType] = [
        .racewell,      // T1 Integrated EID
        .stickReader,
        .xrp2i,
        .manual
    ]

    var body: some View {
        WizardTileGrid(
            title: "Choose Scanner",
            caption: "This is a Scan-only session. Pick which scanner to use.",
            tiles: options.map { t in
                WizardTile(
                    id: t.rawValue,
                    title: t.label,
                    systemImage: t.icon,
                    subtitle: nil
                )
            },
            selection: Binding<Set<String>>(
                get: {
                    if let s = scannerType?.rawValue { return [s] }
                    return []
                },
                set: { newSet in
                    scannerType = newSet.first.flatMap { LocalDataStore.ScannerType(rawValue: $0) }
                }
            ),
            allowsMultipleSelection: false,
            isTileEnabled: { _ in true },
            onSelectionChanged: { _ in }
        )
    }
}
