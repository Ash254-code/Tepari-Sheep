import Foundation

/// High-level UI layouts for Session screen.
enum SessionLayoutKind: Hashable {

    // Existing
    case weighDraft
    case scanTreat
    case scanDraft
    case scanTraits
    case scanOnly
    case treatOnly
    case draftOnly
    case transferSaleForm

    // New scan/weigh combinations
    case scanWeigh
    case scanWeighTreat
    case scanWeighDraft
    case scanWeighTreatDraft

    // Special purpose layouts
    case pregTestDraft
    case fleeceWeigh
    case lambMarking
    case lambMarkingTreatTrait

    static func from(types: Set<SetupSessionType>) -> SessionLayoutKind {

        let hasScan   = types.contains(.scan)
        let hasWeigh  = types.contains(.weigh)
        let hasTreat  = types.contains(.treatment)
        let hasDraft  = types.contains(.draft)
        let hasTraits = types.contains(.traitInput)

        let hasTransfer = types.contains(.transfer)
        let hasSale     = types.contains(.sale)

        let hasPregTest    = types.contains(.pregTesting)
        let hasFleeceWeigh = types.contains(.fleeceWeigh)
        let hasLambMarking = types.contains(.lambMarking)

        // ---------------------------------------------------------
        // 1) Hard overrides: Transfer / Sale always win
        // ---------------------------------------------------------
        if hasTransfer || hasSale {
            return .transferSaleForm
        }

        // ---------------------------------------------------------
        // 2) Special purpose workflows
        // ---------------------------------------------------------
        if hasPregTest {
            return .pregTestDraft
        }

        if hasFleeceWeigh {
            return .fleeceWeigh
        }

        if hasLambMarking && hasTraits && hasTreat {
            return .lambMarkingTreatTrait
        }

        if hasLambMarking {
            return .lambMarking
        }

        // ---------------------------------------------------------
        // 3) Traits workflow
        // ---------------------------------------------------------
        if hasTraits {
            return .scanTraits
        }

        // ---------------------------------------------------------
        // 4) Explicit scan/weigh/treat/draft combinations
        // ---------------------------------------------------------
        if hasScan && hasWeigh && hasTreat && hasDraft {
            return .scanWeighTreatDraft
        }

        if hasScan && hasWeigh && hasTreat {
            return .scanWeighTreat
        }

        if hasScan && hasWeigh && hasDraft {
            return .scanWeighDraft
        }

        if hasScan && hasWeigh {
            return .scanWeigh
        }

        // ---------------------------------------------------------
        // 5) Legacy / simpler draft routing
        // ---------------------------------------------------------
        if hasWeigh && hasDraft {
            return .weighDraft
        }

        if hasScan && hasDraft {
            return .scanDraft
        }

        if hasDraft {
            return .draftOnly
        }

        // ---------------------------------------------------------
        // 6) Treatment routing
        // ---------------------------------------------------------
        if hasScan && hasTreat && !hasWeigh {
            return .scanTreat
        }

        if hasTreat && !hasScan && !hasWeigh {
            return .treatOnly
        }

        // ---------------------------------------------------------
        // 7) Scan-only
        // ---------------------------------------------------------
        if hasScan && !hasWeigh {
            return .scanOnly
        }

        // ---------------------------------------------------------
        // 8) Weigh-only fallback
        // ---------------------------------------------------------
        if hasWeigh {
            return .scanWeigh
        }

        // ---------------------------------------------------------
        // Final fallback
        // ---------------------------------------------------------
        return .scanOnly
    }
}
