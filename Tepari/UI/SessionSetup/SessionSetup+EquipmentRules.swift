import Foundation

extension SessionSetupView {

    /// EXACT rule:
    /// If Session Types == Scan + Weigh (and nothing else) → lock equipment to Handler + Scales ONLY.
    var isLockedScanWeighOnly: Bool {
        selectedTypes == Set([SetupSessionType.scan, SetupSessionType.weigh])
    }

    var forcedEquipmentForLockedScanWeighOnly: Set<SetupEquipment> {
        Set([.handler, .scales])
    }

    var requiredEquipmentFromTypes: Set<SetupEquipment> {
        var req: Set<SetupEquipment> = []
        if selectedTypes.contains(.scan) { req.insert(.handler) }
        if selectedTypes.contains(.weigh) { req.insert(.scales) }
        if selectedTypes.contains(.fleeceWeigh) { req.insert(.fleeceScales) }
        if selectedTypes.contains(.draft) { req.insert(.draft) }
        return req
    }

    func applyEquipmentRulesFromSessionTypes() {
        if isLockedScanWeighOnly {
            selectedEquipment = forcedEquipmentForLockedScanWeighOnly
            return
        }

        // Auto-add required items but keep extras user selected
        selectedEquipment.formUnion(requiredEquipmentFromTypes)
    }
}
