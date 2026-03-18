import Foundation
import Combine

// =========================================================
// MARK: - Draft Logical Target (ABSTRACTION LAYER)
// =========================================================

enum DraftLogicalTarget: String, Codable, CaseIterable, Hashable, Identifiable {
    case empty
    case single
    case twin
    case keep
    case cull
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .empty:  return "Empty"
        case .single: return "Single"
        case .twin:   return "Twin"
        case .keep:   return "Keep"
        case .cull:   return "Cull"
        case .custom: return "Custom"
        }
    }
}

// =========================================================
// MARK: - Gate Map
// =========================================================

struct DraftGateMap: Equatable, Codable {
    var empty: DraftPosition  = .left
    var single: DraftPosition = .straight
    var twin: DraftPosition   = .right

    var keep: DraftPosition   = .straight
    var cull: DraftPosition   = .left
    var custom: DraftPosition = .straight

    func physical(for logical: DraftLogicalTarget) -> DraftPosition {
        switch logical {
        case .empty:  return empty
        case .single: return single
        case .twin:   return twin
        case .keep:   return keep
        case .cull:   return cull
        case .custom: return custom
        }
    }
}

// =========================================================
// MARK: - Draft Rule
// =========================================================

struct DraftRule: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String

    // Optional filters
    var minWeight: Double?
    var maxWeight: Double?
    var klassEquals: String?
    var mobID: UUID?

    // Legacy physical result
    var result: DraftPosition

    // Preferred logical target
    var logicalTarget: DraftLogicalTarget? = nil

    init(
        id: UUID = UUID(),
        name: String,
        minWeight: Double? = nil,
        maxWeight: Double? = nil,
        klassEquals: String? = nil,
        mobID: UUID? = nil,
        result: DraftPosition = .straight,
        logicalTarget: DraftLogicalTarget? = nil
    ) {
        self.id = id
        self.name = name
        self.minWeight = minWeight
        self.maxWeight = maxWeight
        self.klassEquals = klassEquals
        self.mobID = mobID
        self.result = result
        self.logicalTarget = logicalTarget
    }

    func matches(
        weight: Double,
        animal: LocalDataStore.AnimalProfile?
    ) -> Bool {

        if let minWeight, weight < minWeight { return false }
        if let maxWeight, weight > maxWeight { return false }

        if let klassEquals {
            let expected = klassEquals.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let animalKlass = animal?.klass?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let animalClassLabel = animal?.animalClass?.rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let matchesKlass = animalKlass == expected
            let matchesAnimalClass = animalClassLabel == expected

            if !matchesKlass && !matchesAnimalClass {
                return false
            }
        }

        if let mobID {
            guard animal?.mobID == mobID else { return false }
        }

        return true
    }

    func resolvedPosition(using map: DraftGateMap) -> DraftPosition {
        if let logicalTarget {
            return map.physical(for: logicalTarget)
        }
        return result
    }
}

// =========================================================
// MARK: - Rule Engine
// =========================================================

@MainActor
final class DraftRuleEngine: ObservableObject {

    struct Evaluation: Equatable {
        var position: DraftPosition
        var logicalTarget: DraftLogicalTarget?
        var matchedRuleName: String?
    }

    @Published var rules: [DraftRule] = []
    @Published var gateMap: DraftGateMap = DraftGateMap()

    var defaultPosition: DraftPosition = .straight
    var defaultLogicalTarget: DraftLogicalTarget? = nil

    // =====================================================
    // MARK: - Rule editing
    // =====================================================

    func addRule(_ rule: DraftRule) {
        rules.append(rule)
    }

    func updateRule(_ rule: DraftRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func moveRules(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty else { return }

        var items = rules
        let moving = offsets.map { items[$0] }

        for i in offsets.sorted(by: >) {
            items.remove(at: i)
        }

        let removedBefore = offsets.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(items.count, destination - removedBefore))

        items.insert(contentsOf: moving, at: adjustedDestination)
        rules = items
    }

    func replaceAllRules(_ newRules: [DraftRule]) {
        rules = newRules
    }

    func clearRules() {
        rules.removeAll()
    }

    // =====================================================
    // MARK: - Convenience builders from UI
    // =====================================================

    func makeWeightRule(
        name: String,
        minWeight: Double?,
        maxWeight: Double?,
        gate: DraftPosition
    ) -> DraftRule {
        DraftRule(
            name: name,
            minWeight: minWeight,
            maxWeight: maxWeight,
            result: gate
        )
    }

    func makeMobRule(
        name: String,
        mobID: UUID,
        gate: DraftPosition
    ) -> DraftRule {
        DraftRule(
            name: name,
            mobID: mobID,
            result: gate
        )
    }

    func makeClassRule(
        name: String,
        className: String,
        gate: DraftPosition
    ) -> DraftRule {
        DraftRule(
            name: name,
            klassEquals: className,
            result: gate
        )
    }

    func makePregRule(
        name: String,
        logicalTarget: DraftLogicalTarget
    ) -> DraftRule {
        DraftRule(
            name: name,
            result: gateMap.physical(for: logicalTarget),
            logicalTarget: logicalTarget
        )
    }

    // =====================================================
    // MARK: - Evaluate animal
    // =====================================================

    func evaluateDetailed(
        eid: String,
        weight: Double,
        store: LocalDataStore,
        farmID: UUID?
    ) -> Evaluation {

        let profile: LocalDataStore.AnimalProfile?

        if let farmID {
            profile = store.animalProfile(
                farmID: farmID,
                eidRaw: eid
            )
        } else {
            profile = nil
        }

        for rule in rules {
            if rule.matches(weight: weight, animal: profile) {
                let physical = rule.resolvedPosition(using: gateMap)
                return Evaluation(
                    position: physical,
                    logicalTarget: rule.logicalTarget,
                    matchedRuleName: rule.name
                )
            }
        }

        if let logical = defaultLogicalTarget {
            return Evaluation(
                position: gateMap.physical(for: logical),
                logicalTarget: logical,
                matchedRuleName: nil
            )
        } else {
            return Evaluation(
                position: defaultPosition,
                logicalTarget: nil,
                matchedRuleName: nil
            )
        }
    }

    func evaluate(
        eid: String,
        weight: Double,
        store: LocalDataStore,
        farmID: UUID?
    ) -> DraftPosition {
        evaluateDetailed(
            eid: eid,
            weight: weight,
            store: store,
            farmID: farmID
        ).position
    }
}
