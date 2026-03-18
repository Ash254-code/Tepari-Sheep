import Foundation
import Combine

// =========================================================
// MARK: - Dose Unit (shared)
// =========================================================

enum DoseUnit: String, CaseIterable, Codable, Hashable, Identifiable {
    case mL = "mL"
    case L  = "L"
    case mg = "mg"
    case g  = "g"
    case kg = "kg"

    var id: String { rawValue }
}

// =========================================================
// MARK: - Dose Basis (per animal vs per body weight)
// =========================================================

enum DoseBasis: String, CaseIterable, Codable, Hashable, Identifiable {
    case perAnimal
    case perBodyWeight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perAnimal: return "Per animal"
        case .perBodyWeight: return "Per body weight"
        }
    }
}

@MainActor
final class TreatmentPresetStore: ObservableObject {

    // =========================================================
    // MARK: - Model (v4)
    // =========================================================

    struct TreatmentPreset: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String

        /// Amount the user types ("2", "0.5", etc)
        var doseAmount: String?

        /// Unit picker (defaults to mL in UI, but we store optional for legacy/migration safety)
        var doseUnit: DoseUnit?

        /// perAnimal or perBodyWeight
        var doseBasis: DoseBasis?

        /// Only used when basis == perBodyWeight (e.g. "10" for "per 10 kg")
        var dosePerKg: String?

        /// Optional minimum calculated dose
        var minimumDose: String?

        /// Optional maximum calculated dose
        var maximumDose: String?

        /// Optional rounding step for calculated dose (e.g. 0.1 mL or 0.5 mL)
        var doseStep: String?

        /// If true, live dosing should only occur from stable weight
        var requiresStableWeight: Bool?

        /// Allows a preset to be hidden/disabled without deletion
        var isEnabled: Bool?

        /// Withholding days (optional)
        var defaultWithholdingDays: Int?

        // -------- Legacy decode support --------
        // v3 fields: doseAmount + doseUnit + doseBasis + dosePerKg + defaultWithholdingDays
        // v2 fields: defaultDoseValue + defaultDoseUnit + defaultWithholdingDays
        // v1 field: defaultDose "2 mL" or "1 mL/10kg"
        enum CodingKeys: String, CodingKey {
            case id, name
            case doseAmount, doseUnit, doseBasis, dosePerKg
            case minimumDose, maximumDose, doseStep, requiresStableWeight, isEnabled
            case defaultWithholdingDays

            // v2 legacy
            case defaultDoseValue, defaultDoseUnit

            // v1 legacy
            case defaultDose
        }

        init(
            id: UUID = UUID(),
            name: String,
            doseAmount: String? = nil,
            doseUnit: DoseUnit? = nil,
            doseBasis: DoseBasis? = nil,
            dosePerKg: String? = nil,
            minimumDose: String? = nil,
            maximumDose: String? = nil,
            doseStep: String? = nil,
            requiresStableWeight: Bool? = nil,
            isEnabled: Bool? = nil,
            defaultWithholdingDays: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.doseAmount = doseAmount
            self.doseUnit = doseUnit
            self.doseBasis = doseBasis
            self.dosePerKg = dosePerKg
            self.minimumDose = minimumDose
            self.maximumDose = maximumDose
            self.doseStep = doseStep
            self.requiresStableWeight = requiresStableWeight
            self.isEnabled = isEnabled
            self.defaultWithholdingDays = defaultWithholdingDays
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            defaultWithholdingDays = try c.decodeIfPresent(Int.self, forKey: .defaultWithholdingDays)

            // v4 fields
            minimumDose = try c.decodeIfPresent(String.self, forKey: .minimumDose)
            maximumDose = try c.decodeIfPresent(String.self, forKey: .maximumDose)
            doseStep = try c.decodeIfPresent(String.self, forKey: .doseStep)
            requiresStableWeight = try c.decodeIfPresent(Bool.self, forKey: .requiresStableWeight)
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled)

            // 1) Prefer v3/v4 fields
            doseAmount = try c.decodeIfPresent(String.self, forKey: .doseAmount)
            doseUnit   = try c.decodeIfPresent(DoseUnit.self, forKey: .doseUnit)
            doseBasis  = try c.decodeIfPresent(DoseBasis.self, forKey: .doseBasis)
            dosePerKg  = try c.decodeIfPresent(String.self, forKey: .dosePerKg)

