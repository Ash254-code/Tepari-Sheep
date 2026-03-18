import Foundation

/// Represents a treatment product with a dosing rule.
/// Example: 2 mL per 10 kg body weight.
struct Treatment: Identifiable, Codable, Hashable {

    // MARK: - Identity

    var id: UUID

    // MARK: - Basic info

    /// Display name of the treatment (e.g. "Cydectin")
    var name: String

    /// Dose unit (e.g. "mL")
    var unit: String

    // MARK: - Dose rule

    /// Amount of product per dose weight
    /// Example: 2
    var doseAmount: Double

    /// Weight that doseAmount applies to
    /// Example: 10 kg
    var doseWeightKg: Double

    // MARK: - Optional limits

    /// Optional minimum allowed dose
    var minimumDose: Double?

    /// Optional maximum allowed dose
    var maximumDose: Double?

    /// Optional rounding step (example: 0.1 mL)
    var doseStep: Double?

    // MARK: - Behaviour flags

    /// Require stable weight before calculating
    var requiresStableWeight: Bool

    /// Allows disabling a treatment without deleting it
    var isEnabled: Bool

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        unit: String = "mL",
        doseAmount: Double,
        doseWeightKg: Double,
        minimumDose: Double? = nil,
        maximumDose: Double? = nil,
        doseStep: Double? = nil,
        requiresStableWeight: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.doseAmount = doseAmount
        self.doseWeightKg = doseWeightKg
        self.minimumDose = minimumDose
        self.maximumDose = maximumDose
        self.doseStep = doseStep
        self.requiresStableWeight = requiresStableWeight
        self.isEnabled = isEnabled
    }
}

// MARK: - Dose Calculation

extension Treatment {

    /// Calculates dose for a given animal weight.
    func dose(forWeightKg weightKg: Double) -> Double {

        guard weightKg > 0 else { return 0 }
        guard doseWeightKg > 0 else { return 0 }

        // Base calculation
        var dose = (weightKg / doseWeightKg) * doseAmount

        // Apply min limit
        if let min = minimumDose {
            dose = max(dose, min)
        }

        // Apply max limit
        if let max = maximumDose {
            dose = min(dose, max)
        }

        // Apply rounding step
        if let step = doseStep, step > 0 {
            dose = (dose / step).rounded() * step
        }

        return dose
    }
}

// MARK: - Display Helpers

extension Treatment {

    /// Human readable rate description.
    /// Example: "2 mL per 10 kg"
    var rateDescription: String {
        "\(doseAmount.clean) \(unit) per \(doseWeightKg.clean) kg"
    }
}

// MARK: - Formatting Helpers

private extension Double {

    /// Removes trailing .0 for cleaner display
    var clean: String {
        if self.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        } else {
            return String(format: "%.2f", self)
        }
    }
}
