import Foundation

/// Shared storage for yard/location names per Farm.
/// Used by FarmSetupView (manage yards) and SessionSetupView (pick yard).
enum YardLocationStore {

    private static func key(_ farmID: UUID) -> String {
        "farms.yards.\(farmID.uuidString)"
    }

    static func list(for farmID: UUID) -> [String] {
        let raw = UserDefaults.standard.string(forKey: key(farmID)) ?? ""

        let parts = raw
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // De-dupe case-insensitively, preserve order
        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            let k = p.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(p)
        }
        return out
    }

    static func saveMerged(_ items: [String], for farmID: UUID) {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // De-dupe case-insensitively
        var seen = Set<String>()
        var out: [String] = []
        for p in cleaned {
            let k = p.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(p)
        }

        let packed = out.joined(separator: "|")
        UserDefaults.standard.set(packed, forKey: key(farmID))
    }

    static func addCommaSeparated(_ input: String, for farmID: UUID) {
        let incoming = input
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !incoming.isEmpty else { return }

        var merged = list(for: farmID)
        for y in incoming {
            if merged.contains(where: { $0.caseInsensitiveCompare(y) == .orderedSame }) { continue }
            merged.append(y)
        }
        saveMerged(merged, for: farmID)
    }

    static func removeAll(for farmID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(farmID))
    }
}
