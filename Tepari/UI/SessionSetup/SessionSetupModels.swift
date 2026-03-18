import Foundation

// =========================================================
// MARK: - Session Setup scoped models (NO global name collisions)
// =========================================================
import Foundation

// =========================================================
// MARK: - Session Setup scoped models (NO global name collisions)
// =========================================================
enum SetupWizardStep: String, CaseIterable, Hashable {
    case farm
    case yards
    case mob
    case sessionTypes
    case scannerType
    case defaults
    case treatments
    case sessionName
    case review

    var title: String {
        switch self {
        case .farm: return "Farm"
        case .yards: return "Yards"
        case .mob: return "Mob"
        case .sessionTypes: return "Session Type"
        case .scannerType: return "Scanner Type"
        case .defaults: return "Defaults"
        case .treatments: return "Treatments"
        case .sessionName: return "Session Name"
        case .review: return "Review"
        }
    }
}
// ---------------------------------------------------------
// MARK: - Session Types
// ---------------------------------------------------------

enum SetupSessionType: String, CaseIterable, Identifiable, Hashable {
    case scan = "Scan"
    case weigh = "Weigh"
    case fleeceWeigh = "Fleece Weigh"
    case traitInput = "Trait Input"
    case draft = "Draft"
    case treatment = "Treatment"
    case lambMarking = "Lamb Marking"
    case pregTesting = "Preg Testing"

    // ✅ New
    case transfer = "Transfer"
    case sale = "Sale"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scan:        return "qrcode.viewfinder"
        case .weigh:       return "scalemass"
        case .fleeceWeigh: return "tshirt"
        case .traitInput:  return "list.bullet.rectangle"
        case .draft:       return "arrow.triangle.branch"
        case .treatment:   return "syringe"
        case .lambMarking: return "tag"
        case .pregTesting: return "waveform.path.ecg"
        case .transfer:    return "arrow.left.arrow.right"
        case .sale:        return "cart.fill"
        }
    }
}

struct SetupSessionTypeRules {

    /// Allowed *final* combinations.
    static let allowed: Set<Set<SetupSessionType>> = [

        // -----------------------------------------------------
        // Scan-centric (general)
        // -----------------------------------------------------
        [.scan],
        [.scan, .weigh],
        [.scan, .draft],
        [.scan, .weigh, .draft],
        [.scan, .weigh, .draft, .treatment],
        [.scan, .weigh, .treatment],
        [.scan, .treatment, .draft],
        [.scan, .traitInput],
        [.scan, .treatment],
        [.scan, .traitInput, .draft, .treatment],
        [.weigh, .draft],        // -----------------------------------------------------
        // ✅ Preg Testing (SPECIAL): MUST include draft
        // Scan → choose 0/1/2 → draft to pens
        // Optional: Treatment
        // -----------------------------------------------------
        [.scan, .pregTesting, .draft],
        [.scan, .pregTesting, .draft, .treatment],

        // -----------------------------------------------------
        // ✅ Fleece Weigh (SPECIAL): stick reader + fleece scales
        // Optional: Trait Input, Optional: Treatment
        // -----------------------------------------------------
        [.fleeceWeigh],
        [.fleeceWeigh, .traitInput],
        [.fleeceWeigh, .treatment],
        [.fleeceWeigh, .traitInput, .treatment],

        // -----------------------------------------------------
        // Lamb Marking (SPECIAL)
        // -----------------------------------------------------
        [.lambMarking, .treatment, .traitInput],

        // If you later want lamb marking to draft into pens too, uncomment:
        // [.lambMarking, .treatment, .draft],
        // [.lambMarking, .treatment, .traitInput, .draft],

        // -----------------------------------------------------
        // Transfer / Sale
        // -----------------------------------------------------
        [.transfer],
        [.transfer, .scan],
        [.sale],
        [.sale, .treatment],
        [.sale, .scan]
    ]

    /// Final-set validity (exact match with `allowed`)
    static func isValid(_ selection: Set<SetupSessionType>) -> Bool {
        allowed.contains(selection)
    }

    /// ✅ Reachability for progressive selection:
    /// Returns true if there exists an allowed final set that contains all selected items.
    static func isReachablePrefix(_ selection: Set<SetupSessionType>) -> Bool {
        guard !selection.isEmpty else { return true }
        return allowed.contains(where: { selection.isSubset(of: $0) })
    }

    /// Candidate is valid as a starting type.
    static func canStart(with candidate: SetupSessionType) -> Bool {
        isReachablePrefix([candidate])
    }

    /// Candidate can be added to the current selection while still being able to reach an allowed final set.
    static func canAdd(_ candidate: SetupSessionType, to selection: Set<SetupSessionType>) -> Bool {
        let next = selection.union([candidate])
        return isReachablePrefix(next)
    }

    static func validationMessage(_ selection: Set<SetupSessionType>) -> String? {
        guard !selection.isEmpty else { return "Select at least one session type." }
        if isValid(selection) { return nil }
        return "Only certain combinations are allowed."
    }
}

// ---------------------------------------------------------
// MARK: - Equipment (Session Setup scoped)
// ---------------------------------------------------------

enum SetupEquipment: String, CaseIterable, Identifiable, Hashable {
    case handler = "Handler"
    case draft = "Draft"
    case scanner = "Scanner"
    case scales = "Scales"
    case stickReader = "Stick Reader"
    case fleeceScales = "Fleece Scales"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .handler:      return "person.fill"
        case .draft:        return "arrow.triangle.branch"
        case .scanner:      return "qrcode.viewfinder"
        case .scales:       return "scalemass"
        case .stickReader:  return "dot.radiowaves.left.and.right"
        case .fleeceScales: return "tshirt"
        }
    }
}

// ---------------------------------------------------------
// MARK: - Defaults for NEW animals created during a session
// ---------------------------------------------------------
//
// Wizard-scoped state. Does NOT need Codable.
// You persist these into LocalDataStore per-session when starting the session.
//
struct SetupAnimalDefaults: Hashable {

    // 1) Sex
    var sex: LocalDataStore.Sex? = nil

    // 2) Breed (free text for now)
    var breed: String = ""

    // 3) Mob (name applied to NEW animals)
    var mobName: String = ""

    // 4) Class
    var animalClass: LocalDataStore.AnimalClass? = nil

    // 5) Birth Year
    var birthYear: Int? = nil

    // 6) Birth Month (1...12)
    var birthMonth: Int? = nil

    // 7) Current Status
    var status: AnimalStatus = .dry
}
