import Foundation

// =========================================================
// MARK: - Dose override value (per-session)
// =========================================================
//
// IMPORTANT:
// - This file assumes your project ALREADY has `DoseUnit` defined elsewhere.
// - This file ALSO assumes `DoseBasis` is defined elsewhere ONCE.
//   (Do not redeclare DoseBasis here, or you will get ambiguity/redeclaration errors.)
//

struct DoseValue: Codable, Hashable {
    var value: String
    var unit: DoseUnit

    /// Per animal vs per body weight
    var basis: DoseBasis

    /// Only used when basis == .perBodyWeight
    var perKg: String?

    // ✅ Keep old initializer calls working
    init(value: String, unit: DoseUnit) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = unit
        self.basis = .perAnimal
        self.perKg = nil
    }

    // ✅ New initializer for weight-based dosing
    init(value: String, unit: DoseUnit, basis: DoseBasis, perKg: String? = nil) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = unit
        self.basis = basis
        self.perKg = perKg?.trimmingCharacters(in: .whitespacesAndNewlines)

        normalize()
    }

    mutating func normalize() {
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch basis {
        case .perAnimal:
            perKg = nil

        case .perBodyWeight:
            let trimmed = perKg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            perKg = trimmed.isEmpty ? "10" : trimmed
        }
    }

    // Handy display for UI
    var displayString: String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return "" }

        switch basis {
        case .perAnimal:
            return "\(v) \(unit.rawValue)"
        case .perBodyWeight:
            let p = (perKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
            let per = p.isEmpty ? "10" : p
            return "\(v) \(unit.rawValue) / \(per) kg"
        }
    }
}

// =========================================================
// MARK: - Treatment template (Settings library item)
// =========================================================

struct TreatmentTemplate: Identifiable, Hashable, Codable {

    let id: UUID
    var product: String

    // Stored as split value + unit
    var doseValue: String
    var doseUnit: DoseUnit

    // Structured dose mode
    var doseBasis: DoseBasis
    var dosePerKg: String?

    var withholding: String

    // ---------------------------------------------
    // Codable keys (supports old saves)
    // ---------------------------------------------
    enum CodingKeys: String, CodingKey {
        case id, product, doseValue, doseUnit, withholding
        case doseBasis, dosePerKg
    }

    init(
        id: UUID = UUID(),
        product: String,
        doseValue: String,
        doseUnit: DoseUnit,
        withholding: String = ""
    ) {
        self.id = id
        self.product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        self.doseValue = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.doseUnit = doseUnit
        self.withholding = withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        // Defaults keep old callsites compiling
        self.doseBasis = .perAnimal
        self.dosePerKg = nil

        normalize()
    }

    init(
        id: UUID = UUID(),
        product: String,
        doseValue: String,
        doseUnit: DoseUnit,
        doseBasis: DoseBasis,
        dosePerKg: String? = nil,
        withholding: String = ""
    ) {
        self.id = id
        self.product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        self.doseValue = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.doseUnit = doseUnit
        self.doseBasis = doseBasis
        self.dosePerKg = dosePerKg?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.withholding = withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        normalize()
    }

    // -------------------------------------------------
    // MARK: - Backwards compat decode (auto-migrate)
    // -------------------------------------------------

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        product = try c.decode(String.self, forKey: .product)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        withholding = (try c.decodeIfPresent(String.self, forKey: .withholding) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        doseValue = (try c.decodeIfPresent(String.self, forKey: .doseValue) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        doseUnit = (try c.decodeIfPresent(DoseUnit.self, forKey: .doseUnit) ?? .mL)

        doseBasis = (try c.decodeIfPresent(DoseBasis.self, forKey: .doseBasis) ?? .perAnimal)
        dosePerKg = try c.decodeIfPresent(String.self, forKey: .dosePerKg)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Legacy ratio migration:
        // If older data shoved "1 mL/10kg" into doseValue or "1mL/10kg",
        // convert it to structured fields.
        if doseBasis == .perAnimal {
            let parsed = Self.parseRatioIfPresent(doseValue)
            if let p = parsed {
                doseValue = p.value
                doseUnit = p.unit
                doseBasis = .perBodyWeight
                dosePerKg = p.perKg
            }
        }

        normalize()
    }

    // -------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------

    mutating func normalize() {
        product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        doseValue = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        withholding = withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        switch doseBasis {
        case .perAnimal:
            dosePerKg = nil

        case .perBodyWeight:
            let trimmed = dosePerKg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            dosePerKg = trimmed.isEmpty ? "10" : trimmed
        }
    }

    var displayDoseString: String {
        let v = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return "" }

        switch doseBasis {
        case .perAnimal:
            return "\(v) \(doseUnit.rawValue)"
        case .perBodyWeight:
            let per = (dosePerKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
            let safePer = per.isEmpty ? "10" : per
            return "\(v) \(doseUnit.rawValue) / \(safePer) kg"
        }
    }

    // -------------------------------------------------
    // MARK: - Backwards compat builder
    // -------------------------------------------------

    /// Backwards compat for older code paths that used a legacy "3.4 mL" string.
    /// If the string is ratio-like (contains "/"), we parse it to structured fields.
    static func fromLegacyDoseString(
        id: UUID = UUID(),
        product: String,
        legacyDose: String,
        withholding: String = ""
    ) -> TreatmentTemplate {

        if let ratio = parseRatioIfPresent(legacyDose) {
            return TreatmentTemplate(
                id: id,
                product: product,
                doseValue: ratio.value,
                doseUnit: ratio.unit,
                doseBasis: .perBodyWeight,
                dosePerKg: ratio.perKg,
                withholding: withholding
            )
        }

        let parsed = parseLegacyDose(legacyDose, fallbackUnit: .mL)
        return TreatmentTemplate(
            id: id,
            product: product,
            doseValue: parsed.value,
            doseUnit: parsed.unit,
            withholding: withholding
        )
    }

    // MARK: - Legacy parsing (non-ratio)

    private static func parseLegacyDose(_ s: String, fallbackUnit: DoseUnit) -> (value: String, unit: DoseUnit) {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return ("", fallbackUnit) }

        let parts = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count >= 2 {
            let maybeUnit = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = DoseUnit(rawValue: maybeUnit) {
                let v = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        for u in DoseUnit.allCases {
            if raw.hasSuffix(u.rawValue) {
                let v = raw.replacingOccurrences(of: u.rawValue, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        return (raw, fallbackUnit)
    }

    // MARK: - Ratio parsing: "1mL/10kg", "1 mL/10 kg"

    private struct RatioParsed {
        var value: String
        var unit: DoseUnit
        var perKg: String
    }

    private static func parseRatioIfPresent(_ s: String) -> RatioParsed? {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let compact = raw.replacingOccurrences(of: " ", with: "")
        guard compact.contains("/") else { return nil }

        let parts = compact.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let left = parts[0]
        let right = parts[1]

        let rightLower = right.lowercased()
        guard rightLower.hasSuffix("kg") else { return nil }

        let perKgRaw = String(right.dropLast(2))
        let perKgTrim = perKgRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let perKg = perKgTrim.isEmpty ? "10" : perKgTrim

        let (v, u) = parseLegacyDose(left, fallbackUnit: .mL)
        let vv = v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vv.isEmpty else { return nil }

        return RatioParsed(value: vv, unit: u, perKg: perKg)
    }
}
