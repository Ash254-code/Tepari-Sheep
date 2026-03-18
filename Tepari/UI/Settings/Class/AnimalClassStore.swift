import Foundation
import Combine

@MainActor
final class AnimalClassStore: ObservableObject {

    // =========================================================
    // MARK: - Model
    // =========================================================

    struct AnimalClass: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String

        /// Optional defaults you may want later (safe to have now).
        var defaultSex: String?        // "Ewe" / "Wether" / "Ram" etc (string keeps it flexible)
        var notes: String?

        init(
            id: UUID = UUID(),
            name: String,
            defaultSex: String? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.name = name
            self.defaultSex = defaultSex
            self.notes = notes
        }
    }

    // =========================================================
    // MARK: - State
    // =========================================================

    @Published private(set) var classes: [AnimalClass] = []

    // =========================================================
    // MARK: - Persistence
    // =========================================================

    private let defaults: UserDefaults
    private let key = "tepari.animalClasses.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else {
            classes = []
            return
        }
        do {
            classes = try JSONDecoder().decode([AnimalClass].self, from: data)
        } catch {
            classes = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(classes)
            defaults.set(data, forKey: key)
        } catch {
            // no-op
        }
    }

    // =========================================================
    // MARK: - CRUD
    // =========================================================

    func add(_ item: AnimalClass) {
        classes.append(item)
        classes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func update(_ item: AnimalClass) {
        guard let idx = classes.firstIndex(where: { $0.id == item.id }) else { return }
        classes[idx] = item
        classes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func delete(_ item: AnimalClass) {
        classes.removeAll { $0.id == item.id }
        save()
    }
}
