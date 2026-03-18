import Foundation

@MainActor
enum DemoSeedData {

    // Bump this when you change seed content
    private static let seedVersion = 1
    private static let seedKey = "tepari.demoSeed.version"

    // ✅ one-shot force reseed flag (DEBUG only behavior in seedIfNeeded)
    private static let forceKey = "tepari.demoSeed.force"

    /// Call this from a debug button / settings toggle to force reseed on next launch/run.
    /// (Works on real devices without deleting the app.)
    static func requestForceReseed() {
        UserDefaults.standard.set(true, forKey: forceKey)
    }

    /// Optional helper if you want a UI to show current state.
    static func isForceReseedArmed() -> Bool {
        UserDefaults.standard.bool(forKey: forceKey)
    }

    /// ✅ FIX:
    /// - ALWAYS reseeds on the Simulator
    /// - On device, seeds if version is old OR actual store is empty
    /// - On DEBUG builds, you can arm a one-shot reseed using requestForceReseed()
    static func seedIfNeeded(
        store: LocalDataStore,
        treatmentPresets: TreatmentPresetStore,
        animalClasses: AnimalClassStore
    ) {

        let defaults = UserDefaults.standard

        // Manual one-shot reseed when explicitly requested
        #if DEBUG
        if defaults.bool(forKey: forceKey) {
            print("=== DEMO SEED FORCE RESEED ===")
            seedNow(store: store, treatmentPresets: treatmentPresets, animalClasses: animalClasses)
            defaults.set(false, forKey: forceKey)
            return
        }
        #endif

        let current = defaults.integer(forKey: seedKey)
        let hasAnyData =
            !store.farms.isEmpty ||
            !store.mobs.isEmpty ||
            !store.animals.isEmpty ||
            !store.sessions.isEmpty

        print("=== DEMO SEED CHECK ===")
        print("savedVersion:", current)
        print("hasAnyData:", hasAnyData)
        print("farmCount:", store.farms.count)
        print("mobCount:", store.mobs.count)
        print("animalCount:", store.animals.count)
        print("sessionCount:", store.sessions.count)

        guard current < seedVersion && !hasAnyData else { return }

        seedNow(store: store, treatmentPresets: treatmentPresets, animalClasses: animalClasses)
        defaults.set(seedVersion, forKey: seedKey)
    }

    // MARK: - Actual seeding (shared)

    private static func seedNow(
        store: LocalDataStore,
        treatmentPresets: TreatmentPresetStore,
        animalClasses: AnimalClassStore
    ) {
        print("=== RUNNING DEMO SEED NOW ===")

        // Clean slate demo (deterministic)
        store.resetAllData()

        // ----------------------------
        // Farms
        // ----------------------------
        let greenwood = store.addFarm(name: "Greenwood Park", pic: "SA12345")
        let mahanewo  = store.addFarm(name: "Mahanewo", pic: "SA54321")

        // ----------------------------
        // Yards (FarmSetupView stores yards in UserDefaults)
        // ----------------------------
        seedYards(farmID: greenwood.id, yards: ["Home Yards", "Paddock", "Narrawa"])
        seedYards(
            farmID: mahanewo.id,
            yards: ["Home Yards", "RockHole Yards", "Footes Yards", "Evelyn Yards", "Nortons Yards", "Micolo Yards"]
        )

        // ----------------------------
        // Mobs + Animals
        // ----------------------------
        seedMobsAndAnimals(store: store, farm: greenwood, mobNames: ["Blue", "Green", "Black"], seed: 12345)
        seedMobsAndAnimals(store: store, farm: mahanewo, mobNames: ["Yellow", "Red"], seed: 54321)

        // ----------------------------
        // Animal Classes (user-editable list store)
        // ----------------------------
        seedAnimalClasses(animalClasses)

        // ----------------------------
        // Treatment Presets
        // ----------------------------
        seedTreatmentPresets(treatmentPresets)

        // ----------------------------
        // History Sessions + Records
        // ----------------------------
        seedHistory(store: store, farms: [greenwood, mahanewo])

        print("=== DEMO SEED COMPLETE ===")
        print("farmCount:", store.farms.count)
        print("mobCount:", store.mobs.count)
        print("animalCount:", store.animals.count)
        print("sessionCount:", store.sessions.count)

        // ✅ mark seed version (harmless on simulator too)
        UserDefaults.standard.set(seedVersion, forKey: seedKey)
    }

    // MARK: - Yards (FarmSetupView UserDefaults format)

    private static func yardsKey(_ farmID: UUID) -> String {
        "farms.yards.\(farmID.uuidString)"
    }

    private static func seedYards(farmID: UUID, yards: [String]) {
        let packed = yards.joined(separator: "|")
        UserDefaults.standard.set(packed, forKey: yardsKey(farmID))
    }

    // MARK: - Mobs + Animals

