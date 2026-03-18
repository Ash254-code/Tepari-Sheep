import SwiftUI

struct SessionSetupEquipmentStepView: View {

    // MARK: - Binding
    @Binding var selectedEquipment: Set<SetupEquipment>

    // MARK: - Inputs (derived in parent)
    let isLockedScanWeighOnly: Bool
    let forcedEquipmentForLockedScanWeighOnly: Set<SetupEquipment>
    let requiredEquipmentFromTypes: Set<SetupEquipment>

    // MARK: - Actions
    let onSelectionChanged: () -> Void

    // MARK: - Body
    var body: some View {
        WizardTileGrid(
            title: "Equipment",
            caption: isLockedScanWeighOnly
                ? "Auto-filled for Scan + Weigh (locked)."
                : "Select the gear you’ll use. Some items auto-fill based on Session Type.",
            tiles: equipmentTiles,
            selection: equipmentSelectionBinding,
            allowsMultipleSelection: true,
            isTileEnabled: { tile in
                guard let eq = SetupEquipment(rawValue: tile.id) else { return true }
                if isLockedScanWeighOnly {
                    return forcedEquipmentForLockedScanWeighOnly.contains(eq)
                }
                return true
            },
            isTileLockedOn: { tile in
                guard let eq = SetupEquipment(rawValue: tile.id) else { return false }
                if isLockedScanWeighOnly {
                    return forcedEquipmentForLockedScanWeighOnly.contains(eq)
                }
                return requiredEquipmentFromTypes.contains(eq)
            },
            onSelectionChanged: { _ in
                onSelectionChanged()
            }
        )
    }

    // MARK: - Tiles
    private var equipmentTiles: [WizardTile] {
        SetupEquipment.allCases.map { eq in
            WizardTile(
                id: eq.rawValue,          // ✅ matches SetupEquipment(rawValue:)
                title: eq.rawValue,       // ✅ your display label
                systemImage: eq.icon,     // ✅ your SF Symbol string
                subtitle: nil
            )
        }
    }

    // MARK: - Selection bridge (Set<SetupEquipment> <-> Set<String>)
    private var equipmentSelectionBinding: Binding<Set<String>> {
        Binding<Set<String>>(
            get: { Set(selectedEquipment.map { $0.rawValue }) },
            set: { newIDs in
                let mapped = Set(newIDs.compactMap { SetupEquipment(rawValue: $0) })
                if mapped != selectedEquipment {
                    selectedEquipment = mapped
                    onSelectionChanged()
                }
            }
        )
    }
}
