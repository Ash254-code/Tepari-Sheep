// LocalDataStore.swift
import Foundation
import Combine
import SwiftUI

@MainActor
final class LocalDataStore: ObservableObject {

    // =========================================================
    // MARK: - Persistence (core data snapshot)
    // =========================================================

    private struct Snapshot: Codable {
        var schemaVersion: Int

        // Core
        var sessions: [Session]
        var records: [AnimalRecord]

        // Wizard/session config + runtime state
        var sessionConfigs: [UUID: SessionConfig]
        var sessionTreatments: [UUID: [SessionTreatment]]

        // Per-session selections / defaults / overwrites
        var sessionFarmID: [UUID: UUID]
        var sessionMobID: [UUID: UUID]

        var sessionDefaultSex: [UUID: Sex]
        var sessionDefaultClass: [UUID: AnimalClass]
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
        var farms: [Farm]
        var mobs: [Mob]
        var animals: [AnimalProfile]

        // Lifetime animal history (v1 files may not include this, so keep optional)
        var animalEvents: [AnimalEvent]? = nil

        // Programmed tags + sold archive
        var programmedTags: [UUID: [String: ProgrammedTagAssignment]]
        var soldArchive: [SoldAnimal]

        init(
            schemaVersion: Int = 1,
            sessions: [Session] = [],
            records: [AnimalRecord] = [],
            sessionConfigs: [UUID: SessionConfig] = [:],
            sessionTreatments: [UUID: [SessionTreatment]] = [:],
            sessionFarmID: [UUID: UUID] = [:],
            sessionMobID: [UUID: UUID] = [:],
            sessionDefaultSex: [UUID: Sex] = [:],
            sessionDefaultClass: [UUID: AnimalClass] = [:],
            sessionDefaultMobName: [UUID: String] = [:],

            // ✅ NEW defaults
            sessionDefaultBreed: [UUID: String]? = nil,
            sessionDefaultBirthYear: [UUID: Int]? = nil,
            sessionDefaultBirthMonth: [UUID: Int]? = nil,
            sessionDefaultStatus: [UUID: AnimalStatus]? = nil,

            sessionOverwriteSex: [UUID: Bool] = [:],
            sessionOverwriteClass: [UUID: Bool] = [:],
            sessionOverwriteMob: [UUID: Bool] = [:],
            farms: [Farm] = [],
            mobs: [Mob] = [],
            animals: [AnimalProfile] = [],
            animalEvents: [AnimalEvent]? = nil,
            programmedTags: [UUID: [String: ProgrammedTagAssignment]] = [:],
            soldArchive: [SoldAnimal] = []
        ) {
            self.schemaVersion = schemaVersion
            self.sessions = sessions
            self.records = records

            self.sessionConfigs = sessionConfigs
            self.sessionTreatments = sessionTreatments

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
        }
    }

    // ✅ Keep the schema version the same; we used OPTIONAL new keys for backwards-compat.
    private let snapshotSchemaVersion = 1
    private var saveTask: Task<Void, Never>? = nil
    private var isLoadingSnapshot: Bool = false

