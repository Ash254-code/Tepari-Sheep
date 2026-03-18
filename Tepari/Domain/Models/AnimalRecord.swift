import Foundation

// =========================================================
// MARK: - Session Treatment
// =========================================================

struct SessionTreatment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var product: String

    /// Human-readable dose string kept for backward compatibility and easy display.
    /// Examples:
    /// - "3.4 mL"
    /// - "1 mL / 10 kg"
    var dosage: String

    var withholding: String
    var createdAt: Date

    // =====================================================
    // MARK: - Structured dosing fields
    // =====================================================

    /// Base entered dose amount, e.g. "2", "0.5", "3.4"
    var doseValue: String?

    /// Dose unit, e.g. mL, mg
    var doseUnit: DoseUnit?

    /// Per animal vs per body weight
    var doseBasis: DoseBasis?

    /// Only used when basis == .perBodyWeight
    /// Example: "10" for "per 10 kg"
    var dosePerKg: String?

    /// Optional minimum calculated dose
    var minimumDose: String?

    /// Optional maximum calculated dose
    var maximumDose: String?

    /// Optional rounding step
    var doseStep: String?

    /// Require stable weight before auto-calculating/sending
    var requiresStableWeight: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case product
        case dosage
        case withholding
        case createdAt

        case doseValue
        case doseUnit
        case doseBasis
        case dosePerKg
        case minimumDose
        case maximumDose
        case doseStep
        case requiresStableWeight
    }

    init(
        id: UUID = UUID(),
        product: String,
        dosage: String,
        withholding: String,
        createdAt: Date = Date(),
        doseValue: String? = nil,
        doseUnit: DoseUnit? = nil,
        doseBasis: DoseBasis? = nil,
        dosePerKg: String? = nil,
        minimumDose: String? = nil,
        maximumDose: String? = nil,
        doseStep: String? = nil,
        requiresStableWeight: Bool? = nil
    ) {
        self.id = id
        self.product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.withholding = withholding.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt

        self.doseValue = Self.cleanOptionalString(doseValue)
        self.doseUnit = doseUnit
        self.doseBasis = doseBasis
        self.dosePerKg = Self.cleanOptionalString(dosePerKg)
        self.minimumDose = Self.cleanOptionalString(minimumDose)
        self.maximumDose = Self.cleanOptionalString(maximumDose)
        self.doseStep = Self.cleanOptionalString(doseStep)
        self.requiresStableWeight = requiresStableWeight

        normalizeStructuredDoseFields()
        refreshDosageStringIfPossible()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        product = try c.decode(String.self, forKey: .product)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        dosage = (try c.decodeIfPresent(String.self, forKey: .dosage) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        withholding = (try c.decodeIfPresent(String.self, forKey: .withholding) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        doseValue = Self.cleanOptionalString(try c.decodeIfPresent(String.self, forKey: .doseValue))
        doseUnit = try c.decodeIfPresent(DoseUnit.self, forKey: .doseUnit)
        doseBasis = try c.decodeIfPresent(DoseBasis.self, forKey: .doseBasis)
        dosePerKg = Self.cleanOptionalString(try c.decodeIfPresent(String.self, forKey: .dosePerKg))
        minimumDose = Self.cleanOptionalString(try c.decodeIfPresent(String.self, forKey: .minimumDose))
        maximumDose = Self.cleanOptionalString(try c.decodeIfPresent(String.self, forKey: .maximumDose))
        doseStep = Self.cleanOptionalString(try c.decodeIfPresent(String.self, forKey: .doseStep))
        requiresStableWeight = try c.decodeIfPresent(Bool.self, forKey: .requiresStableWeight)

        // Backward compatibility:
        // Older saved data may only have `dosage`, e.g.:
        // - "3.4 mL"
        // - "1 mL / 10 kg"
        if (doseValue == nil || doseUnit == nil || doseBasis == nil), !dosage.isEmpty {
            let parsed = parseLegacyDosage(dosage)

            if doseValue == nil { doseValue = parsed.value }
            if doseUnit == nil { doseUnit = parsed.unit }
            if doseBasis == nil { doseBasis = parsed.basis }
            if dosePerKg == nil { dosePerKg = parsed.perKg }
        }

        normalizeStructuredDoseFields()
        refreshDosageStringIfPossible()
    }

    mutating func refreshDosageStringIfPossible() {
        let newString = displayDoseString
        if !newString.isEmpty {
            dosage = newString
        }
    }

    var displayDoseString: String {
        let value = (doseValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let unit = (doseUnit ?? .mL).rawValue
        switch doseBasis ?? .perAnimal {
        case .perAnimal:
            return "\(value) \(unit)"
        case .perBodyWeight:
            let per = (dosePerKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
            let safePer = per.isEmpty ? "10" : per
            return "\(value) \(unit) / \(safePer) kg"
        }
    }

    var dosingSummary: String {
        var parts: [String] = []

        let main = displayDoseString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !main.isEmpty {
            parts.append(main)
        }

        let unitText = (doseUnit ?? .mL).rawValue

        if let min = minimumDose?.trimmedNonEmpty {
            parts.append("Min \(min) \(unitText)")
        }

        if let max = maximumDose?.trimmedNonEmpty {
            parts.append("Max \(max) \(unitText)")
        }

        if let step = doseStep?.trimmedNonEmpty {
            parts.append("Step \(step) \(unitText)")
        }

        if stableWeightRequired {
            parts.append("Stable wt")
        }

        return parts.joined(separator: " · ")
    }

    var stableWeightRequired: Bool {
        requiresStableWeight ?? true
    }

    var typedDoseValue: Double? {
        Self.parseNumber(doseValue)
    }

    var typedDosePerKg: Double? {
        Self.parseNumber(dosePerKg)
    }

    var typedMinimumDose: Double? {
        Self.parseNumber(minimumDose)
    }

    var typedMaximumDose: Double? {
        Self.parseNumber(maximumDose)
    }

    var typedDoseStep: Double? {
        Self.parseNumber(doseStep)
    }

    var canCalculateDose: Bool {
        guard let amount = typedDoseValue, amount > 0 else { return false }

        switch doseBasis ?? .perAnimal {
        case .perAnimal:
            return true
        case .perBodyWeight:
            guard let perKg = typedDosePerKg else { return false }
            return perKg > 0
        }
    }

    func calculatedDose(forWeightKg weightKg: Double) -> Double? {
        guard weightKg > 0 else { return nil }
        guard let amount = typedDoseValue, amount > 0 else { return nil }

        var calculated: Double

        switch doseBasis ?? .perAnimal {
        case .perAnimal:
            calculated = amount

        case .perBodyWeight:
            guard let perKg = typedDosePerKg, perKg > 0 else { return nil }
            calculated = (weightKg / perKg) * amount
        }

        if let min = typedMinimumDose {
            calculated = max(calculated, min)
        }

        if let max = typedMaximumDose {
            calculated = min(calculated, max)
        }

        if let step = typedDoseStep, step > 0 {
            calculated = (calculated / step).rounded() * step
        }

        return calculated
    }

    func calculatedDoseString(forWeightKg weightKg: Double) -> String? {
        guard let value = calculatedDose(forWeightKg: weightKg) else { return nil }
        return "\(value.cleanDoseText) \((doseUnit ?? .mL).rawValue)"
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private mutating func normalizeStructuredDoseFields() {
        doseValue = Self.cleanOptionalString(doseValue)
        dosePerKg = Self.cleanOptionalString(dosePerKg)
        minimumDose = Self.cleanOptionalString(minimumDose)
        maximumDose = Self.cleanOptionalString(maximumDose)
        doseStep = Self.cleanOptionalString(doseStep)

        if requiresStableWeight == nil {
            requiresStableWeight = true
        }

        let value = (doseValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            if doseUnit == nil { doseUnit = .mL }
            if doseBasis == nil { doseBasis = .perAnimal }

            if doseBasis == .perBodyWeight {
                let per = (dosePerKg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if per.isEmpty {
                    dosePerKg = "10"
                }
            } else {
                dosePerKg = nil
            }
        } else {
            dosePerKg = nil
        }
    }

    private static func cleanOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseNumber(_ text: String?) -> Double? {
        guard let cleaned = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "."),
              !cleaned.isEmpty else {
            return nil
        }

        return Double(cleaned)
    }

    private struct ParsedLegacyDose {
        var value: String?
        var unit: DoseUnit?
        var basis: DoseBasis?
        var perKg: String?
    }

    private func parseLegacyDosage(_ raw: String) -> ParsedLegacyDose {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParsedLegacyDose(value: nil, unit: nil, basis: nil, perKg: nil)
        }

        let compact = text.replacingOccurrences(of: " ", with: "")

        if compact.contains("/") {
            let parts = compact.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1]

                var parsedPerKg: String? = nil
                let rightLower = right.lowercased()
                if rightLower.hasSuffix("kg") {
                    let n = String(right.dropLast(2))
                    let cleaned = n.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsedPerKg = cleaned.isEmpty ? "10" : cleaned
                }

                let pair = parseAmountAndUnit(left, fallbackUnit: .mL)
                return ParsedLegacyDose(
                    value: pair.value,
                    unit: pair.unit,
                    basis: .perBodyWeight,
                    perKg: parsedPerKg ?? "10"
                )
            }
        }

        let pair = parseAmountAndUnit(compact, fallbackUnit: .mL)
        return ParsedLegacyDose(
            value: pair.value,
            unit: pair.unit,
            basis: .perAnimal,
            perKg: nil
        )
    }

    private func parseAmountAndUnit(_ compact: String, fallbackUnit: DoseUnit) -> (value: String?, unit: DoseUnit) {
        for unit in DoseUnit.allCases {
            if compact.hasSuffix(unit.rawValue) {
                let value = compact
                    .replacingOccurrences(of: unit.rawValue, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (value.isEmpty ? nil : value, unit)
            }
        }

        let trimmed = compact.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? nil : trimmed, fallbackUnit)
    }
}

// =========================================================
// MARK: - Historical Preg Record
// =========================================================

struct HistoricalPregRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var year: Int
    var lambNumber: Int?
    var importedAt: Date

    init(
        id: UUID = UUID(),
        year: Int,
        lambNumber: Int?,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.year = year
        self.lambNumber = lambNumber
        self.importedAt = importedAt
    }
}