            // 2) v2 fallback (split value/unit)
            if doseAmount == nil || doseUnit == nil || doseBasis == nil {
                let v2Value = try c.decodeIfPresent(String.self, forKey: .defaultDoseValue)
                let v2Unit  = try c.decodeIfPresent(DoseUnit.self, forKey: .defaultDoseUnit)

                if doseAmount == nil { doseAmount = v2Value }
                if doseUnit == nil { doseUnit = v2Unit }
                if doseBasis == nil, (v2Value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
                    doseBasis = .perAnimal
                }
            }

            // 3) v1 fallback (single string "2 mL" or "1 mL/10kg")
            if (doseAmount == nil || doseUnit == nil || doseBasis == nil),
               let legacy = try c.decodeIfPresent(String.self, forKey: .defaultDose) {

                let parsed = DoseSpec.parseLegacy(legacy, fallbackUnit: .mL)

                if doseAmount == nil {
                    let v = parsed.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                    doseAmount = v.isEmpty ? nil : v
                }
                if doseUnit == nil {
                    doseUnit = parsed.unit
                }
                if doseBasis == nil {
                    doseBasis = parsed.basis
                }
                if dosePerKg == nil {
                    dosePerKg = parsed.perKg
                }
            }

            // Sensible defaults
            let amt = (doseAmount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !amt.isEmpty {
                if doseUnit == nil { doseUnit = .mL }
                if doseBasis == nil { doseBasis = .perAnimal }

                if doseBasis == .perBodyWeight {
                    let per = (dosePerKg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if per.isEmpty { dosePerKg = "10" }
                } else {
                    dosePerKg = nil
                }
            } else {
                dosePerKg = nil
            }

            if requiresStableWeight == nil {
                requiresStableWeight = true
            }

            if isEnabled == nil {
                isEnabled = true
            }

            minimumDose = Self.cleanOptionalNumericString(minimumDose)
            maximumDose = Self.cleanOptionalNumericString(maximumDose)
            doseStep = Self.cleanOptionalNumericString(doseStep)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)

            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)

            try c.encodeIfPresent(doseAmount, forKey: .doseAmount)
            try c.encodeIfPresent(doseUnit, forKey: .doseUnit)
            try c.encodeIfPresent(doseBasis, forKey: .doseBasis)
            try c.encodeIfPresent(dosePerKg, forKey: .dosePerKg)

            try c.encodeIfPresent(minimumDose, forKey: .minimumDose)
            try c.encodeIfPresent(maximumDose, forKey: .maximumDose)
            try c.encodeIfPresent(doseStep, forKey: .doseStep)
            try c.encodeIfPresent(requiresStableWeight, forKey: .requiresStableWeight)
            try c.encodeIfPresent(isEnabled, forKey: .isEnabled)

            try c.encodeIfPresent(defaultWithholdingDays, forKey: .defaultWithholdingDays)

