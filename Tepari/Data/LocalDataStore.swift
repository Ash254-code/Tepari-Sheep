// LocalDataStore.swift
import Foundation
import Combine
import SwiftUI

struct LocalDataStoreSnapshot: Codable {
    var schemaVersion: Int

    // Core
    var sessions: [Session]
    var records: [AnimalRecord]

    // Wizard/session config + runtime state
    var sessionConfigs: [UUID: LocalDataStore.SessionConfig]
    var sessionTreatments: [UUID: [SessionTreatment]]
    var sessionQuickStartTemplates: [LocalDataStore.SessionQuickStartTemplate]?

    // Per-session selections / defaults / overwrites
    var sessionFarmID: [UUID: UUID]
    var sessionMobID: [UUID: UUID]

    var sessionDefaultSex: [UUID: LocalDataStore.Sex]
    var sessionDefaultClass: [UUID: LocalDataStore.AnimalClass]
    var sessionDefaultMobName: [UUID: String]

    // ✅ NEW defaults (optional so older files decode safely)
    var sessionDefaultBreed: [UUID: String]?
    var sessionDefaultBirthYear: [UUID: Int]?
    var sessionDefaultBirthMonth: [UUID: Int]?
    var sessionDefaultStatus: [UUID: AnimalStatus]?

    var sessionOverwriteSex: [UUID: Bool]
    var sessionOverwriteClass: [UUID: Bool]
    var sessionOverwriteMob: [UUID: Bool]

    // Catalog
    var farms: [LocalDataStore.Farm]
    var mobs: [LocalDataStore.Mob]
    var animals: [LocalDataStore.AnimalProfile]

    // Lifetime animal history (v1 files may not include this, so keep optional)
    var animalEvents: [AnimalEvent]? = nil

    // Programmed tags + sold archive
    var programmedTags: [UUID: [String: LocalDataStore.ProgrammedTagAssignment]]
    var soldArchive: [LocalDataStore.SoldAnimal]

    // Per-session draft setup
    var sessionDraftSetup: [UUID: SessionDraftSetup]?
    
    
    init(
        schemaVersion: Int = 1,
        sessions: [Session] = [],
        records: [AnimalRecord] = [],
        sessionConfigs: [UUID: LocalDataStore.SessionConfig] = [:],
        sessionTreatments: [UUID: [SessionTreatment]] = [:],
        sessionQuickStartTemplates: [LocalDataStore.SessionQuickStartTemplate]? = nil,
        sessionFarmID: [UUID: UUID] = [:],
        sessionMobID: [UUID: UUID] = [:],
        sessionDefaultSex: [UUID: LocalDataStore.Sex] = [:],
        sessionDefaultClass: [UUID: LocalDataStore.AnimalClass] = [:],
        sessionDefaultMobName: [UUID: String] = [:],

        // ✅ NEW defaults
        sessionDefaultBreed: [UUID: String]? = nil,
        sessionDefaultBirthYear: [UUID: Int]? = nil,
        sessionDefaultBirthMonth: [UUID: Int]? = nil,
        sessionDefaultStatus: [UUID: AnimalStatus]? = nil,

        sessionOverwriteSex: [UUID: Bool] = [:],
        sessionOverwriteClass: [UUID: Bool] = [:],
        sessionOverwriteMob: [UUID: Bool] = [:],
        farms: [LocalDataStore.Farm] = [],
        mobs: [LocalDataStore.Mob] = [],
        animals: [LocalDataStore.AnimalProfile] = [],
        animalEvents: [AnimalEvent]? = nil,
        programmedTags: [UUID: [String: LocalDataStore.ProgrammedTagAssignment]] = [:],
        soldArchive: [LocalDataStore.SoldAnimal] = [],
        sessionDraftSetup: [UUID: SessionDraftSetup]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
        self.records = records

        self.sessionConfigs = sessionConfigs
        self.sessionTreatments = sessionTreatments
        self.sessionQuickStartTemplates = sessionQuickStartTemplates

        self.sessionFarmID = sessionFarmID
        self.sessionMobID = sessionMobID

        self.sessionDefaultSex = sessionDefaultSex
        self.sessionDefaultClass = sessionDefaultClass
        self.sessionDefaultMobName = sessionDefaultMobName

        // ✅ NEW defaults
        self.sessionDefaultBreed = sessionDefaultBreed
        self.sessionDefaultBirthYear = sessionDefaultBirthYear
        self.sessionDefaultBirthMonth = sessionDefaultBirthMonth
        self.sessionDefaultStatus = sessionDefaultStatus

        self.sessionOverwriteSex = sessionOverwriteSex
        self.sessionOverwriteClass = sessionOverwriteClass
        self.sessionOverwriteMob = sessionOverwriteMob

        self.farms = farms
        self.mobs = mobs
        self.animals = animals

        self.animalEvents = animalEvents

        self.programmedTags = programmedTags
        self.soldArchive = soldArchive
        self.sessionDraftSetup = sessionDraftSetup
    }
}

@MainActor
final class LocalDataStore: ObservableObject {

    // =========================================================
    // MARK: - CSV Import Helpers
    // =========================================================

    enum DuplicateImportAction {
        case skip
        case replace
    }

    struct AnimalCSVImportResult {
        var totalAnimals: Int
        var animalsImported: Int
        var animalsSkipped: Int
        var duplicatesSkipped: Int
        var animalsReplaced: Int
    }

    // =========================================================
    // MARK: - IMPORT FIX (CORE CHANGE)
    // =========================================================

    private func applyLambingFromCSVRow(
        profile: AnimalProfile,
        lambsByYear: [Int: Int]
    ) {
        guard !lambsByYear.isEmpty else { return }

        for (year, lambs) in lambsByYear {
            addLambingEvent(
                farmID: profile.farmID,
                eidRaw: profile.eidRaw,
                year: year,
                born: lambs,
                weaned: nil,
                notes: "CSV Import"
            )
        }

        if let latestYear = lambsByYear.keys.max(),
           let latestValue = lambsByYear[latestYear],
           let idx = animals.firstIndex(where: {
               $0.farmID == profile.farmID &&
               $0.eidRaw == profile.eidRaw
           }) {
            animals[idx].lambsPerYear = latestValue
            animals[idx].updatedAt = Date()
        }
    }
    func totalLambsCached(farmID: UUID, eidRaw: String) -> Int {
        totalLambsByAnimalIndex[animalIndexKey(farmID: farmID, eidRaw: eidRaw)] ?? 0
    }
    func totalLambsForAnimal(farmID: UUID?, eidRaw: String) -> Int {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return 0 }

        if let farmID {
            return totalLambsByAnimalIndex[animalIndexKey(farmID: farmID, eidRaw: eid)] ?? 0
        }

