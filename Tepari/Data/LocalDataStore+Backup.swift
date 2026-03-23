import Foundation

struct LocalDataStoreFullBackup: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var snapshot: LocalDataStoreSnapshot
    var animalEvents: [AnimalEvent]
    var yardsByFarmID: [UUID: [String]]
    var treatmentLibrary: [TreatmentTemplate]
    var traitsConfig: LocalDataStore.TraitsConfig
}

extension LocalDataStore {

    private var fullBackupSchemaVersion: Int { 1 }

    func buildFullBackup() -> LocalDataStoreFullBackup {
        let snapshot = LocalDataStoreSnapshot(
            schemaVersion: 1,
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
            animalEvents: animalEvents,
            programmedTags: programmedTags,
            soldArchive: soldArchive,
            sessionDraftSetup: sessionDraftSetup
        )

        let yardsByFarmID = Dictionary(uniqueKeysWithValues: farms.map { farm in
            (farm.id, YardLocationStore.list(for: farm.id))
        })

        return LocalDataStoreFullBackup(
            schemaVersion: fullBackupSchemaVersion,
            exportedAt: Date(),
            snapshot: snapshot,
            animalEvents: animalEvents,
            yardsByFarmID: yardsByFarmID,
            treatmentLibrary: treatmentLibrary,
            traitsConfig: traitsConfig
        )
    }

    func exportFullBackupFile() throws -> URL {
        let backup = buildFullBackup()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(backup)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: backup.exportedAt)
            .replacingOccurrences(of: ":", with: "-")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tepari_Full_Backup_\(timestamp).json")

        try data.write(to: url, options: [.atomic])
        return url
    }
}
