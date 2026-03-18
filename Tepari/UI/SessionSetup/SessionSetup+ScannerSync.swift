import Foundation

extension SessionSetupView {

    /// If user picks scanner type later, keep equipment consistent.
    func applyScannerSelectionToEquipment() {

        guard !isLockedScanWeighOnly else { return }

        // clear both scanner indicators first
        selectedEquipment.remove(.scanner)
        selectedEquipment.remove(.stickReader)

        switch scannerType {
        case .racewell:
            selectedEquipment.insert(.scanner)

        case .stickReader:
            selectedEquipment.insert(.stickReader)

        case .xrp2i:
            selectedEquipment.insert(.scanner)

        case .manual, .none:
            break
        }
    }
}