// =========================================================
// MARK: - Animal Record
// =========================================================

struct AnimalRecord: Identifiable, Codable, Equatable {
    
    // =====================================================
    // MARK: - Core
    // =====================================================
    
    let id: UUID
    var sessionID: UUID
    var eidRaw: String
    
    /// Weight recorded for this animal in this session.
    /// For non-weighing sessions (e.g. Traits), this will typically be 0.
    var lockedWeight: Double
    
    var recordedAt: Date
    
    /// Treatments applied to this animal when it was recorded (copied from session templates)
    var treatments: [SessionTreatment]
    
    // =====================================================
    // MARK: - Draft outcome fields (optional for backward compatibility)
    // =====================================================
    
    /// The draft position that was chosen/fired for this animal (if any).
    /// Optional so old saved records decode without issues.
    var draftResult: DraftPosition?
    
    /// Name of the rule that matched (if you want to show it in Summary later).
    var matchedRuleName: String?
    
    // =====================================================
    // MARK: - Traits (optional for backward compatibility)
    //
    // NOTE:
    // - These are per-session measurements, not permanent animal profile data.
    // - Keep optional so old saved records decode without issues.
    // =====================================================
    
    /// Fibre diameter in microns (e.g. 18.5).
    var micron: Double?
    
    /// Staple length in millimetres (e.g. 70).
    var stapleLengthMm: Int?
    