            // NOTE: We do NOT re-encode legacy keys.
        }

        // MARK: - Safe typed helpers

        var typedDoseAmount: Double? {
            Self.parseNumber(doseAmount)
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

        var stableWeightRequired: Bool {
            requiresStableWeight ?? true
        }

        var enabled: Bool {
            isEnabled ?? true
        }

        var canCalculateDose: Bool {
            guard let amount = typedDoseAmount, amount > 0 else { return false }

            switch doseBasis ?? .perAnimal {
            case .perAnimal:
                return true
            case .perBodyWeight:
                guard let perKg = typedDosePerKg else { return false }
                return perKg > 0
            }
        }

        /// Human-friendly display for list rows etc.
        var displayDoseString: String {
            let amt = (doseAmount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !amt.isEmpty else { return "" }

            let unit = (doseUnit ?? .mL).rawValue
            let basis = doseBasis ?? .perAnimal

            switch basis {
            case .perAnimal:
                return "\(amt) \(unit)"
            case .perBodyWeight:
                let per = (dosePerKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
                let perClean = per.isEmpty ? "10" : per
                return "\(amt) \(unit) / \(perClean) kg"
            }
        }

        /// Full display string with optional constraints
        var dosingSummary: String {
            var parts: [String] = []

            let main = displayDoseString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !main.isEmpty {
                parts.append(main)
            }

            if let min = minimumDose?.trimmedNonEmpty {
                parts.append("Min \(min) \(displayUnit)")
            }

            if let max = maximumDose?.trimmedNonEmpty {
                parts.append("Max \(max) \(displayUnit)")
            }

            if let step = doseStep?.trimmedNonEmpty {
                parts.append("Step \(step) \(displayUnit)")
            }

            if stableWeightRequired {
                parts.append("Stable wt")
            }

            return parts.joined(separator: " · ")
        }

        var displayUnit: String {
            (doseUnit ?? .mL).rawValue
        }

        // MARK: - Dose calculation

        /// Returns calculated dose for a live weight, or nil if this preset does not have enough info.
        func calculatedDose(forWeightKg weightKg: Double) -> Double? {
            guard enabled else { return nil }
            guard weightKg > 0 else { return nil }
            guard let amount = typedDoseAmount, amount > 0 else { return nil }

            var dose: Double

            switch doseBasis ?? .perAnimal {
            case .perAnimal:
                dose = amount

            case .perBodyWeight:
                guard let perKg = typedDosePerKg, perKg > 0 else { return nil }
                dose = (weightKg / perKg) * amount
            }

            if let min = typedMinimumDose {
                dose = max(dose, min)
            }

            if let max = typedMaximumDose {
                dose = min(dose, max)
            }

            if let step = typedDoseStep, step > 0 {
                dose = (dose / step).rounded() * step
            }

            return dose
        }

        func calculatedDoseString(forWeightKg weightKg: Double) -> String? {
            guard let dose = calculatedDose(forWeightKg: weightKg) else { return nil }
            return "\(dose.cleanDoseText) \(displayUnit)"
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

        private static func cleanOptionalNumericString(_ value: String?) -> String? {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !v.isEmpty else {
                return nil
            }
            return v
        }
    }

    // =========================================================
    // MARK: - Dose Spec (parsing legacy strings)
    // =========================================================

    struct DoseSpec: Hashable, Codable {
        var amount: String
        var unit: DoseUnit
        var basis: DoseBasis
        var perKg: String? // only when basis == perBodyWeight

        /// Parses legacy strings like:
        /// "2 mL", "2mL", "10mg", "0.5 g", "1 mL/10kg", "1mL/10 kg"
        static func parseLegacy(_ s: String, fallbackUnit: DoseUnit) -> DoseSpec {
            let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                return DoseSpec(amount: "", unit: fallbackUnit, basis: .perAnimal, perKg: nil)
            }

            let compact = raw.replacingOccurrences(of: " ", with: "")

            if compact.contains("/") {
                let parts = compact.split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let left = parts[0]
                    let right = parts[1]

                    let rightLower = right.lowercased()
                    var perKgValue: String? = nil
                    if rightLower.hasSuffix("kg") {
                        let n = String(right.dropLast(2))
                        let cleaned = n.trimmingCharacters(in: .whitespacesAndNewlines)
                        perKgValue = cleaned.isEmpty ? "1" : cleaned
                    }

                    let (amt, unit) = parseAmountAndUnit(left, fallbackUnit: fallbackUnit)
                    return DoseSpec(amount: amt, unit: unit, basis: .perBodyWeight, perKg: perKgValue ?? "10")
                }

                return DoseSpec(amount: raw, unit: fallbackUnit, basis: .perAnimal, perKg: nil)
            }

            let (amt, unit) = parseAmountAndUnit(compact, fallbackUnit: fallbackUnit)
            return DoseSpec(amount: amt, unit: unit, basis: .perAnimal, perKg: nil)
        }

        private static func parseAmountAndUnit(_ compact: String, fallbackUnit: DoseUnit) -> (String, DoseUnit) {
            for u in DoseUnit.allCases {
                if compact.hasSuffix(u.rawValue) {
                    let v = compact.replacingOccurrences(of: u.rawValue, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (v, u)
                }
            }

            return (compact.trimmingCharacters(in: .whitespacesAndNewlines), fallbackUnit)
        }
    }

    // =========================================================
    // MARK: - Legacy Models (for migration)
    // =========================================================

    private struct TreatmentPresetV2: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String
        var defaultDoseValue: String?
        var defaultDoseUnit: DoseUnit?
        var defaultWithholdingDays: Int?
    }

    private struct TreatmentPresetV1: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String
        var defaultDose: String?
        var defaultWithholdingDays: Int?
    }

    // =========================================================
    // MARK: - State
    // =========================================================

    @Published private(set) var presets: [TreatmentPreset] = []

    // =========================================================
    // MARK: - Persistence
    // =========================================================

    private let defaults: UserDefaults
    private let keyV4 = "tepari.treatmentPresets.v4"
    private let keyV3 = "tepari.treatmentPresets.v3"
    private let keyV2 = "tepari.treatmentPresets.v2"
    private let keyV1 = "tepari.treatmentPresets.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        load()
    }

    private func load() {
        // 1) Try v4 first
        if let data = defaults.data(forKey: keyV4) {
            do {
                presets = try JSONDecoder().decode([TreatmentPreset].self, from: data)
                sortPresets()
                return
            } catch {
                // fall through
            }
        }

        // 2) Try v3 and migrate -> v4
        if let data = defaults.data(forKey: keyV3) {
            do {
                presets = try JSONDecoder().decode([TreatmentPreset].self, from: data)
                sortPresets()
                save()
                return
            } catch {
                // fall through to v2/v1 migration
            }
        }

        // 3) Try v2 and migrate -> v4
        if let data = defaults.data(forKey: keyV2) {
            do {
                let old = try JSONDecoder().decode([TreatmentPresetV2].self, from: data)
                presets = old.map { v2 in
                    let amt = (v2.defaultDoseValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return TreatmentPreset(
                        id: v2.id,
                        name: v2.name,
                        doseAmount: amt.isEmpty ? nil : amt,
                        doseUnit: amt.isEmpty ? nil : (v2.defaultDoseUnit ?? .mL),
                        doseBasis: amt.isEmpty ? nil : .perAnimal,
                        dosePerKg: nil,
                        minimumDose: nil,
                        maximumDose: nil,
                        doseStep: nil,
                        requiresStableWeight: true,
                        isEnabled: true,
                        defaultWithholdingDays: v2.defaultWithholdingDays
                    )
                }
                sortPresets()
                save()
                return
            } catch {
                // fall through to v1 migration
            }
        }

        // 4) Try v1 and migrate -> v4
        guard let data = defaults.data(forKey: keyV1) else {
            presets = []
            return
        }

        do {
            let old = try JSONDecoder().decode([TreatmentPresetV1].self, from: data)
            presets = old.map { v1 in
                let parsed = DoseSpec.parseLegacy(v1.defaultDose ?? "", fallbackUnit: .mL)
                let amt = parsed.amount.trimmingCharacters(in: .whitespacesAndNewlines)

                return TreatmentPreset(
                    id: v1.id,
                    name: v1.name,
                    doseAmount: amt.isEmpty ? nil : amt,
                    doseUnit: amt.isEmpty ? nil : parsed.unit,
                    doseBasis: amt.isEmpty ? nil : parsed.basis,
                    dosePerKg: (parsed.basis == .perBodyWeight) ? parsed.perKg : nil,
                    minimumDose: nil,
                    maximumDose: nil,
                    doseStep: nil,
                    requiresStableWeight: true,
                    isEnabled: true,
                    defaultWithholdingDays: v1.defaultWithholdingDays
                )
            }

            sortPresets()
            save()
        } catch {
            presets = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(presets)
            defaults.set(data, forKey: keyV4)
        } catch {
            // no-op
        }
    }

    // =========================================================
    // MARK: - CRUD
    // =========================================================

    func add(_ preset: TreatmentPreset) {
        presets.append(preset)
        sortPresets()
        save()
    }

    func update(_ preset: TreatmentPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        sortPresets()
        save()
    }

    func delete(_ preset: TreatmentPreset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func setEnabled(_ isEnabled: Bool, for preset: TreatmentPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].isEnabled = isEnabled
        sortPresets()
        save()
    }

    func toggleEnabled(for preset: TreatmentPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].isEnabled = !(presets[idx].isEnabled ?? true)
        sortPresets()
        save()
    }

    func preset(id: UUID) -> TreatmentPreset? {
        presets.first { $0.id == id }
    }

    var enabledPresets: [TreatmentPreset] {
        presets.filter { $0.enabled }
    }

    var disabledPresets: [TreatmentPreset] {
        presets.filter { !$0.enabled }
    }

    private func sortPresets() {
        presets.sort {
            if $0.enabled != $1.enabled {
                return $0.enabled && !$1.enabled
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// =========================================================
// MARK: - Small helpers
// =========================================================

private extension String {
    var trimmedNonEmpty: String? {
        let v = trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
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