    private func scheduleSave() {
        guard !isLoadingSnapshot else { return }

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

        saveTask = Task.detached(priority: .utility) {
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

    private func buildSnapshot() -> Snapshot {
        Snapshot(
            schemaVersion: snapshotSchemaVersion,
            sessions: sessions,
            records: records,
            sessionConfigs: sessionConfigs,
            sessionTreatments: sessionTreatments,
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
            soldArchive: soldArchive
        )
    }

    private func applySnapshot(_ snap: Snapshot) {
        guard snap.schemaVersion == snapshotSchemaVersion else { return }

        sessions = snap.sessions
        records = snap.records

        sessionConfigs = snap.sessionConfigs
        sessionTreatments = snap.sessionTreatments

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

            let snap = try dec.decode(Snapshot.self, from: data)
            applySnapshot(snap)
        } catch {
            // If decode fails, keep app usable; optionally quarantine the bad file.
            do {
                let url = try snapshotURL()
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let bad = url.deletingLastPathComponent().appendingPathComponent("localDataStore_corrupt_\(stamp).json")
                    try? fm.moveItem(at: url, to: bad)
                }
            } catch { /* ignore */ }
        }
    }
    private func loadAnimalEventsFromDisk() {
        do {
            let url = try animalEventsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                animalEvents = []
                return
            }

            let data = try Data(contentsOf: url)

            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            animalEvents = try dec.decode([AnimalEvent].self, from: data)
        } catch {
            animalEvents = []
        }
    }

    private func saveAnimalEventsToDisk(_ events: [AnimalEvent]) {
        let url: URL

        do {
            url = try animalEventsURL()
        } catch {
            return
        }

        Task.detached(priority: .utility) {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                enc.dateEncodingStrategy = .iso8601

                let data = try enc.encode(events)
                try data.write(to: url, options: [.atomic])
            } catch {
                // ignore
            }
        }
    }   // =========================================================
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

        if let index = records.firstIndex(where: {
            $0.sessionID == sessionID && $0.eidRaw == eid
        }) {
            // ✅ Update existing record
            var rec = records[index]
            var traits = rec.customTraits ?? [:]
            traits["pregFetusCount"] = String(fetusCount)
            rec.customTraits = traits
            rec.draftResult = draftPosition
            records[index] = rec
        } else {
            // ✅ Create new record
            var traits: [String: String] = [:]
            traits["pregFetusCount"] = String(fetusCount)

            let newRecord = AnimalRecord(
                sessionID: sessionID,
                eidRaw: eid,
                lockedWeight: 0,
                treatments: [],
                draftResult: draftPosition,   // ✅ move up
                customTraits: traits          // ✅ move down
            )
            records.insert(newRecord, at: 0)
        }
        // ✅ ALSO write-through into lifetime history + cached profile
        if let farmID = resolvedFarmIDForEvent(sessionID: sessionID) {

            let status: String = (fetusCount == 0) ? "Empty" : "Pregnant"

            // record lifetime pregnancy event (persists outside the session)
            addPregnancyEvent(
                farmID: farmID,
                eidRaw: eid,
                status: status,
                fetusCount: fetusCount,
                method: "Scan",
                notes: nil,
                at: Date()
            )

            // OPTIONAL: update cached lambsPerYear so AnimalDataView shows it immediately
            if var p = animalProfile(farmID: farmID, eidRaw: eid) {
                p.lambsPerYear = fetusCount
                upsertAnimal(p)
            }
        }
        // ✅ Write-through into lifetime history (per-year lamb count)
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

            let year = Calendar.current.component(.year, from: Date())
            addLambingEvent(
                farmID: farmID,
                eidRaw: eid,
                year: year,
                born: fetusCount,   // ✅ store 0/1/2 for this year
                weaned: nil,
                notes: "Preg test"
            )
        }
        scheduleSave()   // ✅ persists using your existing save system
    }

    // =========================================================
    // MARK: - Lifetime animal history
    // =========================================================

    @Published private(set) var animalEvents: [AnimalEvent] = []
    // =========================================================
    // MARK: - Lifetime event helpers
    // =========================================================

    /// Adds an event, with optional de-dupe on (farmID+eid+kind+date).
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
                scheduleSave()
                return event
            }
        }

        animalEvents.insert(event, at: 0)
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

        // Use Jan 1 of that year as a stable “anchor date” for yearly lambing summary.
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
        return appendAnimalEvent(e, dedupe: false) // allow multiple treatments same day
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
        return animalEvents
            .filter { ev in
                ev.kind == .weight &&
                ev.eidRaw == eid &&
                (farmID == nil || ev.farmID == farmID!)
            }
            .sorted { $0.date > $1.date }
            .first
    }

    func latestPregnancyEvent(farmID: UUID?, eidRaw: String) -> AnimalEvent? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }
        return animalEvents
            .filter { ev in
                ev.kind == .pregnancy &&
                ev.eidRaw == eid &&
                (farmID == nil || ev.farmID == farmID!)
            }
            .sorted { $0.date > $1.date }
            .first
    }

    func lambCountForYear(farmID: UUID?, eidRaw: String, year: Int) -> Int? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard !eid.isEmpty, eid != "—" else { return nil }

        // anchor date matches addLambingEvent (Jan 1 of year)
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        let anchor = Calendar.current.date(from: comps)

        let ev = animalEvents.first(where: { e in
            e.kind == .lambing &&
            e.eidRaw == eid &&
            (farmID == nil || e.farmID == farmID!) &&
            (anchor == nil || e.date == anchor!) &&
            e.int1 == year
        })

        if let s = ev?.json?["born"], let n = Int(s) { return n }
        return nil
    }

    func lambCountForCurrentYear(farmID: UUID?, eidRaw: String) -> Int? {
        let year = Calendar.current.component(.year, from: Date())
        return lambCountForYear(farmID: farmID, eidRaw: eidRaw, year: year)
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
        // ✅ Tepari dosing gun (controls "G" connectivity pill + connection prompt)
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
    // (UNCHANGED - keep your existing code)
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
    // (UNCHANGED - keep your existing code)
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
        // Settings: load from UserDefaults (keep as-is)
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
        
        // Core data snapshot: load from disk
        loadSnapshotFromDisk()
        loadAnimalEventsFromDisk()
    }

    // =========================================================
    // MARK: - Treatment library helpers
    // =========================================================
    // (UNCHANGED)
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
    // (UNCHANGED)
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
    // MARK: - Session Treatments (apply to all animals scanned in a session)
    // =========================================================

    @Published private(set) var sessionTreatments: [UUID: [SessionTreatment]] = [:]

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
    // MARK: - Session defaults (Sex / Class / Mob / NEW fields) + Overwrite toggles
    // =========================================================

    @Published private(set) var sessionDefaultSex: [UUID: Sex] = [:]
    @Published private(set) var sessionDefaultClass: [UUID: AnimalClass] = [:]
    @Published private(set) var sessionDefaultMobName: [UUID: String] = [:]

    // ✅ NEW defaults
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
            // Mixed is allowed here as a session-level sentinel.
            // It must never be turned into a real mob.
            sessionDefaultMobName[sessionID] = trimmed
        }

        scheduleSave()
    }

    // ✅ NEW defaults getters/setters

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

        // Mixed must never allow mob overwrite.
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
    // MARK: - Programmed Tags (multi-field overrides)
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

        // ✅ NEW (cached fields)
        var breed: String?
        var birthYear: Int?
        var birthMonth: Int?
        var status: AnimalStatus?

        // NOTE: these are “latest/cached” values (history lives in animalEvents)
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

            // ✅ NEW
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

    // =========================================================
    // MARK: - Sale archive (optional audit trail)
    // =========================================================
    // (UNCHANGED)
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
    // (UNCHANGED - keep your existing code)
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
            scheduleSave()
            return true
        }

        guard let idx = animals.firstIndex(where: { $0.eidRaw == eid }) else { return false }
        let fromFarm = animals[idx].farmID
        animals.remove(at: idx)
        soldArchive.insert(SoldAnimal(eidRaw: eid, fromFarmID: fromFarm, soldAt: soldAt, reference: reference), at: 0)
        scheduleSave()
        return true
    }

    // =========================================================
    // MARK: - Session-driven helpers
    // =========================================================
    // (UNCHANGED)
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
    // (UNCHANGED)
    // =========================================================

    func animalCountForSession(sessionID: UUID) -> Int {
        let eids = Set(records.filter { $0.sessionID == sessionID }.map { $0.eidRaw })
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
    // (UNCHANGED)
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

        // Build ordered session type string (exclude Scan)
        var types: [String] = []

        if sessionTypes.contains(.weigh) { types.append("Weigh") }
        if sessionTypes.contains(.draft) { types.append("Draft") }
        if sessionTypes.contains(.treatment) { types.append("Treat") }

        let typeText = types.isEmpty ? "General" : types.joined(separator: "/")

        // No mob yet at creation
        let mobText = "—"

        // No animals yet
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
    // (UNCHANGED, with NEW clears added below)
    // =========================================================

    func forceReseedDemoData() {
        resetAllData()

        let greenwood = addFarm(name: "Greenwood Park", pic: "SA12345")
        let mahanewo  = addFarm(name: "Mahanewo", pic: "SA54321")

        let mobNames = ["Blue", "Green", "Black", "Yellow", "Red"]

        seedMobsAndAnimals(for: greenwood, mobNames: mobNames, farmSeed: 12345)
        seedMobsAndAnimals(for: mahanewo,  mobNames: mobNames, farmSeed: 54321)

        scheduleSave()
    }

    func resetAllData() {
        sessions.removeAll()
        records.removeAll()

        sessionConfigs.removeAll()
        sessionTreatments.removeAll()

        sessionFarmID.removeAll()
        sessionMobID.removeAll()

        sessionDefaultSex.removeAll()
        sessionDefaultClass.removeAll()
        sessionDefaultMobName.removeAll()

        // ✅ NEW defaults
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

        scheduleSave()
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
    // (UNCHANGED)
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
    // (UNCHANGED)
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
        scheduleSave()
        return rec
    }

    func addOrOverwriteRecord(sessionID: UUID, eidRaw: String, lockedWeight: Double, treatments: [SessionTreatment]) {
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

        // ✅ Write-through into lifetime history
        guard let farmID = resolvedFarmIDForEvent(sessionID: sessionID) else { return }

        // Weight event (only if non-zero; change this rule if you want zeros kept)
        if rec.lockedWeight > 0 {
            addWeightEvent(farmID: farmID, eidRaw: rec.eidRaw, weightKg: rec.lockedWeight, at: rec.recordedAt)
        }

        // Treatment events (one per applied treatment)
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

        // Always last seen
        addLastSeenEvent(farmID: farmID, eidRaw: rec.eidRaw, at: rec.recordedAt, sessionID: sessionID)
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

    func records(for sessionID: UUID) -> [AnimalRecord] {
        records
            .filter { $0.sessionID == sessionID }
            .sorted { $0.recordedAt > $1.recordedAt }
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
        return records
            .filter { $0.eidRaw == eid }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        records.removeAll { $0.sessionID == session.id }

        sessionConfigs.removeValue(forKey: session.id)

        sessionFarmID.removeValue(forKey: session.id)
        sessionMobID.removeValue(forKey: session.id)
        sessionDefaultSex.removeValue(forKey: session.id)
        sessionDefaultClass.removeValue(forKey: session.id)
        sessionDefaultMobName.removeValue(forKey: session.id)

        // ✅ NEW defaults
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

        scheduleSave()
    }

    // =========================================================
    // MARK: - Farms
    // =========================================================
    // (UNCHANGED)
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

        // Also remove events tied to that farm (keeps things consistent)
        animalEvents.removeAll { $0.farmID == farmID }

        scheduleSave()
    }

    // =========================================================
    // MARK: - Mobs
    // =========================================================
    // (UNCHANGED)
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
        scheduleSave()
    }

    func mobs(for farmID: UUID) -> [Mob] {
        mobs.filter { $0.farmID == farmID }
    }

    // =========================================================
    // MARK: - Session editing helpers
    // =========================================================
    // (UNCHANGED)
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

    func upsertAnimal(_ profile: AnimalProfile) {
        let eid = EIDValidator.cleanedRaw(profile.eidRaw)

        if let idx = animals.firstIndex(where: { $0.farmID == profile.farmID && $0.eidRaw == eid }) {
            var copy = profile
            copy.eidRaw = eid

            if let ac = copy.animalClass {
                copy.klass = ac.rawValue
            } else if let klass = copy.klass, let ac = AnimalClass(rawValue: klass) {
                copy.animalClass = ac
            }

            // normalize breed
            if let b = copy.breed {
                let t = b.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.breed = t.isEmpty ? nil : t
            }

            copy.updatedAt = Date()
            animals[idx] = copy
        } else {
            var copy = profile
            copy.eidRaw = eid

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
            animals.insert(copy, at: 0)
        }

        scheduleSave()
    }

    func animalProfile(farmID: UUID, eidRaw: String) -> AnimalProfile? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return animals.first(where: { $0.farmID == farmID && $0.eidRaw == eid })
    }

    func animalProfileAnyFarm(eidRaw: String) -> AnimalProfile? {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        return animals.first(where: { $0.eidRaw == eid })
    }

    func searchAnimalsAnyFarm(query: String, limit: Int = 30) -> [AnimalProfile] {
        let q = EIDValidator.cleanedRaw(query)
        guard !q.isEmpty, q != "—" else { return [] }
        return animals
            .filter { $0.eidRaw.contains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    // =========================================================
    // MARK: - Updates (Sex / Class / Notes / NEW fields)
    // =========================================================

    func updateAnimalSex(farmID: UUID, eidRaw: String, sex: Sex?) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        animals[idx].sex = sex
        animals[idx].updatedAt = Date()
        scheduleSave()
    }

    func updateAnimalClass(farmID: UUID, eidRaw: String, animalClass: AnimalClass?) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        animals[idx].animalClass = animalClass
        animals[idx].klass = animalClass?.rawValue
        animals[idx].updatedAt = Date()
        scheduleSave()
    }

    // ✅ NEW “blank-fill” updaters used by SessionViewModel.applyAnimalDefaults

    func updateAnimalBreedIfBlank(farmID: UUID, eidRaw: String, breed: String) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        let b = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return }
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }

        let existing = animals[idx].breed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }

        animals[idx].breed = b
        animals[idx].updatedAt = Date()
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
        scheduleSave()
    }

    func updateAnimalBirthMonthIfBlank(farmID: UUID, eidRaw: String, month: Int) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard (1...12).contains(month) else { return }
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        guard animals[idx].birthMonth == nil else { return }
        animals[idx].birthMonth = month
        animals[idx].updatedAt = Date()
        scheduleSave()
    }

    func updateAnimalStatusIfBlank(farmID: UUID, eidRaw: String, status: AnimalStatus) {
        let eid = EIDValidator.cleanedRaw(eidRaw)
        guard let idx = animals.firstIndex(where: { $0.farmID == farmID && $0.eidRaw == eid }) else { return }
        if animals[idx].status == nil {
            animals[idx].status = status
            animals[idx].updatedAt = Date()
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

        animals[idx].comments = (comments?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : comments
        animals[idx].userField1 = (userField1?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : userField1
        animals[idx].userField2 = (userField2?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : userField2
        animals[idx].updatedAt = Date()

        scheduleSave()
    }

    // =========================================================
    // MARK: - Resolvers (Sex / Class / Mob for a scan)
    // =========================================================
    // (UNCHANGED)
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

    // NOTE: defaultImportedMobColorHex is used here too
    private var defaultImportedMobColorHex: String { "#4CAF50" }

    func resolvedMobIDForScan(sessionID: UUID, farmID: UUID, eidRaw: String) -> UUID? {
        let existing = animalProfile(farmID: farmID, eidRaw: eidRaw)
        let overwrite = overwriteMobEnabled(for: sessionID)

        let mobName = defaultMobName(for: sessionID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Mixed is session context only.
        // Existing animals keep their mob.
        // Animals with no mob stay nil.
        if mobName == SessionSetupMobStepView.mixedSentinel {
            return existing?.mobID
        }

        if !overwrite, let existingMob = existing?.mobID {
            return existingMob
        }

        guard !mobName.isEmpty else {
            return existing?.mobID
        }

        if let m = mobs.first(where: {
            $0.farmID == farmID && $0.name.caseInsensitiveCompare(mobName) == .orderedSame
        }) {
            return m.id
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
        return mobs.first(where: { $0.id == mobID })
    }
    func mobColorHexForEID(_ eidRaw: String, farmID: UUID? = nil) -> String? {
        mobForEID(eidRaw, farmID: farmID)?.colorHex
    }

    // =========================================================
    // MARK: - CSV Import (animals + historical preg)
    // =========================================================

    @discardableResult
    func importAnimalsCSV(farmID: UUID, csvText: String) -> (imported: Int, skipped: Int) {

        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else { return (0, 0) }

        let firstRow = parseCSVRow(rows[0]).map { normalizeCSVHeader($0) }
        let hasHeader = firstRow.contains("eid")

        let headers: [String]
        let startIndex: Int

        if hasHeader {
            headers = firstRow
            startIndex = 1
        } else {
            headers = [
                "eid",
                "mob",
                "lambsperyear",
                "fleeceweightkg",
                "staplelengthmm",
                "class",
                "comments",
                "user1",
                "user2"
            ]
            startIndex = 0
        }

        func value(_ key: String, from cols: [String]) -> String? {
            guard let idx = headers.firstIndex(of: key), let v = cols[safe: idx] else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        func parseInt(_ s: String?) -> Int? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Int(t)
        }

        func parseDouble(_ s: String?) -> Double? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Double(t)
        }

        var imported = 0
        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = value("eid", from: cols) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            let existing = animalProfile(farmID: farmID, eidRaw: eid)

            let mobName = value("mob", from: cols)
            let mobIDFromCSV: UUID? = {
                guard let mobName, !mobName.isEmpty else { return nil }

                if let existingMob = mobs.first(where: {
                    $0.farmID == farmID && $0.name.caseInsensitiveCompare(mobName) == .orderedSame
                }) {
                    return existingMob.id
                }

                return addMob(farmID: farmID, name: mobName, colorHex: defaultImportedMobColorHex).id
            }()

            let lambsFromCSV = parseInt(value("lambsperyear", from: cols))
            let fleeceFromCSV = parseDouble(value("fleeceweightkg", from: cols))
            let stapleFromCSV = parseDouble(value("staplelengthmm", from: cols))

            let classTextFromCSV = value("class", from: cols)
            let parsedClassFromCSV = parseAnimalClass(from: classTextFromCSV)

            let commentsFromCSV = value("comments", from: cols)
            let user1FromCSV = value("user1", from: cols)
            let user2FromCSV = value("user2", from: cols)

            let klassFromCSV: String? = {
                if let s = classTextFromCSV?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    return s
                }
                if let ac = parsedClassFromCSV {
                    return ac.rawValue
                }
                return nil
            }()

            let profile = AnimalProfile(
                id: existing?.id ?? UUID(),
                farmID: farmID,
                eidRaw: eid,
                mobID: mobIDFromCSV ?? existing?.mobID,
                sex: existing?.sex,
                animalClass: parsedClassFromCSV ?? existing?.animalClass,
                breed: existing?.breed,
                birthYear: existing?.birthYear,
                birthMonth: existing?.birthMonth,
                status: existing?.status,
                lambsPerYear: lambsFromCSV ?? existing?.lambsPerYear,
                fleeceWeightKg: fleeceFromCSV ?? existing?.fleeceWeightKg,
                stapleLengthMm: stapleFromCSV ?? existing?.stapleLengthMm,
                klass: klassFromCSV ?? existing?.klass,
                comments: commentsFromCSV ?? existing?.comments,
                userField1: user1FromCSV ?? existing?.userField1,
                userField2: user2FromCSV ?? existing?.userField2
            )

            upsertAnimal(profile)
            imported += 1
        }

        scheduleSave()
        return (imported, skipped)
    }

    @discardableResult
    func importAnimalsCSV(csvText: String) -> (imported: Int, skipped: Int) {

        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else { return (0, 0) }

        let firstRow = parseCSVRow(rows[0]).map { normalizeCSVHeader($0) }
        let hasHeader = firstRow.contains("eid")

        let headers: [String]
        let startIndex: Int

        if hasHeader {
            headers = firstRow
            startIndex = 1
        } else {
            headers = [
                "eid",
                "farm",
                "farmname",
                "pic",
                "farmpic",
                "mob",
                "lambsperyear",
                "fleeceweightkg",
                "staplelengthmm",
                "class",
                "comments",
                "user1",
                "user2"
            ]
            startIndex = 0
        }

        func value(_ keys: [String], from cols: [String]) -> String? {
            for key in keys {
                if let idx = headers.firstIndex(of: key), let v = cols[safe: idx] {
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
            return nil
        }

        func parseInt(_ s: String?) -> Int? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Int(t)
        }

        func parseDouble(_ s: String?) -> Double? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Double(t)
        }

        var imported = 0
        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = value(["eid"], from: cols) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            let rowPIC = value(["pic", "farmpic"], from: cols)
            let rowFarmName = value(["farm", "farmname"], from: cols)

            guard let resolvedFarmID = resolveFarmIDForImport(pic: rowPIC, farmName: rowFarmName) else {
                skipped += 1
                continue
            }

            let existing = animalProfile(farmID: resolvedFarmID, eidRaw: eid)

            let mobName = value(["mob"], from: cols)
            let mobIDFromCSV: UUID? = {
                guard let mobName, !mobName.isEmpty else { return nil }

                if let existingMob = mobs.first(where: {
                    $0.farmID == resolvedFarmID && $0.name.caseInsensitiveCompare(mobName) == .orderedSame
                }) {
                    return existingMob.id
                }

                return addMob(farmID: resolvedFarmID, name: mobName, colorHex: defaultImportedMobColorHex).id
            }()

            let lambsFromCSV = parseInt(value(["lambsperyear", "lambs"], from: cols))
            let fleeceFromCSV = parseDouble(value(["fleeceweightkg", "fleeceweight"], from: cols))
            let stapleFromCSV = parseDouble(value(["staplelengthmm", "staplelength"], from: cols))

            let classTextFromCSV = value(["class"], from: cols)
            let parsedClassFromCSV = parseAnimalClass(from: classTextFromCSV)

            let commentsFromCSV = value(["comments", "comment"], from: cols)
            let user1FromCSV = value(["user1"], from: cols)
            let user2FromCSV = value(["user2"], from: cols)

            let klassFromCSV: String? = {
                if let s = classTextFromCSV?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    return s
                }
                if let ac = parsedClassFromCSV {
                    return ac.rawValue
                }
                return nil
            }()

            let profile = AnimalProfile(
                id: existing?.id ?? UUID(),
                farmID: resolvedFarmID,
                eidRaw: eid,
                mobID: mobIDFromCSV ?? existing?.mobID,
                sex: existing?.sex,
                animalClass: parsedClassFromCSV ?? existing?.animalClass,
                breed: existing?.breed,
                birthYear: existing?.birthYear,
                birthMonth: existing?.birthMonth,
                status: existing?.status,
                lambsPerYear: lambsFromCSV ?? existing?.lambsPerYear,
                fleeceWeightKg: fleeceFromCSV ?? existing?.fleeceWeightKg,
                stapleLengthMm: stapleFromCSV ?? existing?.stapleLengthMm,
                klass: klassFromCSV ?? existing?.klass,
                comments: commentsFromCSV ?? existing?.comments,
                userField1: user1FromCSV ?? existing?.userField1,
                userField2: user2FromCSV ?? existing?.userField2
            )

            upsertAnimal(profile)
            imported += 1
        }

        scheduleSave()
        return (imported, skipped)
    }

    @discardableResult
    func importHistoricalPregCSV(
        csvText: String,
        farmID: UUID? = nil
    ) -> (imported: Int, unmatched: Int, skipped: Int) {

        let parsed = CSVAnimalImporter.parseHistoricalPregCSV(csvText: csvText)

        guard !parsed.rows.isEmpty else {
            return (0, 0, parsed.skippedRows)
        }

        var imported = 0
        var unmatched = 0
        let currentYear = Calendar.current.component(.year, from: Date())

        for row in parsed.rows {
            let eid = normalizedImportEID(row.eid)
            guard !eid.isEmpty, eid != "—" else {
                continue
            }

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

            addLambingEvent(
                farmID: profile.farmID,
                eidRaw: profile.eidRaw,
                year: row.year,
                born: row.lambNumber,
                weaned: nil,
                notes: "Historical preg import"
            )

            if row.year == currentYear,
               let idx = animals.firstIndex(where: {
                   $0.farmID == profile.farmID && normalizedImportEID($0.eidRaw) == normalizedImportEID(profile.eidRaw)
               }) {
                animals[idx].lambsPerYear = row.lambNumber
                animals[idx].updatedAt = Date()
            }

            imported += 1
        }

        scheduleSave()
        return (imported, unmatched, parsed.skippedRows)
    }
    private func resolveFarmIDForImport(pic: String?, farmName: String?) -> UUID? {

        if let pic {
            let cleanPIC = pic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanPIC.isEmpty,
               let match = farms.first(where: {
                   $0.pic.trimmingCharacters(in: .whitespacesAndNewlines)
                       .caseInsensitiveCompare(cleanPIC) == .orderedSame
               }) {
                return match.id
            }
        }

        if let farmName {
            let cleanFarm = farmName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanFarm.isEmpty,
               let match = farms.first(where: {
                   $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                       .caseInsensitiveCompare(cleanFarm) == .orderedSame
               }) {
                return match.id
            }
        }

        return nil
    }
    // =========================================================
    // MARK: - CSV Export (animals)
    // =========================================================
    // (UNCHANGED)
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
    private func normalizedImportEID(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }

    private func alternateImportEIDForms(_ raw: String) -> [String] {
        let base = normalizedImportEID(raw)
        guard !base.isEmpty else { return [] }

        var forms: [String] = [base]

        // Handle old data that may have lost the 3-digit NLIS prefix.
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
    private func normalizeCSVHeader(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