    /// Class recorded during this session (can differ from the animal profile's class).
    var traitClass: LocalDataStore.AnimalClass?
    
    /// Free text notes for trait capture (optional).
    var traitNotes: String?
    
    /// Flexible per-session user-defined traits.
    /// Keys should be stable ids such as: "custom1", "custom2".
    /// Values are strings to support numeric/text/picker use-cases.
    var customTraits: [String: String]?
    
    // =====================================================
    // MARK: - Historical preg data
    // =====================================================
    
    /// Historical preg results imported from CSV by year.
    /// Kept separate from live/current preg test data.
    var historicalPregTests: [HistoricalPregRecord]
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case eidRaw
        case lockedWeight
        case recordedAt
        case treatments
        case draftResult
        case matchedRuleName
        case micron
        case stapleLengthMm
        case traitClass
        case traitNotes
        case customTraits
        case historicalPregTests
    }
    
    // =====================================================
    // MARK: - Init
    // =====================================================
    
    init(
        id: UUID = UUID(),
        sessionID: UUID,
        eidRaw: String,
        lockedWeight: Double,
        recordedAt: Date = Date(),
        treatments: [SessionTreatment] = [],
        draftResult: DraftPosition? = nil,
        matchedRuleName: String? = nil,
        micron: Double? = nil,
        stapleLengthMm: Int? = nil,
        traitClass: LocalDataStore.AnimalClass? = nil,
        traitNotes: String? = nil,
        customTraits: [String: String]? = nil,
        historicalPregTests: [HistoricalPregRecord] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eidRaw = eidRaw
        self.lockedWeight = lockedWeight
        self.recordedAt = recordedAt
        self.treatments = treatments
        self.draftResult = draftResult
        self.matchedRuleName = matchedRuleName
        self.micron = micron
        self.stapleLengthMm = stapleLengthMm
        self.traitClass = traitClass
        self.traitNotes = traitNotes
        self.customTraits = customTraits
        self.historicalPregTests = historicalPregTests
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try c.decode(UUID.self, forKey: .id)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        eidRaw = try c.decode(String.self, forKey: .eidRaw)
        lockedWeight = try c.decode(Double.self, forKey: .lockedWeight)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
        treatments = try c.decodeIfPresent([SessionTreatment].self, forKey: .treatments) ?? []
        
        draftResult = try c.decodeIfPresent(DraftPosition.self, forKey: .draftResult)
        matchedRuleName = try c.decodeIfPresent(String.self, forKey: .matchedRuleName)
        
        micron = try c.decodeIfPresent(Double.self, forKey: .micron)
        stapleLengthMm = try c.decodeIfPresent(Int.self, forKey: .stapleLengthMm)
        traitClass = try c.decodeIfPresent(LocalDataStore.AnimalClass.self, forKey: .traitClass)
        traitNotes = try c.decodeIfPresent(String.self, forKey: .traitNotes)
        customTraits = try c.decodeIfPresent([String: String].self, forKey: .customTraits)
        
        // Backward compatibility:
        // Older saved records won't contain this field.
        historicalPregTests = try c.decodeIfPresent([HistoricalPregRecord].self, forKey: .historicalPregTests) ?? []
    }
    
    // =====================================================
    // MARK: - Historical preg helpers
    // =====================================================
    
    /// Normalized EID for matching imported historical preg data.
    /// Keeps the full number and only removes spaces/newlines.
    var normalizedEID: String {
        Self.normalizeEID(eidRaw)
    }
    
    mutating func upsertHistoricalPreg(year: Int, lambNumber: Int?) {
        if let index = historicalPregTests.firstIndex(where: { $0.year == year }) {
            historicalPregTests[index].lambNumber = lambNumber
            historicalPregTests[index].importedAt = Date()
        } else {
            historicalPregTests.append(
                HistoricalPregRecord(year: year, lambNumber: lambNumber)
            )
            historicalPregTests.sort { $0.year > $1.year }
        }
    }
    
    mutating func removeHistoricalPreg(year: Int) {
        historicalPregTests.removeAll { $0.year == year }
    }
    
    func historicalPreg(forYear year: Int) -> HistoricalPregRecord? {
        historicalPregTests.first { $0.year == year }
    }
    
    static func normalizeEID(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }
}

// =========================================================
// MARK: - Small helpers
// =========================================================

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Double {
    var cleanDoseText: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        } else if (self * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", self)
        } else {
            return String(format: "%.2f", self)
        }
    }
}
