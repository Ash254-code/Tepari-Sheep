import Foundation
import SwiftData

// =====================================================
// MARK: - FARM
// =====================================================

@Model
final class Farm {
    @Attribute(.unique) var id: UUID
    var name: String
    var pic: String
    var createdAt: Date

    // Optional: which farm shows first / default selection
    var isActive: Bool

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Mob.farm)
    var mobs: [Mob] = []

    @Relationship(deleteRule: .cascade, inverse: \Animal.farm)
    var animals: [Animal] = []

    init(
        name: String,
        pic: String,
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.pic = pic
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// =====================================================
// MARK: - MOB
// =====================================================

@Model
final class Mob {
    @Attribute(.unique) var id: UUID

    var name: String

    /// Store colour as HEX so it’s stable across platforms.
    /// Example: "#FF9900"
    var colorHex: String

    var createdAt: Date

    // Relationships
    var farm: Farm?

    @Relationship(deleteRule: .nullify, inverse: \Animal.mob)
    var animals: [Animal] = []

    init(
        name: String,
        colorHex: String = "#2ECC71",
        farm: Farm? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.farm = farm
        self.createdAt = createdAt
    }
}

// =====================================================
// MARK: - ANIMAL (EID + traits)
// =====================================================

@Model
final class Animal {
    @Attribute(.unique) var id: UUID

    /// Cleaned, digits-only EID (store the canonical form).
    /// IMPORTANT: Use your existing EIDValidator.cleanedRaw() before saving.
    @Attribute(.unique) var eid: String

    var createdAt: Date
    var updatedAt: Date

    // Relationships
    var farm: Farm?
    var mob: Mob?

    // -------------------------
    // Core traits (drafting can use these)
    // -------------------------

    /// 1 or 2 (but keep it open in case you want 0/3 etc)
    var lambsTypicalPerYear: Int?

    /// kg
    var fleeceWeightKg: Double?

    /// mm
    var stapleLengthMm: Double?

    /// Classing / micron class / internal label
    var classLabel: String?

    var comments: String?

    // -------------------------
    // Lambing history (per year)
    // -------------------------

    @Relationship(deleteRule: .cascade, inverse: \LambingRecord.animal)
    var lambingRecords: [LambingRecord] = []

    // -------------------------
    // User-defined fields (key/value)
    // Add as many later without changing schema.
    // -------------------------

    @Relationship(deleteRule: .cascade, inverse: \UserFieldValue.animal)
    var userFields: [UserFieldValue] = []

    init(
        eid: String,
        farm: Farm? = nil,
        mob: Mob? = nil
    ) {
        self.id = UUID()
        self.eid = eid
        self.farm = farm
        self.mob = mob
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func touchUpdated() {
        updatedAt = Date()
    }
}

// =====================================================
// MARK: - Lambing record (year -> count)
// =====================================================

@Model
final class LambingRecord {
    @Attribute(.unique) var id: UUID

    /// e.g. 2026
    var year: Int

    /// 0, 1, 2, etc
    var lambCount: Int

    var createdAt: Date

    // Relationship
    var animal: Animal?

    init(year: Int, lambCount: Int, animal: Animal? = nil) {
        self.id = UUID()
        self.year = year
        self.lambCount = lambCount
        self.animal = animal
        self.createdAt = Date()
    }
}

// =====================================================
// MARK: - User-defined fields (key/value)
// =====================================================

@Model
final class UserFieldValue {
    @Attribute(.unique) var id: UUID

    /// e.g. "Draft Score", "Dentition", "Breed Notes"
    var key: String

    /// Store as String; you can interpret as number/bool later if you want.
    var value: String

    var createdAt: Date

    // Relationship
    var animal: Animal?

    init(key: String, value: String, animal: Animal? = nil) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.animal = animal
        self.createdAt = Date()
    }
}
