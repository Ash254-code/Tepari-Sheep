import Foundation

// =========================================================
// MARK: - Animal Event (lifetime history)
// =========================================================

enum AnimalEventKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case weight
    case pregnancy
    case lambing
    case treatment
    case traits
    case lastSeen

    var id: String { rawValue }
}

/// Generic event payload to move fast without schema pain.
/// We can split into typed event structs later if needed.
struct AnimalEvent: Identifiable, Codable, Hashable {
    let id: UUID

    /// Farm context at time of event.
    /// (Animals can transfer farms over time.)
    var farmID: UUID

    /// Canonical identifier for the animal.
    var eidRaw: String

    var kind: AnimalEventKind
    var date: Date

    // ---------------------------------------------------------
    // Flexible payload slots (keep v1 simple + future-proof)
    // ---------------------------------------------------------
    var number1: Double?
    var number2: Double?
    var int1: Int?
    var text1: String?
    var text2: String?
    var json: [String: String]?

    init(
        id: UUID = UUID(),
        farmID: UUID,
        eidRaw: String,
        kind: AnimalEventKind,
        date: Date,
        number1: Double? = nil,
        number2: Double? = nil,
        int1: Int? = nil,
        text1: String? = nil,
        text2: String? = nil,
        json: [String: String]? = nil
    ) {
        self.id = id
        self.farmID = farmID
        self.eidRaw = EIDValidator.cleanedRaw(eidRaw)
        self.kind = kind
        self.date = date

        self.number1 = number1
        self.number2 = number2
        self.int1 = int1

        let t1 = text1?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text1 = (t1?.isEmpty == true) ? nil : t1

        let t2 = text2?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text2 = (t2?.isEmpty == true) ? nil : t2

        self.json = (json?.isEmpty == true) ? nil : json
    }
}

// =========================================================
// MARK: - Convenience accessors (optional but very handy)
// =========================================================

extension AnimalEvent {

    /// For `.weight`: kilograms stored in number1
    var weightKg: Double? {
        guard kind == .weight else { return nil }
        return number1
    }

    /// For `.pregnancy`: fetus count stored in int1
    var fetusCount: Int? {
        guard kind == .pregnancy else { return nil }
        return int1
    }

    /// For `.pregnancy`: status stored in text1 (e.g. "Empty", "Pregnant", "Recheck")
    var pregStatus: String? {
        guard kind == .pregnancy else { return nil }
        return text1
    }

    /// For `.treatment`: product stored in text1, dose stored in text2
    var treatmentProduct: String? {
        guard kind == .treatment else { return nil }
        return text1
    }

    var treatmentDose: String? {
        guard kind == .treatment else { return nil }
        return text2
    }
}

// =========================================================
// MARK: - Lightweight factory helpers (optional)
// =========================================================

extension AnimalEvent {

    static func weight(
        farmID: UUID,
        eidRaw: String,
        date: Date,
        kg: Double,
        notes: String? = nil,
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String]? = nil
        if let sessionID { json = (json ?? [:]).merging(["sessionID": sessionID.uuidString], uniquingKeysWith: { $1 }) }
        return AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .weight,
            date: date,
            number1: kg,
            text1: notes,
            json: json
        )
    }

    static func lastSeen(
        farmID: UUID,
        eidRaw: String,
        date: Date,
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String]? = nil
        if let sessionID { json = (json ?? [:]).merging(["sessionID": sessionID.uuidString], uniquingKeysWith: { $1 }) }
        return AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .lastSeen,
            date: date,
            json: json
        )
    }

    static func pregnancy(
        farmID: UUID,
        eidRaw: String,
        date: Date,
        status: String,
        fetusCount: Int? = nil,
        method: String? = nil,
        notes: String? = nil,
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String]? = nil
        if let method, !method.isEmpty { json = (json ?? [:]).merging(["method": method], uniquingKeysWith: { $1 }) }
        if let sessionID { json = (json ?? [:]).merging(["sessionID": sessionID.uuidString], uniquingKeysWith: { $1 }) }

        // Store:
        // text1 = status, text2 = notes, int1 = fetusCount
        return AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .pregnancy,
            date: date,
            int1: fetusCount,
            text1: status,
            text2: notes,
            json: json
        )
    }
}