    private static func seedMobsAndAnimals(
        store: LocalDataStore,
        farm: LocalDataStore.Farm,
        mobNames: [String],
        seed: UInt64
    ) {
        for (i, mobName) in mobNames.enumerated() {
            let mob = store.addMob(
                farmID: farm.id,
                name: mobName,
                colorHex: colorHex(forMobName: mobName)
            )

            var rng = SeededRNG(seed: seed &+ UInt64(i) &* 1000)

            for n in 0..<18 {
                let eid = makeEID(rng: &rng) // "982 123456789"
                let sex: LocalDataStore.Sex = (n % 10 == 0) ? .ram : .ewe
                let klass: LocalDataStore.AnimalClass = (n % 12 == 0) ? .stud : .flock

                let profile = LocalDataStore.AnimalProfile(
                    farmID: farm.id,
                    eidRaw: eid,
                    mobID: mob.id,
                    sex: sex,
                    animalClass: klass,
                    lambsPerYear: (sex == .ewe ? (n % 3) : nil),
                    fleeceWeightKg: Double((n % 7) + 3) + 0.2,
                    stapleLengthMm: Double((n % 6) * 10 + 70),
                    klass: klass.rawValue,
                    comments: (n % 8 == 0 ? "Good doer" : nil),
                    userField1: (n % 9 == 0 ? "Note \(n)" : nil),
                    userField2: nil
                )

                store.upsertAnimal(profile)
            }
        }
    }

    private static func colorHex(forMobName name: String) -> String {
        switch name.lowercased() {
        case "blue":   return "#2196F3"
        case "green":  return "#4CAF50"
        case "black":  return "#111111"
        case "yellow": return "#FFEB3B"
        case "red":    return "#F44336"
        default:       return "#9E9E9E"
        }
    }

    private static func makeEID(rng: inout SeededRNG) -> String {
        let body = rng.nextInt(in: 100_000_000...999_999_999)
        return "982 \(body)"
    }

    private struct SeededRNG {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xDEADBEEF : seed
        }

        mutating func nextUInt64() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }

        mutating func nextInt(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            let v = nextUInt64() % span
            return range.lowerBound + Int(v)
        }
    }

    // MARK: - Presets

    private static func seedTreatmentPresets(_ store: TreatmentPresetStore) {
        store.deleteAllPresetsForDemoSeed()

        store.add(.init(
            name: "5-in-1",
            doseAmount: "2",
            doseUnit: DoseUnit.mL,
            doseBasis: .perAnimal,
            dosePerKg: nil,
            defaultWithholdingDays: 14
        ))

        store.add(.init(
            name: "Drench (Triple)",
            doseAmount: "10",
            doseUnit: DoseUnit.mL,
            doseBasis: .perAnimal,
            dosePerKg: nil,
            defaultWithholdingDays: 7
        ))

        // Weight-based dose: 1 mL per 10 kg
        store.add(.init(
            name: "Backline (Lice)",
            doseAmount: "1",
            doseUnit: DoseUnit.mL,
            doseBasis: .perBodyWeight,
            dosePerKg: "10",
            defaultWithholdingDays: 21
        ))

        store.add(.init(
            name: "Vitamin B12",
            doseAmount: "1",
            doseUnit: DoseUnit.mL,
            doseBasis: .perAnimal,
            dosePerKg: nil,
            defaultWithholdingDays: nil
        ))

        store.add(.init(
            name: "Selenium",
            doseAmount: "1",
            doseUnit: DoseUnit.mL,
            doseBasis: .perAnimal,
            dosePerKg: nil,
            defaultWithholdingDays: 28
        ))
    }

    private static func seedAnimalClasses(_ store: AnimalClassStore) {
        store.deleteAllClassesForDemoSeed()

        store.add(.init(name: "Flock", defaultSex: "Ewe"))
        store.add(.init(name: "Cull", defaultSex: nil, notes: "Draft out / sale"))
        store.add(.init(name: "Stud", defaultSex: "Ram"))
        store.add(.init(name: "Stud Reserve", defaultSex: nil))
        store.add(.init(name: "Weaners", defaultSex: nil))
    }

    // MARK: - History Sessions

    private static func seedHistory(store: LocalDataStore, farms: [LocalDataStore.Farm]) {
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60

        for i in 0..<12 {
            let farm = farms[i % farms.count]
            let sessionID = UUID()
            let createdAt = now.addingTimeInterval(-day * Double(5 + i * 7))

            let name = store.uniqueSessionName("Weigh – \(farm.name)")
            _ = store.ensureSession(id: sessionID, name: name, farmID: farm.id, mobID: nil)

            store.updateSession(sessionID: sessionID) { s in
                s.createdAt = createdAt
                s.kind = .general
            }

            let cfg = LocalDataStore.SessionConfig(
                farmID: farm.id,
                farmName: farm.name,
                locationName: "Main Yards",
                scanningEnabled: true,
                scannerType: .racewell,
                weighingEnabled: true,
                weightSource: .demo,
                equipment: [.scanner, .scales],
                recordTreatments: true
            )
            store.setConfig(cfg, for: sessionID)

            if i % 3 == 0 {
                store.setSessionTreatments(
                    [SessionTreatment(product: "5-in-1", dosage: "2 mL", withholding: "14d")],
                    for: sessionID
                )
            }

            let animals = store.animals.filter { $0.farmID == farm.id }.prefix(35)
            var w: Double = 34.0 + Double(i)

            for (n, a) in animals.enumerated() {
                w += (n % 5 == 0 ? 0.8 : 0.2)
                store.addOrOverwriteRecord(
                    sessionID: sessionID,
                    eidRaw: a.eidRaw,
                    lockedWeight: round(w * 10) / 10.0,
                    treatments: []
                )
            }
        }
    }
}

// =========================================================
// MARK: - Demo-only wipe helpers for the separate preset stores
// =========================================================

private extension TreatmentPresetStore {
    @MainActor
    func deleteAllPresetsForDemoSeed() {
        let all = presets
        for p in all {
            delete(p)
        }
    }
}

private extension AnimalClassStore {
    @MainActor
    func deleteAllClassesForDemoSeed() {
        let all = classes
        for c in all {
            delete(c)
        }
    }
}