        var total = 0
        for animal in animals {
            let cleaned = EIDValidator.cleanedRaw(animal.eidRaw)
            guard cleaned == eid else { continue }
            total += totalLambsByAnimalIndex[animalIndexKey(farmID: animal.farmID, eidRaw: eid)] ?? 0
        }
        return total
    }

    // =========================================================
    // MARK: - CSV Import (UPDATED CORE LOGIC)
    // =========================================================

    @discardableResult
    func importAnimalsCSV(
        csvText: String,
        duplicateAction: DuplicateImportAction = .skip,
        progress: ((Int, Int) -> Void)? = nil
    ) -> AnimalCSVImportResult {

        let parsed = CSVAnimalImporter.parseAnimalsCSV(csvText: csvText)
        let total = parsed.rows.count

        var imported = 0
        var skipped = parsed.skippedRows
        var duplicatesSkipped = 0
        var replaced = 0

        for (index, row) in parsed.rows.enumerated() {

            if index % 20 == 0 || index == total - 1 {
                progress?(index + 1, total)
            }

            guard let farmID = resolveFarmIDForImport(
                pic: row.farmPIC,
                farmName: row.farmName
            ) else {
                skipped += 1
                continue
            }

            let existing = animalProfile(farmID: farmID, eidRaw: row.eid)

            if existing != nil && duplicateAction == .skip {
                duplicatesSkipped += 1
                continue
            }

            let mobIDFromCSV: UUID? = {
                guard let mobName = row.mobName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !mobName.isEmpty else {
                    return existing?.mobID
                }

                if let existingMob = mobs.first(where: {
                    $0.farmID == farmID &&
                    $0.name.caseInsensitiveCompare(mobName) == .orderedSame
                }) {
                    return existingMob.id
                }

                return addMob(farmID: farmID, name: mobName, colorHex: defaultImportedMobColorHex).id
            }()

            let profile = AnimalProfile(
                id: existing?.id ?? UUID(),
                farmID: farmID,
                eidRaw: row.eid,
                mobID: mobIDFromCSV ?? existing?.mobID,
                sex: row.sex ?? existing?.sex,
                animalClass: row.animalClass ?? existing?.animalClass,
                breed: existing?.breed,
                birthYear: existing?.birthYear,
                birthMonth: existing?.birthMonth,
                status: row.status ?? existing?.status,
                lambsPerYear: existing?.lambsPerYear,
                fleeceWeightKg: row.fleeceWeightKg ?? existing?.fleeceWeightKg,
                stapleLengthMm: row.stapleLengthMm ?? existing?.stapleLengthMm,
                klass: row.klass ?? existing?.klass,
                comments: row.comments ?? existing?.comments,
                userField1: row.userField1 ?? existing?.userField1,
                userField2: row.userField2 ?? existing?.userField2
            )

            upsertAnimal(profile)

            applyLambingFromCSVRow(
                profile: profile,
                lambsByYear: row.lambsByYear
            )

            if existing != nil {
                replaced += 1
            } else {
                imported += 1
            }
        }

        rebuildIndexes()
        scheduleSave()

        progress?(total, total)

        return AnimalCSVImportResult(
            totalAnimals: total,
            animalsImported: imported,
            animalsSkipped: skipped,
            duplicatesSkipped: duplicatesSkipped,
            animalsReplaced: replaced
        )
    }
    

    // =========================================================
    // MARK: - Persistence (core data snapshot)
    // =========================================================

    // Removed private nested Snapshot struct as per instructions.

    // ✅ Keep the schema version the same; we used OPTIONAL new keys for backwards-compat.
    private let snapshotSchemaVersion = 1
    private var saveTask: Task<Void, Never>? = nil
    private var isLoadingSnapshot: Bool = false

    // ✅ Batch/deferred save support
    private var saveSuspensionDepth: Int = 0
    private var saveNeededWhileSuspended: Bool = false

    func scheduleSave() {
        guard !isLoadingSnapshot else { return }

        guard saveSuspensionDepth == 0 else {
            saveNeededWhileSuspended = true
            return
        }

        saveTask?.cancel()

        let snapshot = buildSnapshot()
        let eventsSnapshot = animalEvents

        let snapshotURLValue: URL
        let animalEventsURLValue: URL

        do {
            snapshotURLValue = try snapshotURL()
            animalEventsURLValue = try animalEventsURL()
        } catch {
            return
        }

        saveTask = Task(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s debounce

                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                enc.dateEncodingStrategy = .iso8601

                let data = try enc.encode(snapshot)
                try data.write(to: snapshotURLValue, options: [.atomic])

                let eventsData = try enc.encode(eventsSnapshot)
                try eventsData.write(to: animalEventsURLValue, options: [.atomic])

            } catch {
                // ignore cancellations / write failures
            }
        }
    }

    private func withDeferredSave<T>(_ work: () throws -> T) rethrows -> T {
        saveSuspensionDepth += 1
        defer {
            saveSuspensionDepth -= 1
            if saveSuspensionDepth == 0, saveNeededWhileSuspended {
                saveNeededWhileSuspended = false
                scheduleSave()
            }
        }
        return try work()
    }

    private func appSupportDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Tepari", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func snapshotURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("localDataStore_v\(snapshotSchemaVersion).json")
    }

    private func animalEventsURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("animalEvents_v1.json")
    }

    private func buildSnapshot() -> LocalDataStoreSnapshot {
        LocalDataStoreSnapshot(
            schemaVersion: snapshotSchemaVersion,
            sessions: sessions,
            records: records,
            sessionConfigs: sessionConfigs,
            sessionTreatments: sessionTreatments,
            sessionQuickStartTemplates: sessionQuickStartTemplates,
            sessionFarmID: sessionFarmID,
            sessionMobID: sessionMobID,
            sessionDefaultSex: sessionDefaultSex,
            sessionDefaultClass: sessionDefaultClass,
            sessionDefaultMobName: sessionDefaultMobName,

            // ✅ NEW defaults
            sessionDefaultBreed: sessionDefaultBreed,
            sessionDefaultBirthYear: sessionDefaultBirthYear,
            sessionDefaultBirthMonth: sessionDefaultBirthMonth,
            sessionDefaultStatus: sessionDefaultStatus,

            sessionOverwriteSex: sessionOverwriteSex,
            sessionOverwriteClass: sessionOverwriteClass,
            sessionOverwriteMob: sessionOverwriteMob,
            farms: farms,
            mobs: mobs,
            animals: animals,
            animalEvents: nil,
            programmedTags: programmedTags,
            soldArchive: soldArchive,
            sessionDraftSetup: sessionDraftSetup
        )
    }

    private func applySnapshot(_ snap: LocalDataStoreSnapshot) {
        guard snap.schemaVersion == snapshotSchemaVersion else { return }

        sessions = snap.sessions
        records = snap.records

        sessionConfigs = snap.sessionConfigs
        sessionTreatments = snap.sessionTreatments
        sessionQuickStartTemplates = snap.sessionQuickStartTemplates ?? []

        sessionFarmID = snap.sessionFarmID
        sessionMobID = snap.sessionMobID

        sessionDefaultSex = snap.sessionDefaultSex
        sessionDefaultClass = snap.sessionDefaultClass
        sessionDefaultMobName = snap.sessionDefaultMobName

        // ✅ NEW defaults (older files may omit)
        sessionDefaultBreed = snap.sessionDefaultBreed ?? [:]
        sessionDefaultBirthYear = snap.sessionDefaultBirthYear ?? [:]
        sessionDefaultBirthMonth = snap.sessionDefaultBirthMonth ?? [:]
        sessionDefaultStatus = snap.sessionDefaultStatus ?? [:]

        sessionOverwriteSex = snap.sessionOverwriteSex
        sessionOverwriteClass = snap.sessionOverwriteClass
        sessionOverwriteMob = snap.sessionOverwriteMob

        farms = snap.farms
        mobs = snap.mobs
        animals = snap.animals

        programmedTags = snap.programmedTags
        soldArchive = snap.soldArchive
        sessionDraftSetup = snap.sessionDraftSetup ?? [:]

        rebuildIndexes()
    }

    private func loadSnapshotFromDisk() {
        isLoadingSnapshot = true
        defer { isLoadingSnapshot = false }

        do {
            let url = try snapshotURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }

            let data = try Data(contentsOf: url)

            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            let snap = try dec.decode(LocalDataStoreSnapshot.self, from: data)
            applySnapshot(snap)
        } catch {
            do {
                let url = try snapshotURL()
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let bad = url.deletingLastPathComponent().appendingPathComponent("localDataStore_corrupt_\(stamp).json")
                    try? fm.moveItem(at: url, to: bad)
                }
            } catch { }
        }
    }

    private func loadAnimalEventsFromDisk() {
        do {
            let url = try animalEventsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                animalEvents = []
                rebuildIndexes()
                return
            }

            let data = try Data(contentsOf: url)

            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            animalEvents = try dec.decode([AnimalEvent].self, from: data)
            rebuildIndexes()
        } catch {
            animalEvents = []
            rebuildIndexes()
        }
    }

    // =========================================================
    // MARK: - Existing session data
    // =========================================================

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var records: [AnimalRecord] = []

    // =========================================================
    // MARK: - Preg Draft Record Write
    // =========================================================

    @MainActor
    func savePregDraft(
        sessionID: UUID,
        eidRaw: String,
        fetusCount: Int,
        draftPosition: DraftPosition
    ) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return }

        withDeferredSave {
            if let index = records.firstIndex(where: {
                $0.sessionID == sessionID && $0.eidRaw == eid
            }) {
                var rec = records[index]
                var traits = rec.customTraits ?? [:]
                traits["pregFetusCount"] = String(fetusCount)
                rec.customTraits = traits
                rec.draftResult = draftPosition
                records[index] = rec
            } else {
                var traits: [String: String] = [:]
                traits["pregFetusCount"] = String(fetusCount)

                let newRecord = AnimalRecord(
                    sessionID: sessionID,
                    eidRaw: eid,
                    lockedWeight: 0,
                    treatments: [],
                    draftResult: draftPosition,
                    customTraits: traits
                )
                records.insert(newRecord, at: 0)
            }

            if let farmID = resolvedFarmIDForEvent(sessionID: sessionID) {
                let status: String = (fetusCount == 0) ? "Empty" : "Pregnant"

                addPregnancyEvent(
                    farmID: farmID,
                    eidRaw: eid,
                    status: status,
                    fetusCount: fetusCount,
                    method: "Scan",
                    notes: nil,
                    at: Date()
                )

                if var p = animalProfile(farmID: farmID, eidRaw: eid) {
                    p.lambsPerYear = fetusCount
                    upsertAnimal(p)
                }

                let year = Calendar.current.component(.year, from: Date())
                addLambingEvent(
                    farmID: farmID,
                    eidRaw: eid,
                    year: year,
                    born: fetusCount,
                    weaned: nil,
                    notes: "Preg test"
                )
            }

            rebuildIndexes()
            scheduleSave()
        }
    }

    // =========================================================
    // MARK: - Lifetime animal history
    // =========================================================

    @Published private(set) var animalEvents: [AnimalEvent] = []

    // =========================================================
    // MARK: - Lifetime event helpers
    // =========================================================

    @discardableResult
    func appendAnimalEvent(_ event: AnimalEvent, dedupe: Bool = true) -> AnimalEvent {
        let eid = EIDValidator.cleanedRaw(event.eidRaw)
        guard !eid.isEmpty, eid != "—" else { return event }

        if dedupe {
            if let idx = animalEvents.firstIndex(where: { e in
                e.farmID == event.farmID &&
                e.eidRaw == eid &&
                e.kind == event.kind &&
                e.date == event.date
            }) {
                animalEvents[idx] = event
                rebuildIndexes()
                scheduleSave()
                return event
            }
        }

        animalEvents.insert(event, at: 0)
        rebuildIndexes()
        scheduleSave()
        return event
    }

    @discardableResult
    func addWeightEvent(
        farmID: UUID,
        eidRaw: String,
        weightKg: Double,
        at date: Date = Date()
    ) -> AnimalEvent {
        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .weight,
            date: date,
            number1: weightKg
        )
        return appendAnimalEvent(e, dedupe: true)
    }

    @discardableResult
    func addPregnancyEvent(
        farmID: UUID,
        eidRaw: String,
        status: String,
        fetusCount: Int? = nil,
        method: String? = nil,
        notes: String? = nil,
        at date: Date = Date()
    ) -> AnimalEvent {
        var json: [String: String] = [:]
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { json["notes"] = notes }
        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .pregnancy,
            date: date,
            int1: fetusCount,
            text1: status,
            text2: method,
            json: json.isEmpty ? nil : json
        )
        return appendAnimalEvent(e, dedupe: true)
    }

    @discardableResult
    func addLambingEvent(
        farmID: UUID,
        eidRaw: String,
        year: Int,
        born: Int? = nil,
        weaned: Int? = nil,
        notes: String? = nil
    ) -> AnimalEvent {
        var json: [String: String] = [:]
        if let born { json["born"] = String(born) }
        if let weaned { json["weaned"] = String(weaned) }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { json["notes"] = notes }

        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        let anchor = Calendar.current.date(from: comps) ?? Date()

        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .lambing,
            date: anchor,
            int1: year,
            json: json.isEmpty ? nil : json
        )
        return appendAnimalEvent(e, dedupe: true)
    }

    private func resolvedFarmIDForEvent(sessionID: UUID) -> UUID? {
        if let cfgFarm = config(for: sessionID)?.farmID { return cfgFarm }
        if let legacy = sessionFarmID[sessionID] { return legacy }
        if let s = sessions.first(where: { $0.id == sessionID })?.farmID { return s }
        return nil
    }

    @discardableResult
    func addLastSeenEvent(
        farmID: UUID,
        eidRaw: String,
        at date: Date = Date(),
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String]? = nil
        if let sessionID {
            json = ["sessionID": sessionID.uuidString]
        }

        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .lastSeen,
            date: date,
            json: json
        )
        return appendAnimalEvent(e, dedupe: true)
    }

    @discardableResult
    func addTreatmentEvent(
        farmID: UUID,
        eidRaw: String,
        product: String,
        dosage: String? = nil,
        withholding: String? = nil,
        notes: String? = nil,
        at date: Date = Date(),
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String] = [:]
        if let withholding, !withholding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            json["withholding"] = withholding
        }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            json["notes"] = notes
        }
        if let sessionID {
            json["sessionID"] = sessionID.uuidString
        }

        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .treatment,
            date: date,
            text1: product,
            text2: dosage,
            json: json.isEmpty ? nil : json
        )
        return appendAnimalEvent(e, dedupe: false)
    }

    @discardableResult
    func importHistoricalFleeceWeightCSV(
        csvText: String,
        farmID: UUID? = nil,
        duplicateAction: DuplicateImportAction = .skip
    ) -> HistoricalImportResult {
        withDeferredSave {
            let parsed = CSVAnimalImporter.parseHistoricalFleeceWeightCSV(csvText: csvText)

            guard !parsed.rows.isEmpty else {
                return HistoricalImportResult(
                    imported: 0,
                    unmatched: 0,
                    skipped: parsed.skippedRows,
                    duplicatesSkipped: 0,
                    replaced: 0
                )
            }

            var imported = 0
            var unmatched = 0
            var duplicatesSkipped = 0
            var replaced = 0

            for row in parsed.rows {
                let eid = normalizedImportEID(row.eid)
                guard !eid.isEmpty, eid != "—" else { continue }

                let matchedProfile: AnimalProfile? = {
                    if let farmID {
                        return animalProfileMatchingImportedEID(farmID: farmID, raw: eid)
                    } else {
                        return animalProfileAnyFarmMatchingImportedEID(eid)
                    }
                }()

                guard let profile = matchedProfile else {
                    unmatched += 1
                    continue
                }

                let alreadyExists = latestWeightEvent(farmID: profile.farmID, eidRaw: profile.eidRaw)?.number1 == row.fleeceWeightKg

                if alreadyExists {
                    switch duplicateAction {
                    case .skip:
                        duplicatesSkipped += 1
                        continue
                    case .replace:
                        replaced += 1
                    }
                }

                if let idx = animals.firstIndex(where: {
                    $0.farmID == profile.farmID &&
                    normalizedImportEID($0.eidRaw) == normalizedImportEID(profile.eidRaw)
                }) {
                    animals[idx].fleeceWeightKg = row.fleeceWeightKg
                    animals[idx].updatedAt = Date()
                }

                imported += 1
            }

            rebuildIndexes()
            scheduleSave()

            return HistoricalImportResult(
                imported: imported,
                unmatched: unmatched,
                skipped: parsed.skippedRows,
                duplicatesSkipped: duplicatesSkipped,
                replaced: replaced
            )
        }
    }

    @discardableResult
    func importHistoricalStapleLengthCSV(
        csvText: String,
        farmID: UUID? = nil,
        duplicateAction: DuplicateImportAction = .skip
    ) -> HistoricalImportResult {
        withDeferredSave {
            let parsed = CSVAnimalImporter.parseHistoricalStapleLengthCSV(csvText: csvText)

            guard !parsed.rows.isEmpty else {
                return HistoricalImportResult(
                    imported: 0,
                    unmatched: 0,
                    skipped: parsed.skippedRows,
                    duplicatesSkipped: 0,
                    replaced: 0
                )
            }

            var imported = 0
            var unmatched = 0
            var duplicatesSkipped = 0
            var replaced = 0

            for row in parsed.rows {
                let eid = normalizedImportEID(row.eid)
                guard !eid.isEmpty, eid != "—" else { continue }

                let matchedProfile: AnimalProfile? = {
                    if let farmID {
                        return animalProfileMatchingImportedEID(farmID: farmID, raw: eid)
                    } else {
                        return animalProfileAnyFarmMatchingImportedEID(eid)
                    }
                }()

                guard let profile = matchedProfile else {
                    unmatched += 1
                    continue
                }

                let alreadyExists = animalProfile(farmID: profile.farmID, eidRaw: profile.eidRaw)?.stapleLengthMm == row.stapleLengthMm

                if alreadyExists {
                    switch duplicateAction {
                    case .skip:
                        duplicatesSkipped += 1
                        continue
                    case .replace:
                        replaced += 1
                    }
                }

                if let idx = animals.firstIndex(where: {
                    $0.farmID == profile.farmID &&
                    normalizedImportEID($0.eidRaw) == normalizedImportEID(profile.eidRaw)
                }) {
                    animals[idx].stapleLengthMm = row.stapleLengthMm
                    animals[idx].updatedAt = Date()
                }

                imported += 1
            }

            rebuildIndexes()
            scheduleSave()

            return HistoricalImportResult(
                imported: imported,
                unmatched: unmatched,
                skipped: parsed.skippedRows,
                duplicatesSkipped: duplicatesSkipped,
                replaced: replaced
            )
        }
    }
    
    struct HistoricalImportResult {
        var imported: Int
        var unmatched: Int
        var skipped: Int
        var duplicatesSkipped: Int
        var replaced: Int
    }

    @discardableResult
    func addTraitsEvent(
        farmID: UUID,
        eidRaw: String,
        micron: Double?,
        stapleLengthMm: Int?,
        traitClass: AnimalClass?,
        notes: String?,
        customTraits: [String: String]?,
        at date: Date = Date(),
        sessionID: UUID? = nil
    ) -> AnimalEvent {
        var json: [String: String] = customTraits ?? [:]
        if let sessionID {
            json["sessionID"] = sessionID.uuidString
        }

        let e = AnimalEvent(
            farmID: farmID,
            eidRaw: eidRaw,
            kind: .traits,
            date: date,
            number1: micron,
            int1: stapleLengthMm,
            text1: traitClass?.rawValue,
            text2: notes,
            json: json.isEmpty ? nil : json
        )
        return appendAnimalEvent(e, dedupe: true)
    }

    func latestWeightEvent(farmID: UUID?, eidRaw: String) -> AnimalEvent? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }

        let key = farmID.map { animalIndexKey(farmID: $0, eidRaw: eid) } ?? eid
        return latestWeightEventIndex[key]
    }

    func latestPregnancyEvent(farmID: UUID?, eidRaw: String) -> AnimalEvent? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }

        let key = farmID.map { animalIndexKey(farmID: $0, eidRaw: eid) } ?? eid
        return latestPregnancyEventIndex[key]
    }
    func historicalFleeceDuplicateCountForImport(
        csvText: String,
        farmID: UUID? = nil
    ) -> Int {
        let parsed = CSVAnimalImporter.parseHistoricalFleeceWeightCSV(csvText: csvText)
        guard !parsed.rows.isEmpty else { return 0 }

        var count = 0

        for row in parsed.rows {
            let eid = normalizedImportEID(row.eid)
            guard !eid.isEmpty, eid != "—" else { continue }

            let matchedProfile: AnimalProfile? = {
                if let farmID {
                    return animalProfileMatchingImportedEID(farmID: farmID, raw: eid)
                } else {
                    return animalProfileAnyFarmMatchingImportedEID(eid)
                }
            }()

            guard let profile = matchedProfile else { continue }

            let alreadyExists = latestWeightEvent(farmID: profile.farmID, eidRaw: profile.eidRaw)?.number1 == row.fleeceWeightKg

            if alreadyExists {
                count += 1
            }
        }

        return count
    }

    func historicalStapleDuplicateCountForImport(
        csvText: String,
        farmID: UUID? = nil
    ) -> Int {
        let parsed = CSVAnimalImporter.parseHistoricalStapleLengthCSV(csvText: csvText)
        guard !parsed.rows.isEmpty else { return 0 }

        var count = 0

        for row in parsed.rows {
            let eid = normalizedImportEID(row.eid)
            guard !eid.isEmpty, eid != "—" else { continue }

            let matchedProfile: AnimalProfile? = {
                if let farmID {
                    return animalProfileMatchingImportedEID(farmID: farmID, raw: eid)
                } else {
                    return animalProfileAnyFarmMatchingImportedEID(eid)
                }
            }()

            guard let profile = matchedProfile else { continue }

            let alreadyExists = animalProfile(farmID: profile.farmID, eidRaw: profile.eidRaw)?.stapleLengthMm == row.stapleLengthMm

            if alreadyExists {
                count += 1
            }
        }

        return count
    }
    
    func lambCountForYear(farmID: UUID?, eidRaw: String, year: Int) -> Int? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }

        if let farmID {
            return lambCountByAnimalYearIndex["\(animalIndexKey(farmID: farmID, eidRaw: eid))|\(year)"]
        }

        for animal in animals {
            let cleaned = EIDValidator.cleanedRaw(animal.eidRaw)
            guard cleaned == eid else { continue }
            if let value = lambCountByAnimalYearIndex["\(animalIndexKey(farmID: animal.farmID, eidRaw: eid))|\(year)"] {
                return value
            }
        }

        return nil
    }

    func lambCountForCurrentYear(farmID: UUID?, eidRaw: String) -> Int? {
        let year = Calendar.current.component(.year, from: Date())
        return lambCountForYear(farmID: farmID, eidRaw: eidRaw, year: year)
    }
    // =========================================================
    // MARK: - Quick Start Templates
    // =========================================================

    struct SessionQuickStartTemplate: Identifiable, Codable, Hashable {
        struct TreatmentSelection: Codable, Hashable {
            var treatmentID: UUID
            var doseOverride: DoseValue?
        }

        let id: UUID
        var name: String
        var farmID: UUID
        var yardName: String?

        var sessionTypes: [SetupSessionType]

        var scannerType: ScannerType?
        var weightSource: WeightSource?
        var scanningEnabled: Bool
        var weighingEnabled: Bool

        var recordTreatments: Bool
        var recordLambsProduced: Bool
        var recordFleeceWeight: Bool
        var recordStapleLength: Bool
        var recordMicron: Bool
        var recordCustom1: Bool
        var recordCustom2: Bool

        var defaultSex: Sex
        var defaultClass: AnimalClass
        var defaultBreed: String?
        var defaultBirthYear: Int?
        var defaultBirthMonth: Int?
        var defaultStatus: AnimalStatus?
        var defaultMobName: String?

        var overwriteSex: Bool
        var overwriteBreed: Bool
        var overwriteMob: Bool
        var overwriteClass: Bool
        var overwriteBirthYear: Bool
        var overwriteBirthMonth: Bool
        var overwriteStatus: Bool

        var tepariGunEnabled: Bool
        var tepariTreatmentID: UUID?

        var treatmentSelections: [TreatmentSelection]

        init(
            id: UUID = UUID(),
            name: String,
            farmID: UUID,
            yardName: String? = nil,
            sessionTypes: [SetupSessionType] = [],
            scannerType: ScannerType? = nil,
            weightSource: WeightSource? = nil,
            scanningEnabled: Bool = false,
            weighingEnabled: Bool = false,
            recordTreatments: Bool = false,
            recordLambsProduced: Bool = false,
            recordFleeceWeight: Bool = false,
            recordStapleLength: Bool = false,
            recordMicron: Bool = false,
            recordCustom1: Bool = false,
            recordCustom2: Bool = false,
            defaultSex: Sex = .ewe,
            defaultClass: AnimalClass = .flock,
            defaultBreed: String? = nil,
            defaultBirthYear: Int? = nil,
            defaultBirthMonth: Int? = nil,
            defaultStatus: AnimalStatus? = nil,
            defaultMobName: String? = nil,
            overwriteSex: Bool = false,
            overwriteBreed: Bool = false,
            overwriteMob: Bool = false,
            overwriteClass: Bool = false,
            overwriteBirthYear: Bool = false,
            overwriteBirthMonth: Bool = false,
            overwriteStatus: Bool = false,
            tepariGunEnabled: Bool = false,
            tepariTreatmentID: UUID? = nil,
            treatmentSelections: [TreatmentSelection] = []
        ) {
            self.id = id
            self.name = name
            self.farmID = farmID
            self.yardName = yardName
            self.sessionTypes = sessionTypes
            self.scannerType = scannerType
            self.weightSource = weightSource
            self.scanningEnabled = scanningEnabled
            self.weighingEnabled = weighingEnabled
            self.recordTreatments = recordTreatments
            self.recordLambsProduced = recordLambsProduced
            self.recordFleeceWeight = recordFleeceWeight
            self.recordStapleLength = recordStapleLength
            self.recordMicron = recordMicron
            self.recordCustom1 = recordCustom1
            self.recordCustom2 = recordCustom2
            self.defaultSex = defaultSex
            self.defaultClass = defaultClass
            self.defaultBreed = defaultBreed
            self.defaultBirthYear = defaultBirthYear
            self.defaultBirthMonth = defaultBirthMonth
            self.defaultStatus = defaultStatus
            self.defaultMobName = defaultMobName
            self.overwriteSex = overwriteSex
            self.overwriteBreed = overwriteBreed
            self.overwriteMob = overwriteMob
            self.overwriteClass = overwriteClass
            self.overwriteBirthYear = overwriteBirthYear
            self.overwriteBirthMonth = overwriteBirthMonth
            self.overwriteStatus = overwriteStatus
            self.tepariGunEnabled = tepariGunEnabled
            self.tepariTreatmentID = tepariTreatmentID
            self.treatmentSelections = treatmentSelections
        }
    }

    @Published var sessionQuickStartTemplates: [SessionQuickStartTemplate] = []

    func saveSessionQuickStartTemplate(_ template: SessionQuickStartTemplate) {
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var clean = template
        clean.name = trimmedName

        if let idx = sessionQuickStartTemplates.firstIndex(where: {
            $0.id == clean.id || $0.name.caseInsensitiveCompare(clean.name) == .orderedSame
        }) {
            sessionQuickStartTemplates[idx] = clean
        } else {
            sessionQuickStartTemplates.insert(clean, at: 0)
        }

        sessionQuickStartTemplates.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        scheduleSave()
    }

    func deleteSessionQuickStartTemplate(id: UUID) {
        sessionQuickStartTemplates.removeAll { $0.id == id }
        scheduleSave()
    }
    // =========================================================
    // MARK: - Equipment (Wizard + runtime)
    // =========================================================

    enum SessionEquipment: String, CaseIterable, Codable, Hashable, Identifiable {
        case handler
        case draft
        case scanner
        case scales
        case stickReader
        case fleeceScales

        var id: String { rawValue }

        var label: String {
            switch self {
            case .handler:      return "Handler"
            case .draft:        return "Draft"
            case .scanner:      return "Scanner"
            case .scales:       return "Scales"
            case .stickReader:  return "Stick Reader"
            case .fleeceScales: return "Fleece Scales"
            }
        }

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

    // =========================================================
    // MARK: - Session Config (Wizard output)
    // =========================================================

    struct SessionConfig: Codable, Hashable {

        var farmID: UUID?
        var farmName: String
        var locationName: String?

        var scanningEnabled: Bool
        var scannerType: ScannerType?

        var weighingEnabled: Bool
        var weightSource: WeightSource?

        var equipment: [SessionEquipment]
        var tepariGunEnabled: Bool

        var recordTreatments: Bool
        var recordLambsProduced: Bool
        var recordFleeceWeight: Bool
        var recordStapleLength: Bool
        var recordMicron: Bool

        var recordCustom1: Bool
        var recordCustom2: Bool

        var sessionKind: Session.Kind
        var transferFromPIC: String?
        var transferToPIC: String?
        var saleReference: String?
        var saleDate: Date?

        init(
            farmID: UUID? = nil,
            farmName: String,
            locationName: String? = nil,
            scanningEnabled: Bool,
            scannerType: ScannerType? = nil,
            weighingEnabled: Bool,
            weightSource: WeightSource? = nil,
            equipment: [SessionEquipment] = [],
            tepariGunEnabled: Bool = false,

            recordTreatments: Bool = true,
            recordLambsProduced: Bool = false,
            recordFleeceWeight: Bool = false,
            recordStapleLength: Bool = true,
            recordMicron: Bool = true,

            recordCustom1: Bool = false,
            recordCustom2: Bool = false,

            sessionKind: Session.Kind = .general,
            transferFromPIC: String? = nil,
            transferToPIC: String? = nil,
            saleReference: String? = nil,
            saleDate: Date? = nil
        ) {
            self.farmID = farmID
            self.farmName = farmName
            self.locationName = locationName

            self.scanningEnabled = scanningEnabled
            self.scannerType = scannerType

            self.weighingEnabled = weighingEnabled
            self.weightSource = weightSource

            self.equipment = equipment
            self.tepariGunEnabled = tepariGunEnabled

            self.recordTreatments = recordTreatments
            self.recordLambsProduced = recordLambsProduced
            self.recordFleeceWeight = recordFleeceWeight
            self.recordStapleLength = recordStapleLength
            self.recordMicron = recordMicron

            self.recordCustom1 = recordCustom1
            self.recordCustom2 = recordCustom2

            self.sessionKind = sessionKind
            self.transferFromPIC = transferFromPIC
            self.transferToPIC = transferToPIC
            self.saleReference = saleReference
            self.saleDate = saleDate
        }
    }

    enum ScannerType: String, CaseIterable, Codable, Hashable, Identifiable {

        case racewell
        case stickReader
        case xrp2i
        case manual

        var id: String { rawValue }

        var label: String {
            switch self {
            case .racewell: return "T1 Integrated EID"
            case .stickReader: return "Stick Reader"
            case .xrp2i: return "XRP2i Panel Reader"
            case .manual: return "Manual Entry"
            }
        }

        var icon: String {
            switch self {
            case .racewell: return "scalemass"
            case .stickReader: return "dot.radiowaves.left.and.right"
            case .xrp2i: return "rectangle.connected.to.line.below"
            case .manual: return "keyboard"
            }
        }
    }

    enum WeightSource: String, CaseIterable, Codable, Hashable, Identifiable {
        case tepariT1
        case manual
        case demo

        var id: String { rawValue }

        var label: String {
            switch self {
            case .tepariT1: return "Tepari T1"
            case .manual: return "Manual"
            case .demo: return "Demo"
            }
        }
    }

    @Published private(set) var sessionConfigs: [UUID: SessionConfig] = [:]

    func config(for sessionID: UUID) -> SessionConfig? {
        sessionConfigs[sessionID]
    }

    func setConfig(_ config: SessionConfig?, for sessionID: UUID) {
        if let config {
            sessionConfigs[sessionID] = config
            syncSessionKindFromConfig(sessionID: sessionID, config: config)
        } else {
            sessionConfigs.removeValue(forKey: sessionID)
        }
        scheduleSave()
    }

    // =========================================================
    // MARK: - Session Kind Helpers (Transfer / Sale)
    // =========================================================

    private func syncSessionKindFromConfig(sessionID: UUID, config: SessionConfig) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].kind = config.sessionKind

        switch config.sessionKind {
        case .general:
            sessions[idx].transfer = nil
            sessions[idx].sale = nil
        case .transfer:
            if let from = config.transferFromPIC?.trimmingCharacters(in: .whitespacesAndNewlines),
               let to = config.transferToPIC?.trimmingCharacters(in: .whitespacesAndNewlines),
               !from.isEmpty, !to.isEmpty {
                sessions[idx].transfer = Session.TransferInfo(fromPIC: from, toPIC: to)
            } else {
                sessions[idx].transfer = nil
            }
            sessions[idx].sale = nil
        case .sale:
            let ref = config.saleReference?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanRef = (ref?.isEmpty == true) ? nil : ref
            sessions[idx].sale = Session.SaleInfo(reference: cleanRef, saleDate: config.saleDate)
            sessions[idx].transfer = nil
        }
    }

    func setSessionKind(
        sessionID: UUID,
        kind: Session.Kind,
        transfer: Session.TransferInfo? = nil,
        sale: Session.SaleInfo? = nil
    ) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].kind = kind
            sessions[idx].transfer = (kind == .transfer) ? transfer : nil
            sessions[idx].sale = (kind == .sale) ? sale : nil
        }

        if var cfg = sessionConfigs[sessionID] {
            cfg.sessionKind = kind
            switch kind {
            case .general:
                cfg.transferFromPIC = nil
                cfg.transferToPIC = nil
                cfg.saleReference = nil
                cfg.saleDate = nil
            case .transfer:
                cfg.transferFromPIC = transfer?.fromPIC
                cfg.transferToPIC = transfer?.toPIC
                cfg.saleReference = nil
                cfg.saleDate = nil
            case .sale:
                cfg.transferFromPIC = nil
                cfg.transferToPIC = nil
                cfg.saleReference = sale?.reference
                cfg.saleDate = sale?.saleDate
            }
            sessionConfigs[sessionID] = cfg
        }
        scheduleSave()
    }

    // =========================================================
    // MARK: - Treatment Library (Settings / global)
    // =========================================================

    @Published private(set) var treatmentLibrary: [TreatmentTemplate] = []
    private let treatmentLibraryDefaultsKey = "treatmentLibrary.v1"

    // =========================================================
    // MARK: - Traits Presets + Custom Field Definitions (Settings / global)
    // =========================================================

    enum CustomTraitKind: String, CaseIterable, Codable, Hashable, Identifiable {
        case number
        case text
        case picker
        var id: String { rawValue }
    }

    struct CustomTraitDefinition: Identifiable, Codable, Hashable {
        var id: String
        var label: String
        var kind: CustomTraitKind
        var quickPicks: [String]

        init(
            id: String,
            label: String,
            kind: CustomTraitKind,
            quickPicks: [String] = []
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.quickPicks = quickPicks
        }
    }

    struct TraitsConfig: Codable, Hashable {
        var micronQuickPicks: [Double]
        var stapleLengthQuickPicksMm: [Int]
        var customFields: [CustomTraitDefinition]

        init(
            micronQuickPicks: [Double] = [],
            stapleLengthQuickPicksMm: [Int] = [],
            customFields: [CustomTraitDefinition] = []
        ) {
            self.micronQuickPicks = micronQuickPicks
            self.stapleLengthQuickPicksMm = stapleLengthQuickPicksMm
            self.customFields = customFields
        }
    }

    @Published private(set) var traitsConfig: TraitsConfig = .init()
    private let traitsConfigDefaultsKey = "traitsConfig.v1"

    static let traitsConfigChangedNotification = Notification.Name("traitsConfigChanged")

    private var defaultTraitsConfig: TraitsConfig {
        TraitsConfig(
            micronQuickPicks: [16, 17, 18, 19, 20, 21],
            stapleLengthQuickPicksMm: [65, 70, 75, 80, 85, 90],
            customFields: []
        )
    }

    // =========================================================
    // MARK: - Init
    // =========================================================

    init() {
        if let data = UserDefaults.standard.data(forKey: treatmentLibraryDefaultsKey),
           let decoded = try? JSONDecoder().decode([TreatmentTemplate].self, from: data) {
            self.treatmentLibrary = decoded
        } else {
            self.treatmentLibrary = []
        }

        if treatmentLibrary.isEmpty {
            treatmentLibrary = [
                TreatmentTemplate(product: "Cydectin", doseValue: "3.4", doseUnit: .mL, withholding: ""),
                TreatmentTemplate(product: "Multimin", doseValue: "1 / 25kg", doseUnit: .mL, withholding: "")
            ]
            saveTreatmentLibrary()
        }

        if let data = UserDefaults.standard.data(forKey: traitsConfigDefaultsKey),
           let decoded = try? JSONDecoder().decode(TraitsConfig.self, from: data) {
            self.traitsConfig = sanitizeTraitsConfig(decoded)
        } else {
            self.traitsConfig = sanitizeTraitsConfig(defaultTraitsConfig)
            saveTraitsConfig(notify: false)
        }

        loadSnapshotFromDisk()
        loadAnimalEventsFromDisk()
        rebuildIndexes()
    }

    // =========================================================
    // MARK: - Treatment library helpers
    // =========================================================

    func addTreatmentTemplate(_ t: TreatmentTemplate) {
        treatmentLibrary.insert(t, at: 0)
        saveTreatmentLibrary()
    }

    func deleteTreatmentTemplate(id: UUID) {
        treatmentLibrary.removeAll { $0.id == id }
        saveTreatmentLibrary()
    }

    private func saveTreatmentLibrary() {
        if let data = try? JSONEncoder().encode(treatmentLibrary) {
            UserDefaults.standard.set(data, forKey: treatmentLibraryDefaultsKey)
        }
    }

    // =========================================================
    // MARK: - Traits config helpers
    // =========================================================

    func setTraitsConfig(_ cfg: TraitsConfig) {
        let sanitized = sanitizeTraitsConfig(cfg)
        guard sanitized != traitsConfig else { return }
        traitsConfig = sanitized
        saveTraitsConfig(notify: true)
    }

    func setMicronQuickPicks(_ picks: [Double]) {
        var cfg = traitsConfig
        cfg.micronQuickPicks = picks
        setTraitsConfig(cfg)
    }

    func setStapleLengthQuickPicksMm(_ picks: [Int]) {
        var cfg = traitsConfig
        cfg.stapleLengthQuickPicksMm = picks
        setTraitsConfig(cfg)
    }

    func setCustomTraitFields(_ fields: [CustomTraitDefinition]) {
        var cfg = traitsConfig
        cfg.customFields = fields
        setTraitsConfig(cfg)
    }

    private func saveTraitsConfig(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(traitsConfig) {
            UserDefaults.standard.set(data, forKey: traitsConfigDefaultsKey)
        }

        guard notify else { return }

        NotificationCenter.default.post(
            name: Self.traitsConfigChangedNotification,
            object: nil
        )
    }

    private func sanitizeTraitsConfig(_ cfg: TraitsConfig) -> TraitsConfig {
        var out = cfg

        out.micronQuickPicks = normalizeDoubles(out.micronQuickPicks, maxCount: 10)
        out.stapleLengthQuickPicksMm = normalizeInts(out.stapleLengthQuickPicksMm, maxCount: 10)

        var fields = out.customFields
        if fields.count > 2 { fields = Array(fields.prefix(2)) }

        if fields.indices.contains(0) { fields[0].id = "custom1" }
        if fields.indices.contains(1) { fields[1].id = "custom2" }

        for i in fields.indices {
            fields[i].label = fields[i].label.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[i].quickPicks = normalizeStrings(fields[i].quickPicks, maxCount: 10)
        }

        out.customFields = fields
        return out
    }

    private func normalizeStrings(_ inVals: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(min(maxCount, inVals.count))

        for v in inVals {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.insert(t).inserted {
                out.append(t)
                if out.count >= maxCount { break }
            }
        }
        return out
    }

    private func normalizeInts(_ inVals: [Int], maxCount: Int) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        out.reserveCapacity(min(maxCount, inVals.count))

        for v in inVals {
            if seen.insert(v).inserted {
                out.append(v)
                if out.count >= maxCount { break }
            }
        }
        return out
    }

    private func normalizeDoubles(_ inVals: [Double], maxCount: Int) -> [Double] {
        func key(_ d: Double) -> String { String(format: "%.3f", d) }
        var seen = Set<String>()
        var out: [Double] = []
        out.reserveCapacity(min(maxCount, inVals.count))

        for v in inVals {
            let k = key(v)
            if seen.insert(k).inserted {
                out.append(v)
                if out.count >= maxCount { break }
            }
        }
        return out
    }

    // =========================================================
    // MARK: - Session Treatments
    // =========================================================

    @Published private(set) var sessionTreatments: [UUID: [SessionTreatment]] = [:]
    @Published var sessionDraftSetup: [UUID: SessionDraftSetup] = [:]

    func treatments(for sessionID: UUID) -> [SessionTreatment] {
        sessionTreatments[sessionID] ?? []
    }

    func setSessionTreatments(_ treatments: [SessionTreatment], for sessionID: UUID) {
        sessionTreatments[sessionID] = treatments
        scheduleSave()
    }

    func addTreatment(sessionID: UUID, product: String, dosage: String, withholding: String) {
        let t = SessionTreatment(
            product: product.trimmingCharacters(in: .whitespacesAndNewlines),
            dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
            withholding: withholding.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var list = sessionTreatments[sessionID] ?? []
        list.insert(t, at: 0)
        setSessionTreatments(list, for: sessionID)
    }

    func updateTreatment(sessionID: UUID, treatment: SessionTreatment) {
        var list = sessionTreatments[sessionID] ?? []
        if let idx = list.firstIndex(where: { $0.id == treatment.id }) {
            list[idx] = treatment
        } else {
            list.insert(treatment, at: 0)
        }
        setSessionTreatments(list, for: sessionID)
    }

    func deleteTreatment(sessionID: UUID, treatmentID: UUID) {
        var list = sessionTreatments[sessionID] ?? []
        list.removeAll { $0.id == treatmentID }
        setSessionTreatments(list, for: sessionID)
    }

    func clearTreatments(sessionID: UUID) {
        setSessionTreatments([], for: sessionID)
    }

    // =========================================================
    // MARK: - Sex / Class
    // =========================================================

    enum Sex: String, CaseIterable, Codable, Hashable, Identifiable {
        case ewe
        case wether
        case ram

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ewe: return "Ewe"
            case .wether: return "Wether"
            case .ram: return "Ram"
            }
        }
    }

    enum AnimalClass: String, CaseIterable, Codable, Hashable, Identifiable {
        case flock
        case cull
        case stud
        case studReserve

        var id: String { rawValue }

        var label: String {
            switch self {
            case .flock: return "Flock"
            case .cull: return "Cull"
            case .stud: return "Stud"
            case .studReserve: return "Stud Reserve"
            }
        }
    }

    // =========================================================
    // MARK: - Session defaults
    // =========================================================

    @Published private(set) var sessionDefaultSex: [UUID: Sex] = [:]
    @Published private(set) var sessionDefaultClass: [UUID: AnimalClass] = [:]
    @Published private(set) var sessionDefaultMobName: [UUID: String] = [:]

    @Published private(set) var sessionDefaultBreed: [UUID: String] = [:]
    @Published private(set) var sessionDefaultBirthYear: [UUID: Int] = [:]
    @Published private(set) var sessionDefaultBirthMonth: [UUID: Int] = [:]
    @Published private(set) var sessionDefaultStatus: [UUID: AnimalStatus] = [:]

    func defaultSex(for sessionID: UUID) -> Sex? { sessionDefaultSex[sessionID] }

    func setDefaultSex(_ sex: Sex?, for sessionID: UUID) {
        if let sex { sessionDefaultSex[sessionID] = sex }
        else { sessionDefaultSex.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func defaultClass(for sessionID: UUID) -> AnimalClass? { sessionDefaultClass[sessionID] }

    func setDefaultClass(_ animalClass: AnimalClass?, for sessionID: UUID) {
        if let animalClass { sessionDefaultClass[sessionID] = animalClass }
        else { sessionDefaultClass.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func persistResolvedAnimalDefaultsForScan(
        sessionID: UUID,
        farmID: UUID,
        eidRaw: String
    ) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return }

        let existing = animalProfile(farmID: farmID, eidRaw: eid)

        let resolvedSex = resolvedSexForScan(sessionID: sessionID, farmID: farmID, eidRaw: eid)
        let resolvedClass = resolvedClassForScan(sessionID: sessionID, farmID: farmID, eidRaw: eid)
        let resolvedMobID = resolvedMobIDForScan(sessionID: sessionID, farmID: farmID, eidRaw: eid)

        let profile = AnimalProfile(
            id: existing?.id ?? UUID(),
            farmID: farmID,
            eidRaw: eid,
            mobID: resolvedMobID ?? existing?.mobID,
            sex: resolvedSex ?? existing?.sex,
            animalClass: resolvedClass ?? existing?.animalClass,
            breed: existing?.breed,
            birthYear: existing?.birthYear,
            birthMonth: existing?.birthMonth,
            status: existing?.status,
            lambsPerYear: existing?.lambsPerYear,
            fleeceWeightKg: existing?.fleeceWeightKg,
            stapleLengthMm: existing?.stapleLengthMm,
            klass: existing?.klass,
            comments: existing?.comments,
            userField1: existing?.userField1,
            userField2: existing?.userField2
        )

        upsertAnimal(profile)
    }

    func defaultMobName(for sessionID: UUID) -> String? { sessionDefaultMobName[sessionID] }

    func setDefaultMobName(_ name: String?, for sessionID: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty || trimmed == SessionSetupMobStepView.noneSentinel {
            sessionDefaultMobName.removeValue(forKey: sessionID)
        } else {
            sessionDefaultMobName[sessionID] = trimmed
        }

        scheduleSave()
    }

    func defaultBreed(for sessionID: UUID) -> String {
        sessionDefaultBreed[sessionID] ?? ""
    }

    func setDefaultBreed(_ breed: String, for sessionID: UUID) {
        let t = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { sessionDefaultBreed.removeValue(forKey: sessionID) }
        else { sessionDefaultBreed[sessionID] = t }
        scheduleSave()
    }

    func defaultBirthYear(for sessionID: UUID) -> Int? {
        sessionDefaultBirthYear[sessionID]
    }

    func setDefaultBirthYear(_ year: Int?, for sessionID: UUID) {
        if let year { sessionDefaultBirthYear[sessionID] = year }
        else { sessionDefaultBirthYear.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func defaultBirthMonth(for sessionID: UUID) -> Int? {
        sessionDefaultBirthMonth[sessionID]
    }

    func setDefaultBirthMonth(_ month: Int?, for sessionID: UUID) {
        if let month { sessionDefaultBirthMonth[sessionID] = month }
        else { sessionDefaultBirthMonth.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func defaultStatus(for sessionID: UUID) -> AnimalStatus? {
        sessionDefaultStatus[sessionID]
    }

    func setDefaultStatus(_ status: AnimalStatus, for sessionID: UUID) {
        sessionDefaultStatus[sessionID] = status
        scheduleSave()
    }

    func clearDefaultStatus(for sessionID: UUID) {
        sessionDefaultStatus.removeValue(forKey: sessionID)
        scheduleSave()
    }

    @Published private(set) var sessionOverwriteSex: [UUID: Bool] = [:]
    @Published private(set) var sessionOverwriteClass: [UUID: Bool] = [:]
    @Published private(set) var sessionOverwriteMob: [UUID: Bool] = [:]

    func overwriteSexEnabled(for sessionID: UUID) -> Bool { sessionOverwriteSex[sessionID] ?? false }
    func overwriteClassEnabled(for sessionID: UUID) -> Bool { sessionOverwriteClass[sessionID] ?? false }
    func overwriteMobEnabled(for sessionID: UUID) -> Bool { sessionOverwriteMob[sessionID] ?? false }

    func setOverwriteSexEnabled(_ on: Bool, for sessionID: UUID) {
        if on { sessionOverwriteSex[sessionID] = true }
        else { sessionOverwriteSex.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func setOverwriteClassEnabled(_ on: Bool, for sessionID: UUID) {
        if on { sessionOverwriteClass[sessionID] = true }
        else { sessionOverwriteClass.removeValue(forKey: sessionID) }
        scheduleSave()
    }

    func setOverwriteMobEnabled(_ on: Bool, for sessionID: UUID) {
        let mobName = sessionDefaultMobName[sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines)

        if mobName == SessionSetupMobStepView.mixedSentinel {
            sessionOverwriteMob.removeValue(forKey: sessionID)
            scheduleSave()
            return
        }

        if on {
            sessionOverwriteMob[sessionID] = true
        } else {
            sessionOverwriteMob.removeValue(forKey: sessionID)
        }

        scheduleSave()
    }

    // =========================================================
    // MARK: - Programmed Tags
    // =========================================================

    struct ProgrammedTagAssignment: Codable, Hashable {
        var sex: Sex?
        var animalClass: AnimalClass?
    }

    @Published private(set) var programmedTags: [UUID: [String: ProgrammedTagAssignment]] = [:]

    func programmedAssignment(for farmID: UUID, eidRaw: String) -> ProgrammedTagAssignment? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return programmedTags[farmID]?[eid]
    }

    func allProgrammedTags(for farmID: UUID) -> [(eid: String, assignment: ProgrammedTagAssignment)] {
        let map = programmedTags[farmID] ?? [:]
        return map
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    func setProgrammedTag(
        farmID: UUID,
        eidRaw: String,
        sex: Sex?,
        animalClass: AnimalClass?
    ) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return }

        var map = programmedTags[farmID] ?? [:]
        map[eid] = ProgrammedTagAssignment(sex: sex, animalClass: animalClass)
        programmedTags[farmID] = map
        scheduleSave()
    }

    func removeProgrammedTag(farmID: UUID, eidRaw: String) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard var map = programmedTags[farmID] else { return }
        map.removeValue(forKey: eid)
        programmedTags[farmID] = map.isEmpty ? nil : map
        scheduleSave()
    }

    // =========================================================
    // MARK: - Farm / Mob / Animal Catalog
    // =========================================================

    struct Farm: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String
        var pic: String
        var createdAt: Date

        init(id: UUID = UUID(), name: String, pic: String) {
            self.id = id
            self.name = name
            self.pic = pic
            self.createdAt = Date()
        }
    }

    struct Mob: Identifiable, Codable, Hashable {
        let id: UUID
        var farmID: UUID
        var name: String
        var colorHex: String
        var createdAt: Date

        init(id: UUID = UUID(), farmID: UUID, name: String, colorHex: String) {
            self.id = id
            self.farmID = farmID
            self.name = name
            self.colorHex = colorHex
            self.createdAt = Date()
        }
    }

    struct AnimalProfile: Identifiable, Codable, Hashable {
        let id: UUID
        var farmID: UUID
        var eidRaw: String
        var mobID: UUID?

        var sex: Sex?
        var animalClass: AnimalClass?

        var breed: String?
        var birthYear: Int?
        var birthMonth: Int?
        var status: AnimalStatus?

        var lambsPerYear: Int?
        var fleeceWeightKg: Double?
        var stapleLengthMm: Double?

        var klass: String?

        var comments: String?
        var userField1: String?
        var userField2: String?

        var updatedAt: Date

        init(
            id: UUID = UUID(),
            farmID: UUID,
            eidRaw: String,
            mobID: UUID? = nil,
            sex: Sex? = nil,
            animalClass: AnimalClass? = nil,
            breed: String? = nil,
            birthYear: Int? = nil,
            birthMonth: Int? = nil,
            status: AnimalStatus? = nil,
            lambsPerYear: Int? = nil,
            fleeceWeightKg: Double? = nil,
            stapleLengthMm: Double? = nil,
            klass: String? = nil,
            comments: String? = nil,
            userField1: String? = nil,
            userField2: String? = nil
        ) {
            self.id = id
            self.farmID = farmID
            self.eidRaw = EIDValidator.cleanedRaw(eidRaw)
            self.mobID = mobID
            self.sex = sex
            self.animalClass = animalClass

            self.breed = breed?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.birthYear = birthYear
            self.birthMonth = birthMonth
            self.status = status

            self.lambsPerYear = lambsPerYear
            self.fleeceWeightKg = fleeceWeightKg
            self.stapleLengthMm = stapleLengthMm
            self.klass = klass
            self.comments = comments
            self.userField1 = userField1
            self.userField2 = userField2
            self.updatedAt = Date()
        }
    }

    @Published private(set) var farms: [Farm] = []
    @Published private(set) var mobs: [Mob] = []
    @Published private(set) var animals: [AnimalProfile] = []

    private var animalProfileIndex: [String: AnimalProfile] = [:]
    private var animalProfileAnyFarmIndex: [String: AnimalProfile] = [:]
    private var animalSearchIndex: [(eidRaw: String, profile: AnimalProfile)] = []

    private var recordsBySessionIndex: [UUID: [AnimalRecord]] = [:]
    private var recordsByEIDIndex: [String: [AnimalRecord]] = [:]

    private var latestWeightEventIndex: [String: AnimalEvent] = [:]
    private var latestPregnancyEventIndex: [String: AnimalEvent] = [:]

    // =========================================================
    // MARK: - Fast lookup indexes (Phase 1 performance)
    // =========================================================

    private var farmByIDIndex: [UUID: Farm] = [:]
    private var farmIDByPICIndex: [String: UUID] = [:]
    private var farmIDByNameIndex: [String: UUID] = [:]

    private var mobByIDIndex: [UUID: Mob] = [:]
    private var mobsByFarmIDIndex: [UUID: [Mob]] = [:]
    private var mobIDByFarmAndNameIndex: [String: UUID] = [:]

    private var totalLambsByAnimalIndex: [String: Int] = [:]
    private var lambingEventsByAnimalIndex: [String: [AnimalEvent]] = [:]
    private var lambCountByAnimalYearIndex: [String: Int] = [:]
    private func animalIndexKey(farmID: UUID, eidRaw: String) -> String {
        "\(farmID.uuidString)|\(EIDValidator.cleanedRaw(eidRaw))"
    }

    private func rebuildIndexes() {
        animalProfileIndex = [:]
        animalProfileAnyFarmIndex = [:]
        animalSearchIndex = []

        recordsBySessionIndex = [:]
        recordsByEIDIndex = [:]

        latestWeightEventIndex = [:]
        latestPregnancyEventIndex = [:]

        farmByIDIndex = [:]
        farmIDByPICIndex = [:]
        farmIDByNameIndex = [:]

        mobByIDIndex = [:]
        mobsByFarmIDIndex = [:]
        mobIDByFarmAndNameIndex = [:]

        totalLambsByAnimalIndex = [:]
        lambingEventsByAnimalIndex = [:]
        lambCountByAnimalYearIndex = [:]

        // -----------------------------------------------------
        // Farms
        // -----------------------------------------------------
        for farm in farms {
            farmByIDIndex[farm.id] = farm

            let cleanPIC = farm.pic
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !cleanPIC.isEmpty {
                farmIDByPICIndex[cleanPIC] = farm.id
            }

            let cleanName = farm.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !cleanName.isEmpty {
                farmIDByNameIndex[cleanName] = farm.id
            }
        }

        // -----------------------------------------------------
        // Mobs
        // -----------------------------------------------------
        for mob in mobs {
            mobByIDIndex[mob.id] = mob
            mobsByFarmIDIndex[mob.farmID, default: []].append(mob)

            let key = "\(mob.farmID.uuidString)|\(mob.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if !mob.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mobIDByFarmAndNameIndex[key] = mob.id
            }
        }

        // Keep farm mobs in a stable order
        for key in mobsByFarmIDIndex.keys {
            mobsByFarmIDIndex[key]?.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        // -----------------------------------------------------
        // Animals
        // -----------------------------------------------------
        for animal in animals {
            let eid = EIDValidator.cleanedRaw(animal.eidRaw)
            guard !eid.isEmpty, eid != "—" else { continue }

            animalProfileIndex[animalIndexKey(farmID: animal.farmID, eidRaw: eid)] = animal

            if animalProfileAnyFarmIndex[eid] == nil {
                animalProfileAnyFarmIndex[eid] = animal
            }

            animalSearchIndex.append((eidRaw: eid, profile: animal))
        }

        // -----------------------------------------------------
        // Records
        // -----------------------------------------------------
        for record in records {
            let eid = EIDValidator.cleanedRaw(record.eidRaw)
            guard !eid.isEmpty, eid != "—" else { continue }

            recordsBySessionIndex[record.sessionID, default: []].append(record)
            recordsByEIDIndex[eid, default: []].append(record)
        }

        for key in recordsBySessionIndex.keys {
            recordsBySessionIndex[key]?.sort { $0.recordedAt > $1.recordedAt }
        }

        for key in recordsByEIDIndex.keys {
            recordsByEIDIndex[key]?.sort { $0.recordedAt > $1.recordedAt }
        }

        func updateLatestEventIndex(
            _ index: inout [String: AnimalEvent],
            key: String,
            event: AnimalEvent
        ) {
            if let existing = index[key] {
                if event.date > existing.date {
                    index[key] = event
                }
            } else {
                index[key] = event
            }
        }

        // -----------------------------------------------------
        // Animal events
        // -----------------------------------------------------
        for event in animalEvents {
            let eid = EIDValidator.cleanedRaw(event.eidRaw)
            guard !eid.isEmpty, eid != "—" else { continue }

            let anyFarmKey = eid
            let farmSpecificKey = animalIndexKey(farmID: event.farmID, eidRaw: eid)

            switch event.kind {
            case .weight:
                updateLatestEventIndex(&latestWeightEventIndex, key: anyFarmKey, event: event)
                updateLatestEventIndex(&latestWeightEventIndex, key: farmSpecificKey, event: event)

            case .pregnancy:
                updateLatestEventIndex(&latestPregnancyEventIndex, key: anyFarmKey, event: event)
                updateLatestEventIndex(&latestPregnancyEventIndex, key: farmSpecificKey, event: event)

            case .lambing:
                let animalKey = farmSpecificKey
                let year = event.int1 ?? Calendar.current.component(.year, from: event.date)

                let born: Int = {
                    if let n = event.int1, event.json?["born"] == nil { return n }
                    if let s = event.json?["born"], let n = Int(s) { return n }
                    return 0
                }()

                totalLambsByAnimalIndex[animalKey, default: 0] += born
                lambingEventsByAnimalIndex[animalKey, default: []].append(event)
                lambCountByAnimalYearIndex["\(animalKey)|\(year)"] = born

            default:
                break
            }
        }

        for key in lambingEventsByAnimalIndex.keys {
            lambingEventsByAnimalIndex[key]?.sort { lhs, rhs in
                let lhsYear = lhs.int1 ?? Calendar.current.component(.year, from: lhs.date)
                let rhsYear = rhs.int1 ?? Calendar.current.component(.year, from: rhs.date)
                return lhsYear > rhsYear
            }
        }
    }
    // =========================================================
    // MARK: - Sale archive
    // =========================================================

    struct SoldAnimal: Identifiable, Codable, Hashable {
        let id: UUID
        var eidRaw: String
        var fromFarmID: UUID?
        var soldAt: Date
        var reference: String?

        init(
            id: UUID = UUID(),
            eidRaw: String,
            fromFarmID: UUID?,
            soldAt: Date = Date(),
            reference: String? = nil
        ) {
            self.id = id
            self.eidRaw = EIDValidator.cleanedRaw(eidRaw)
            self.fromFarmID = fromFarmID
            self.soldAt = soldAt
            self.reference = reference
        }
    }

    @Published private(set) var soldArchive: [SoldAnimal] = []

    // =========================================================
    // MARK: - Transfer / Sale operations
    // =========================================================

    @discardableResult
    func transferAnimal(eidRaw: String, fromPIC: String, toPIC: String) -> Bool {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        let from = fromPIC.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toPIC.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eid.isEmpty, eid != "—", !from.isEmpty, !to.isEmpty else { return false }

        guard let fromFarm = farms.first(where: { $0.pic.caseInsensitiveCompare(from) == .orderedSame }),
              let toFarm = farms.first(where: { $0.pic.caseInsensitiveCompare(to) == .orderedSame }) else {
            return false
        }

        let ok = transferAnimal(eidRaw: eid, fromFarmID: fromFarm.id, toFarmID: toFarm.id)
        if ok { scheduleSave() }
        return ok
    }

    @discardableResult
    func transferAnimal(eidRaw: String, fromFarmID: UUID, toFarmID: UUID) -> Bool {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return false }
        guard fromFarmID != toFarmID else { return false }

        guard let idx = animals.firstIndex(where: { $0.farmID == fromFarmID && $0.eidRaw == eid }) else {
            return false
        }

        var moved = animals[idx]
        animals.remove(at: idx)

        moved.farmID = toFarmID
        moved.mobID = nil
        moved.updatedAt = Date()

        if let dstIdx = animals.firstIndex(where: { $0.farmID == toFarmID && $0.eidRaw == eid }) {
            animals[dstIdx] = moved
        } else {
            animals.insert(moved, at: 0)
        }

        rebuildIndexes()
        scheduleSave()
        return true
    }

    @discardableResult
    func markAnimalSold(
        eidRaw: String,
        farmID: UUID? = nil,
        reference: String? = nil,
        soldAt: Date = Date()
    ) -> Bool {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return false }

        if let farmID {
            guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return false }
            animals.remove(at: idx)
            soldArchive.insert(SoldAnimal(eidRaw: eid, fromFarmID: farmID, soldAt: soldAt, reference: reference), at: 0)
            rebuildIndexes()
            scheduleSave()
            return true
        }

        guard let idx = animals.firstIndex(where: { $0.eidRaw == eid }) else { return false }
        let fromFarm = animals[idx].farmID
        animals.remove(at: idx)
        soldArchive.insert(SoldAnimal(eidRaw: eid, fromFarmID: fromFarm, soldAt: soldAt, reference: reference), at: 0)
        rebuildIndexes()
        scheduleSave()
        return true
    }

    // =========================================================
    // MARK: - Session-driven helpers
    // =========================================================

    @discardableResult
    func applyTransfer(sessionID: UUID, eidRaw: String) -> Bool {
        guard let cfg = config(for: sessionID) else { return false }
        guard cfg.sessionKind == .transfer else { return false }

        let fromPIC = cfg.transferFromPIC?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toPIC = cfg.transferToPIC?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !fromPIC.isEmpty, !toPIC.isEmpty else { return false }

        return transferAnimal(eidRaw: eidRaw, fromPIC: fromPIC, toPIC: toPIC)
    }

    @discardableResult
    func applySale(sessionID: UUID, eidRaw: String) -> Bool {
        guard let cfg = config(for: sessionID) else { return false }
        guard cfg.sessionKind == .sale else { return false }

        let farmID = cfg.farmID ?? sessionFarmID[sessionID]
        let ref = cfg.saleReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRef = (ref?.isEmpty == true) ? nil : ref
        let date = cfg.saleDate ?? Date()

        return markAnimalSold(eidRaw: eidRaw, farmID: farmID, reference: cleanRef, soldAt: date)
    }

    // =========================================================
    // MARK: - Session-driven naming helpers
    // =========================================================

    func animalCountForSession(sessionID: UUID) -> Int {
        let eids = Set((recordsBySessionIndex[sessionID] ?? []).map { $0.eidRaw })
        return eids.count
    }

    func makeUniqueSessionName(
        typeLabel: String,
        farmName: String,
        yardName: String?,
        mobName: String?,
        animalCount: Int?,
        at: Date = Date(),
        excluding sessionID: UUID? = nil
    ) -> String {
        let farm = farmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFarm = farm.isEmpty ? "Untitled" : farm

        let rawType = typeLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var orderedTypes: [String] = []

        if rawType.contains("weigh") { orderedTypes.append("Weigh") }
        if rawType.contains("draft") { orderedTypes.append("Draft") }
        if rawType.contains("treat") { orderedTypes.append("Treat") }

        let typeText = orderedTypes.isEmpty ? "General" : orderedTypes.joined(separator: "/")

        let mob = (mobName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMob = mob.isEmpty ? "—" : mob

        let count = max(0, animalCount ?? 0)

        let base = "\(safeFarm) - \(typeText) - \(safeMob) - \(count)"
        return uniqueSessionName(base, excluding: sessionID)
    }

    // =========================================================
    // MARK: - Per-session selections (legacy)
    // =========================================================

    @Published private(set) var sessionFarmID: [UUID: UUID] = [:]
    @Published private(set) var sessionMobID: [UUID: UUID] = [:]
    @Published var pendingFarmSelectionSessionID: UUID? = nil

    func farmID(for sessionID: UUID) -> UUID? { sessionFarmID[sessionID] }

    // =========================================================
    // MARK: - Session naming / creation helpers
    // =========================================================

    func defaultSessionName(
        farmID: UUID?,
        sessionTypes: Set<SetupSessionType> = [],
        explicitKind: Session.Kind? = nil
    ) -> String {

        let farmName: String = {
            if let farmID, let f = farms.first(where: { $0.id == farmID }) {
                return f.name
            }
            return "Untitled"
        }()

        var types: [String] = []

        if sessionTypes.contains(.weigh) { types.append("Weigh") }
        if sessionTypes.contains(.draft) { types.append("Draft") }
        if sessionTypes.contains(.treatment) { types.append("Treat") }

        let typeText = types.isEmpty ? "General" : types.joined(separator: "/")
        let mobText = "—"
        let count = 0

        return "\(farmName) - \(typeText) - \(mobText) - \(count)"
    }

    func uniqueSessionName(_ proposed: String, excluding sessionID: UUID? = nil) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "Untitled" }

        let existingNames = sessions
            .filter { s in
                if let sessionID { return s.id != sessionID }
                return true
            }
            .map { $0.name.lowercased() }

        if !existingNames.contains(base.lowercased()) { return base }

        var n = 2
        while true {
            let candidate = "\(base) (\(n))"
            if !existingNames.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }

    @discardableResult
    func ensureSession(
        id: UUID,
        name: String,
        farmID: UUID? = nil,
        mobID: UUID? = nil
    ) -> Session {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmed.isEmpty ? "Untitled" : trimmed
        let unique = uniqueSessionName(safeName, excluding: id)

        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].name = unique
            sessions[idx].farmID = farmID
            sessions[idx].mobID = mobID
            if let farmID { sessionFarmID[id] = farmID }
            if let mobID { sessionMobID[id] = mobID }
            scheduleSave()
            return sessions[idx]
        }

        let created = Session(
            id: id,
            name: unique,
            farmID: farmID,
            mobID: mobID,
            createdAt: Date()
        )
        sessions.insert(created, at: 0)

        if let farmID {
            sessionFarmID[id] = farmID
            pendingFarmSelectionSessionID = nil
        } else {
            if farms.count > 1 {
                pendingFarmSelectionSessionID = id
            } else if farms.count == 1, let only = farms.first?.id {
                sessionFarmID[id] = only
                sessions[0].farmID = only
                pendingFarmSelectionSessionID = nil
            }
        }

        if let mobID { sessionMobID[id] = mobID }

        scheduleSave()
        return created
    }

    func upsertSessionName(sessionID: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].name = trimmed
        scheduleSave()
    }

    func deleteAnimals(ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        animals.removeAll { idSet.contains($0.id) }
        rebuildIndexes()
        scheduleSave()
    }

    func setSessionFarm(sessionID: UUID, farmID: UUID?) {
        if let farmID { sessionFarmID[sessionID] = farmID }
        else { sessionFarmID.removeValue(forKey: sessionID) }

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].farmID = farmID
        }

        if pendingFarmSelectionSessionID == sessionID, farmID != nil {
            pendingFarmSelectionSessionID = nil
        }

        scheduleSave()
    }

    func setSessionMob(sessionID: UUID, mobID: UUID?) {
        if let mobID { sessionMobID[sessionID] = mobID }
        else { sessionMobID.removeValue(forKey: sessionID) }

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].mobID = mobID
        }

        scheduleSave()
    }

    // =========================================================
    // MARK: - DEV: Force seed on every launch
    // =========================================================

    func forceReseedDemoData() {
        withDeferredSave {
            resetAllData()

            let greenwood = addFarm(name: "Greenwood Park", pic: "SA12345")
            let mahanewo  = addFarm(name: "Mahanewo", pic: "SA54321")

            let mobNames = ["Blue", "Green", "Black", "Yellow", "Red"]

            seedMobsAndAnimals(for: greenwood, mobNames: mobNames, farmSeed: 12345)
            seedMobsAndAnimals(for: mahanewo, mobNames: mobNames, farmSeed: 54321)

            scheduleSave()
        }
    }

    func resetAllData() {
        withDeferredSave {
            sessions.removeAll()
            records.removeAll()

            sessionConfigs.removeAll()
            sessionTreatments.removeAll()
            sessionDraftSetup.removeAll()

            sessionFarmID.removeAll()
            sessionMobID.removeAll()

            sessionDefaultSex.removeAll()
            sessionDefaultClass.removeAll()
            sessionDefaultMobName.removeAll()

            sessionDefaultBreed.removeAll()
            sessionDefaultBirthYear.removeAll()
            sessionDefaultBirthMonth.removeAll()
            sessionDefaultStatus.removeAll()

            sessionOverwriteSex.removeAll()
            sessionOverwriteClass.removeAll()
            sessionOverwriteMob.removeAll()

            pendingFarmSelectionSessionID = nil

            programmedTags.removeAll()

            farms.removeAll()
            mobs.removeAll()
            animals.removeAll()

            animalEvents.removeAll()

            soldArchive.removeAll()

            rebuildIndexes()
            scheduleSave()
        }
    }

    private func seedMobsAndAnimals(for farm: Farm, mobNames: [String], farmSeed: UInt64) {
        for (mobIndex, mobName) in mobNames.enumerated() {
            let colorHex = devColorHex(forMobName: mobName)
            let mob = addMob(farmID: farm.id, name: mobName, colorHex: colorHex)

            var rng = SeededRNG(seed: farmSeed &+ UInt64(mobIndex) &* 1000)
            for _ in 1...10 {
                let eid = devMakeEID(rng: &rng)
                let profile = AnimalProfile(
                    farmID: farm.id,
                    eidRaw: eid,
                    mobID: mob.id,
                    sex: .ewe,
                    animalClass: .flock,
                    breed: nil,
                    birthYear: nil,
                    birthMonth: nil,
                    status: .dry,
                    klass: AnimalClass.flock.rawValue,
                    comments: nil,
                    userField1: nil,
                    userField2: nil
                )
                upsertAnimal(profile)
            }
        }
    }

    private func devColorHex(forMobName name: String) -> String {
        switch name.lowercased() {
        case "blue":   return "#2196F3"
        case "green":  return "#4CAF50"
        case "black":  return "#111111"
        case "yellow": return "#FFEB3B"
        case "red":    return "#F44336"
        default:       return "#9E9E9E"
        }
    }

    private func devMakeEID(rng: inout SeededRNG) -> String {
        let body = rng.nextInt(in: 100_000_000...999_999_999)
        return "982 \(body)"
    }

    struct SeededRNG {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

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

    // =========================================================
    // MARK: - Session creation (legacy)
    // =========================================================

    func createSession(named name: String) -> Session {
        let session = Session(name: name)
        sessions.insert(session, at: 0)

        if farms.count == 1 {
            sessionFarmID[session.id] = farms[0].id
            pendingFarmSelectionSessionID = nil
        } else if farms.count > 1 {
            pendingFarmSelectionSessionID = session.id
        }

        scheduleSave()
        return session
    }

    func createSession(named name: String, farmID: UUID) -> Session {
        let session = Session(name: name)
        sessions.insert(session, at: 0)
        sessionFarmID[session.id] = farmID
        pendingFarmSelectionSessionID = nil
        scheduleSave()
        return session
    }

    func setFarm(for sessionID: UUID, farmID: UUID) {
        setSessionFarm(sessionID: sessionID, farmID: farmID)
    }

    func setFarm(_ sessionID: UUID, _ farmID: UUID) {
        setFarm(for: sessionID, farmID: farmID)
    }

    func setMob(for sessionID: UUID, mobID: UUID?) {
        setSessionMob(sessionID: sessionID, mobID: mobID)
    }

    // =========================================================
    // MARK: - Records
    // =========================================================

    @discardableResult
    func upsertRecord(
        sessionID: UUID,
        eidRaw: String,
        defaultLockedWeight: Double = 0,
        defaultTreatments: [SessionTreatment] = [],
        updateRecordedAt: Bool = true,
        mutate: (inout AnimalRecord) -> Void
    ) -> AnimalRecord {
        let eid = EIDValidator.cleanedRaw(eidRaw)

        if let idx = records.firstIndex(where: { $0.sessionID == sessionID && $0.eidRaw == eid }) {
            var rec = records[idx]
            mutate(&rec)
            if updateRecordedAt {
                rec.recordedAt = Date()
            }
            records[idx] = rec
            rebuildIndexes()
            scheduleSave()
            return rec
        }

        var rec = AnimalRecord(
            sessionID: sessionID,
            eidRaw: eid,
            lockedWeight: defaultLockedWeight,
            recordedAt: Date(),
            treatments: defaultTreatments
        )
        mutate(&rec)
        if updateRecordedAt {
            rec.recordedAt = Date()
        }
        records.insert(rec, at: 0)
        rebuildIndexes()
        scheduleSave()
        return rec
    }

    func addOrOverwriteRecord(sessionID: UUID, eidRaw: String, lockedWeight: Double, treatments: [SessionTreatment]) {
        withDeferredSave {
            let rec = upsertRecord(
                sessionID: sessionID,
                eidRaw: eidRaw,
                defaultLockedWeight: lockedWeight,
                defaultTreatments: treatments,
                updateRecordedAt: true
            ) { rec in
                rec.lockedWeight = lockedWeight
                rec.treatments = treatments
            }

            guard let farmID = resolvedFarmIDForEvent(sessionID: sessionID) else { return }

            if rec.lockedWeight > 0 {
                addWeightEvent(farmID: farmID, eidRaw: rec.eidRaw, weightKg: rec.lockedWeight, at: rec.recordedAt)
            }

            for t in rec.treatments {
                addTreatmentEvent(
                    farmID: farmID,
                    eidRaw: rec.eidRaw,
                    product: t.product,
                    dosage: t.dosage,
                    withholding: t.withholding,
                    at: rec.recordedAt,
                    sessionID: sessionID
                )
            }

            addLastSeenEvent(farmID: farmID, eidRaw: rec.eidRaw, at: rec.recordedAt, sessionID: sessionID)
        }
    }

    @discardableResult
    func applyDraftResult(
        sessionID: UUID,
        eidRaw: String,
        draftResult: DraftPosition?,
        matchedRuleName: String?
    ) -> AnimalRecord {
        upsertRecord(
            sessionID: sessionID,
            eidRaw: eidRaw,
            defaultLockedWeight: 0,
            defaultTreatments: [],
            updateRecordedAt: false
        ) { rec in
            rec.draftResult = draftResult
            let t = matchedRuleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rec.matchedRuleName = t.isEmpty ? nil : t
        }
    }

    @discardableResult
    func applyTraits(
        sessionID: UUID,
        eidRaw: String,
        micron: Double?,
        stapleLengthMm: Int?,
        fleeceWeightKg: Double?,
        traitClass: AnimalClass?,
        notes: String?,
        customTraits: [String: String]?
    ) -> AnimalRecord {
        withDeferredSave {
            let rec = upsertRecord(
                sessionID: sessionID,
                eidRaw: eidRaw,
                defaultLockedWeight: 0,
                defaultTreatments: [],
                updateRecordedAt: false
            ) { rec in
                rec.micron = micron
                rec.stapleLengthMm = stapleLengthMm
                rec.traitClass = traitClass

                let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                rec.traitNotes = (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes

                var mergedCustom = customTraits ?? [:]
                if let fleeceWeightKg {
                    mergedCustom["fleeceWeightKg"] = String(fleeceWeightKg)
                }
                rec.customTraits = mergedCustom.isEmpty ? nil : mergedCustom
            }

            if let farmID = resolvedFarmIDForEvent(sessionID: sessionID) {
                addTraitsEvent(
                    farmID: farmID,
                    eidRaw: rec.eidRaw,
                    micron: rec.micron,
                    stapleLengthMm: rec.stapleLengthMm,
                    traitClass: rec.traitClass,
                    notes: rec.traitNotes,
                    customTraits: rec.customTraits,
                    at: rec.recordedAt,
                    sessionID: sessionID
                )
            }

            return rec
        }
    }

    func records(for sessionID: UUID) -> [AnimalRecord] {
        recordsBySessionIndex[sessionID] ?? []
    }

    func latestRecord(sessionID: UUID, eidRaw: String) -> AnimalRecord? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return records(for: sessionID).first(where: { $0.eidRaw == eid })
    }

    func previousRecord(sessionID: UUID, eidRaw: String) -> AnimalRecord? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        let matches = records(for: sessionID).filter { $0.eidRaw == eid }
        guard matches.count >= 2 else { return nil }
        return matches[1]
    }

    func averageWeight(sessionID: UUID) -> Double? {
        let r = records(for: sessionID)
        guard !r.isEmpty else { return nil }
        return r.map { $0.lockedWeight }.reduce(0, +) / Double(r.count)
    }

    func allRecords(forEID eidRaw: String) -> [AnimalRecord] {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return [] }
        return recordsByEIDIndex[eid] ?? []
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        records.removeAll { $0.sessionID == session.id }

        sessionConfigs.removeValue(forKey: session.id)
        sessionDraftSetup.removeValue(forKey: session.id)

        sessionFarmID.removeValue(forKey: session.id)
        sessionMobID.removeValue(forKey: session.id)
        sessionDefaultSex.removeValue(forKey: session.id)
        sessionDefaultClass.removeValue(forKey: session.id)
        sessionDefaultMobName.removeValue(forKey: session.id)

        sessionDefaultBreed.removeValue(forKey: session.id)
        sessionDefaultBirthYear.removeValue(forKey: session.id)
        sessionDefaultBirthMonth.removeValue(forKey: session.id)
        sessionDefaultStatus.removeValue(forKey: session.id)

        sessionOverwriteSex.removeValue(forKey: session.id)
        sessionOverwriteClass.removeValue(forKey: session.id)
        sessionOverwriteMob.removeValue(forKey: session.id)

        sessionTreatments.removeValue(forKey: session.id)

        if pendingFarmSelectionSessionID == session.id {
            pendingFarmSelectionSessionID = nil
        }

        rebuildIndexes()
        scheduleSave()
    }

    // =========================================================
    // MARK: - Farms
    // =========================================================

    @discardableResult
    func addFarm(name: String, pic: String) -> Farm {
        let farm = Farm(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            pic: pic.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        farms.insert(farm, at: 0)
        scheduleSave()
        return farm
    }

    func updateFarm(_ farm: Farm) {
        guard let idx = farms.firstIndex(where: { $0.id == farm.id }) else { return }
        farms[idx] = farm
        scheduleSave()
    }

    func deleteFarm(_ farmID: UUID) {
        farms.removeAll { $0.id == farmID }
        mobs.removeAll { $0.farmID == farmID }
        animals.removeAll { $0.farmID == farmID }

        sessionFarmID = sessionFarmID.filter { $0.value != farmID }
        programmedTags.removeValue(forKey: farmID)

        animalEvents.removeAll { $0.farmID == farmID }

        rebuildIndexes()
        scheduleSave()
    }

    // =========================================================
    // MARK: - Mobs
    // =========================================================

    @discardableResult
    func addMob(farmID: UUID, name: String, colorHex: String) -> Mob {
        let mob = Mob(
            farmID: farmID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        mobs.insert(mob, at: 0)
        scheduleSave()
        return mob
    }

    func updateMob(_ mob: Mob) {
        guard let idx = mobs.firstIndex(where: { $0.id == mob.id }) else { return }
        mobs[idx] = mob
        scheduleSave()
    }

    func deleteMob(_ mobID: UUID) {
        mobs.removeAll { $0.id == mobID }

        for i in animals.indices {
            if animals[i].mobID == mobID {
                animals[i].mobID = nil
                animals[i].updatedAt = Date()
            }
        }

        sessionMobID = sessionMobID.filter { $0.value != mobID }
        rebuildIndexes()
        scheduleSave()
    }

    func mobs(for farmID: UUID) -> [Mob] {
        mobsByFarmIDIndex[farmID] ?? []
    }

    // =========================================================
    // MARK: - Session editing helpers
    // =========================================================

    func renameSession(sessionID: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].name = trimmed
        scheduleSave()
    }

    func updateSession(sessionID: UUID, mutate: (inout Session) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var copy = sessions[idx]
        mutate(&copy)
        sessions[idx] = copy
        scheduleSave()
    }

    // =========================================================
    // MARK: - Animal profiles
    // =========================================================

    private func normalizedAnimalProfile(_ profile: AnimalProfile) -> AnimalProfile {
        var copy = profile
        copy.eidRaw = EIDValidator.cleanedRaw(copy.eidRaw)

        if let ac = copy.animalClass {
            copy.klass = ac.rawValue
        } else if let klass = copy.klass, let ac = AnimalClass(rawValue: klass) {
            copy.animalClass = ac
        }

        if let b = copy.breed {
            let t = b.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.breed = t.isEmpty ? nil : t
        }

        copy.updatedAt = Date()
        return copy
    }

    func upsertAnimal(_ profile: AnimalProfile) {
        let normalized = normalizedAnimalProfile(profile)

        if let idx = animals.firstIndex(where: {
            $0.farmID == normalized.farmID && $0.eidRaw == normalized.eidRaw
        }) {
            animals[idx] = normalized
        } else {
            animals.insert(normalized, at: 0)
        }

        rebuildIndexes()
        scheduleSave()
    }

    func animalProfile(farmID: UUID, eidRaw: String) -> AnimalProfile? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return animalProfileIndex[animalIndexKey(farmID: farmID, eidRaw: eid)]
    }

    func animalProfileAnyFarm(eidRaw: String) -> AnimalProfile? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return animalProfileAnyFarmIndex[eid]
    }

    func searchAnimalsAnyFarm(query: String, limit: Int = 30) -> [AnimalProfile] {
        let q = EIDValidator.cleanedRaw(query)
        guard !q.isEmpty, q != "—" else { return [] }

        return animalSearchIndex
            .filter { $0.eidRaw.contains(q) }
            .map(\.profile)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    // =========================================================
    // MARK: - Updates
    // =========================================================

    func updateAnimalSex(farmID: UUID, eidRaw: String, sex: Sex?) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        animals[idx].sex = sex
        animals[idx].updatedAt = Date()
        rebuildIndexes()
        scheduleSave()
    }

    func updateAnimalClass(farmID: UUID, eidRaw: String, animalClass: AnimalClass?) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        animals[idx].animalClass = animalClass
        animals[idx].klass = animalClass?.rawValue
        animals[idx].updatedAt = Date()
        rebuildIndexes()
        scheduleSave()
    }

    func updateAnimalBreedIfBlank(farmID: UUID, eidRaw: String, breed: String) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        let b = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return }
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }

        let existing = animals[idx].breed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }

        animals[idx].breed = b
        animals[idx].updatedAt = Date()
        rebuildIndexes()
        scheduleSave()
    }

    func isMixedMobSession(_ sessionID: UUID) -> Bool {
        sessionDefaultMobName[sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines)
            == SessionSetupMobStepView.mixedSentinel
    }

    func updateAnimalBirthYearIfBlank(farmID: UUID, eidRaw: String, year: Int) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        guard animals[idx].birthYear == nil else { return }
        animals[idx].birthYear = year
        animals[idx].updatedAt = Date()
        rebuildIndexes()
        scheduleSave()
    }

    func updateAnimalBirthMonthIfBlank(farmID: UUID, eidRaw: String, month: Int) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard (1...12).contains(month) else { return }
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        guard animals[idx].birthMonth == nil else { return }
        animals[idx].birthMonth = month
        animals[idx].updatedAt = Date()
        rebuildIndexes()
        scheduleSave()
    }

    func updateAnimalStatusIfBlank(farmID: UUID, eidRaw: String, status: AnimalStatus) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        if animals[idx].status == nil {
            animals[idx].status = status
            animals[idx].updatedAt = Date()
            rebuildIndexes()
            scheduleSave()
        }
    }

    func updateAnimalNotes(
        farmID: UUID,
        eidRaw: String,
        comments: String?,
        userField1: String?,
        userField2: String?
    ) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }

        let trimmedComments = comments?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser1 = userField1?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser2 = userField2?.trimmingCharacters(in: .whitespacesAndNewlines)

        animals[idx].comments = (trimmedComments?.isEmpty == true) ? nil : trimmedComments
        animals[idx].userField1 = (trimmedUser1?.isEmpty == true) ? nil : trimmedUser1
        animals[idx].userField2 = (trimmedUser2?.isEmpty == true) ? nil : trimmedUser2
        animals[idx].updatedAt = Date()

        rebuildIndexes()
        scheduleSave()
    }

    // =========================================================
    // MARK: - Resolvers
    // =========================================================

    func resolvedSexForScan(sessionID: UUID, farmID: UUID, eidRaw: String) -> Sex? {
        if let programmed = programmedAssignment(for: farmID, eidRaw: eidRaw)?.sex { return programmed }

        let existing = animalProfile(farmID: farmID, eidRaw: eidRaw)
        let overwrite = overwriteSexEnabled(for: sessionID)

        if overwrite { return defaultSex(for: sessionID) }
        if let existingSex = existing?.sex { return existingSex }
        return defaultSex(for: sessionID)
    }

    func resolvedClassForScan(sessionID: UUID, farmID: UUID, eidRaw: String) -> AnimalClass? {
        if let programmed = programmedAssignment(for: farmID, eidRaw: eidRaw)?.animalClass { return programmed }

        let existing = animalProfile(farmID: farmID, eidRaw: eidRaw)
        let overwrite = overwriteClassEnabled(for: sessionID)

        if overwrite { return defaultClass(for: sessionID) }
        if let existingClass = existing?.animalClass { return existingClass }

        if existing != nil { return .flock }
        return defaultClass(for: sessionID)
    }

    private var defaultImportedMobColorHex: String { "#4CAF50" }

    func resolvedMobIDForScan(sessionID: UUID, farmID: UUID, eidRaw: String) -> UUID? {
        let existing = animalProfile(farmID: farmID, eidRaw: eidRaw)
        let overwrite = overwriteMobEnabled(for: sessionID)

        let mobName = defaultMobName(for: sessionID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if mobName == SessionSetupMobStepView.mixedSentinel {
            return existing?.mobID
        }

        if !overwrite, let existingMob = existing?.mobID {
            return existingMob
        }

        guard !mobName.isEmpty else {
            return existing?.mobID
        }

        let mobLookupKey = "\(farmID.uuidString)|\(mobName.lowercased())"
        if let mobID = mobIDByFarmAndNameIndex[mobLookupKey] {
            return mobID
        }

        let created = addMob(farmID: farmID, name: mobName, colorHex: defaultImportedMobColorHex)
        return created.id
    }

    func mobForEID(_ eidRaw: String, farmID: UUID? = nil) -> Mob? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }

        let profile: AnimalProfile? = {
            if let farmID {
                return animalProfile(farmID: farmID, eidRaw: eid)
            } else {
                return animalProfileAnyFarm(eidRaw: eid)
            }
        }()

        guard let mobID = profile?.mobID else { return nil }
        return mobByIDIndex[mobID]
    }

    func mobColorHexForEID(_ eidRaw: String, farmID: UUID? = nil) -> String? {
        mobForEID(eidRaw, farmID: farmID)?.colorHex
    }

    func animalDuplicateCountForImport(csvText: String) -> Int {
        let parsed = CSVAnimalImporter.parseAnimalsCSV(csvText: csvText)
        var count = 0

        for row in parsed.rows {
            guard let farmID = resolveFarmIDForImport(
                pic: row.farmPIC,
                farmName: row.farmName
            ) else { continue }

            if animalProfile(farmID: farmID, eidRaw: row.eid) != nil {
                count += 1
            }
        }

        return count
    }
    
    func lambingEventsForAnimal(farmID: UUID, eidRaw: String) -> [AnimalEvent] {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return [] }
        return lambingEventsByAnimalIndex[animalIndexKey(farmID: farmID, eidRaw: eid)] ?? []
    }

    @discardableResult
    func importHistoricalPregCSV(
        csvText: String,
        farmID: UUID? = nil,
        duplicateAction: DuplicateImportAction = .skip,
        progress: ((Int, Int) -> Void)? = nil
    ) -> HistoricalImportResult {
        withDeferredSave {
            let parsed = CSVAnimalImporter.parseHistoricalPregCSV(csvText: csvText)

            guard !parsed.rows.isEmpty else {
                progress?(0, 0)
                return HistoricalImportResult(
                    imported: 0,
                    unmatched: 0,
                    skipped: parsed.skippedRows,
                    duplicatesSkipped: 0,
                    replaced: 0
                )
            }

            let total = parsed.rows.count

            // Existing lambing events by unique key: farm|eid|year
            var existingLambingKeys = Set<String>()
            for event in animalEvents where event.kind == .lambing {
                let year = event.int1 ?? Calendar.current.component(.year, from: event.date)
                let key = "\(event.farmID.uuidString)|\(EIDValidator.cleanedRaw(event.eidRaw))|\(year)"
                existingLambingKeys.insert(key)
            }

            var imported = 0
            var unmatched = 0
            var duplicatesSkipped = 0
            var replaced = 0

            struct PendingLambingRow {
                let profile: AnimalProfile
                let year: Int
                let lambNumber: Int?
                let key: String
            }

            var rowsToWrite: [PendingLambingRow] = []
            rowsToWrite.reserveCapacity(parsed.rows.count)

            var keysToRemove = Set<String>()

            for (index, row) in parsed.rows.enumerated() {
                if index == 0 || index % 25 == 0 || index == total - 1 {
                    let scaledCompleted = Int((Double(index + 1) / Double(max(total, 1))) * 70.0)
                    progress?(scaledCompleted, 100)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                }

                let importedEID = EIDValidator.cleanedRaw(row.eid)
                guard !importedEID.isEmpty, importedEID != "—" else { continue }

                let matchedProfile: AnimalProfile? = {
                    if let farmID {
                        return animalProfile(farmID: farmID, eidRaw: importedEID)
                    } else {
                        return animalProfileAnyFarm(eidRaw: importedEID)
                    }
                }()

                guard let profile = matchedProfile else {
                    unmatched += 1
                    continue
                }

                let key = "\(profile.farmID.uuidString)|\(normalizedImportEID(profile.eidRaw))|\(row.year)"
                let alreadyExists = existingLambingKeys.contains(key)

                if alreadyExists {
                    switch duplicateAction {
                    case .skip:
                        duplicatesSkipped += 1
                        continue

                    case .replace:
                        keysToRemove.insert(key)
                        replaced += 1
                    }
                }

                rowsToWrite.append(
                    PendingLambingRow(
                        profile: profile,
                        year: row.year,
                        lambNumber: row.lambNumber,
                        key: key
                    )
                )

                imported += 1
            }

            progress?(75, 100)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))

            if !keysToRemove.isEmpty {
                animalEvents.removeAll { event in
                    guard event.kind == .lambing else { return false }
                    let year = event.int1 ?? Calendar.current.component(.year, from: event.date)
                    let key = "\(event.farmID.uuidString)|\(EIDValidator.cleanedRaw(event.eidRaw))|\(year)"
                    return keysToRemove.contains(key)
                }
            }

            progress?(80, 100)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))

            for (writeIndex, item) in rowsToWrite.enumerated() {
                addLambingEvent(
                    farmID: item.profile.farmID,
                    eidRaw: item.profile.eidRaw,
                    year: item.year,
                    born: item.lambNumber,
                    weaned: nil,
                    notes: "Historical preg import"
                )

                existingLambingKeys.insert(item.key)

                if writeIndex == 0 || writeIndex % 25 == 0 || writeIndex == rowsToWrite.count - 1 {
                    let writeProgress = 80 + Int((Double(writeIndex + 1) / Double(max(rowsToWrite.count, 1))) * 12.0)
                    progress?(writeProgress, 100)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                }
            }

            var latestImportedByAnimal: [String: (year: Int, lambNumber: Int?)] = [:]

            for item in rowsToWrite {
                let animalKey = "\(item.profile.farmID.uuidString)|\(normalizedImportEID(item.profile.eidRaw))"

                if let existing = latestImportedByAnimal[animalKey] {
                    if item.year > existing.year {
                        latestImportedByAnimal[animalKey] = (item.year, item.lambNumber)
                    }
                } else {
                    latestImportedByAnimal[animalKey] = (item.year, item.lambNumber)
                }
            }

            progress?(94, 100)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))

            for (animalIndex, entry) in latestImportedByAnimal.enumerated() {
                let (animalKey, latest) = entry

                guard let idx = animals.firstIndex(where: {
                    "\($0.farmID.uuidString)|\(normalizedImportEID($0.eidRaw))" == animalKey
                }) else { continue }

                animals[idx].lambsPerYear = latest.lambNumber
                animals[idx].updatedAt = Date()

                if animalIndex == 0 || animalIndex % 25 == 0 || animalIndex == latestImportedByAnimal.count - 1 {
                    let updateProgress = 94 + Int((Double(animalIndex + 1) / Double(max(latestImportedByAnimal.count, 1))) * 4.0)
                    progress?(updateProgress, 100)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                }
            }

            progress?(99, 100)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))

            rebuildIndexes()
            scheduleSave()

            progress?(100, 100)
            return HistoricalImportResult(
                imported: imported,
                unmatched: unmatched,
                skipped: parsed.skippedRows,
                duplicatesSkipped: duplicatesSkipped,
                replaced: replaced
            )
        }
    }
    private func resolveFarmIDForImport(pic: String?, farmName: String?) -> UUID? {
        if let pic {
            let cleanPIC = pic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !cleanPIC.isEmpty, let id = farmIDByPICIndex[cleanPIC] {
                return id
            }
        }

        if let farmName {
            let cleanFarm = farmName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !cleanFarm.isEmpty, let id = farmIDByNameIndex[cleanFarm] {
                return id
            }
        }

        return nil
    }
    func historicalPregDuplicateCountForImport(
        csvText: String,
        farmID: UUID? = nil
    ) -> Int {
        let parsed = CSVAnimalImporter.parseHistoricalPregCSV(csvText: csvText)
        guard !parsed.rows.isEmpty else { return 0 }

        let profilesByFarmAndEID: [String: AnimalProfile] = Dictionary(
            uniqueKeysWithValues: animals.map { animal in
                (
                    "\(animal.farmID.uuidString)|\(normalizedImportEID(animal.eidRaw))",
                    animal
                )
            }
        )

        var profilesByAnyEID: [String: AnimalProfile] = [:]
        for animal in animals {
            let eid = normalizedImportEID(animal.eidRaw)
            if profilesByAnyEID[eid] == nil {
                profilesByAnyEID[eid] = animal
            }
        }

        let existingLambingKeys: Set<String> = Set(
            animalEvents.compactMap { event in
                guard event.kind == .lambing else { return nil }
                let year = event.int1 ?? Calendar.current.component(.year, from: event.date)
                return "\(event.farmID.uuidString)|\(normalizedImportEID(event.eidRaw))|\(year)"
            }
        )

        var count = 0

        for row in parsed.rows {
            let importedEID = EIDValidator.cleanedRaw(row.eid)
            guard !importedEID.isEmpty, importedEID != "—" else { continue }

            let matchedProfile: AnimalProfile? = {
                if let farmID {
                    return profilesByFarmAndEID["\(farmID.uuidString)|\(importedEID)"]
                } else {
                    return profilesByAnyEID[importedEID]
                }
            }()

            guard let profile = matchedProfile else { continue }

            let lambingKey = "\(profile.farmID.uuidString)|\(EIDValidator.cleanedRaw(profile.eidRaw))|\(row.year)"
            if existingLambingKeys.contains(lambingKey) {
                count += 1
            }
        }

        return count
    }
    func normalizeAllStoredEIDs() {
        withDeferredSave {
            for i in animals.indices {
                animals[i].eidRaw = EIDValidator.cleanedRaw(animals[i].eidRaw)
                animals[i].updatedAt = Date()
            }

            for i in records.indices {
                records[i].eidRaw = EIDValidator.cleanedRaw(records[i].eidRaw)
            }

            for i in animalEvents.indices {
                animalEvents[i].eidRaw = EIDValidator.cleanedRaw(animalEvents[i].eidRaw)
            }

            var normalizedTags: [UUID: [String: ProgrammedTagAssignment]] = [:]
            for (farmID, tagMap) in programmedTags {
                var newMap: [String: ProgrammedTagAssignment] = [:]
                for (eid, assignment) in tagMap {
                    newMap[EIDValidator.cleanedRaw(eid)] = assignment
                }
                normalizedTags[farmID] = newMap
            }
            programmedTags = normalizedTags

            for i in soldArchive.indices {
                soldArchive[i].eidRaw = EIDValidator.cleanedRaw(soldArchive[i].eidRaw)
            }

            rebuildIndexes()
            scheduleSave()
        }
    }
    
    // =========================================================
    // MARK: - CSV Export (animals)
    // =========================================================

    func exportAnimalsCSV(farmID: UUID, includeHeader: Bool = true) -> String {
        let header = [
            "eid",
            "mob",
            "lambsPerYear",
            "fleeceWeightKg",
            "stapleLengthMm",
            "class",
            "comments",
            "user1",
            "user2"
        ]

        let farmMobsByID: [UUID: Mob] = Dictionary(uniqueKeysWithValues: mobs(for: farmID).map { ($0.id, $0) })

        let rows: [[String]] = animals
            .filter { $0.farmID == farmID }
            .sorted { $0.eidRaw < $1.eidRaw }
            .map { a in
                let mobName: String = {
                    guard let mid = a.mobID, let m = farmMobsByID[mid] else { return "" }
                    return m.name
                }()

                let klassText: String = {
                    if let ac = a.animalClass { return ac.rawValue }
                    if let k = a.klass { return k }
                    return ""
                }()

                return [
                    a.eidRaw,
                    mobName,
                    a.lambsPerYear.map(String.init) ?? "",
                    a.fleeceWeightKg.map { Self.csvNumber($0) } ?? "",
                    a.stapleLengthMm.map { Self.csvNumber($0) } ?? "",
                    klassText,
                    a.comments ?? "",
                    a.userField1 ?? "",
                    a.userField2 ?? ""
                ]
            }

        var out: [String] = []
        out.reserveCapacity(rows.count + 1)

        if includeHeader {
            out.append(header.map(Self.csvEscape).joined(separator: ","))
        }

        for r in rows {
            out.append(r.map(Self.csvEscape).joined(separator: ","))
        }

        return out.joined(separator: "\n")
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func csvNumber(_ d: Double) -> String {
        let s = String(format: "%.3f", d)
        var t = s
        while t.contains(".") && (t.hasSuffix("0") || t.hasSuffix(".")) {
            t.removeLast()
        }
        return t
    }

    // =========================================================
    // MARK: - CSV helpers
    // =========================================================

    private func parseCSVRow(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false

        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if c == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    cur.append("\"")
                    i += 2
                    continue
                } else {
                    inQuotes.toggle()
                    i += 1
                    continue
                }
            }

            if c == "," && !inQuotes {
                out.append(cur)
                cur = ""
                i += 1
                continue
            }

            cur.append(c)
            i += 1
        }

        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func normalizeCSVHeader(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func normalizedImportEID(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }

    private func alternateImportEIDForms(_ raw: String) -> [String] {
        let base = normalizedImportEID(raw)
        guard !base.isEmpty else { return [] }

        var forms: [String] = [base]

        if base.count > 12 {
            let dropped3 = String(base.dropFirst(3))
            if !dropped3.isEmpty {
                forms.append(dropped3)
            }
        }

        return Array(Set(forms))
    }

    private func animalProfileAnyFarmMatchingImportedEID(_ raw: String) -> AnimalProfile? {
        let forms = alternateImportEIDForms(raw)
        guard !forms.isEmpty else { return nil }

        return animals.first(where: { profile in
            let stored = normalizedImportEID(profile.eidRaw)
            return forms.contains(stored)
        })
    }

    private func animalProfileMatchingImportedEID(farmID: UUID, raw: String) -> AnimalProfile? {
        let forms = alternateImportEIDForms(raw)
        guard !forms.isEmpty else { return nil }

        return animals.first(where: { profile in
            guard profile.farmID == farmID else { return false }
            let stored = normalizedImportEID(profile.eidRaw)
            return forms.contains(stored)
        })
    }

    private func parseAnimalClass(from text: String?) -> AnimalClass? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let key = t.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        if let direct = AnimalClass(rawValue: key) { return direct }

        switch key {
        case "studreserve", "studres", "reserve":
            return .studReserve
        case "flock", "mainflock":
            return .flock
        case "cull", "culls":
            return .cull
        case "stud", "ramstud":
            return .stud
        default:
            return nil
        }
    }
}

// =========================================================
// MARK: - Safe indexing helper
// =========================================================

fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

