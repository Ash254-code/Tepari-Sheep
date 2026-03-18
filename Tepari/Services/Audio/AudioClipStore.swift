import Foundation

enum AudioClipStore {

    static let folderName = "AudioClips"

    static func clipsFolderURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func importFile(from pickedURL: URL) throws -> String {
        let dir = try clipsFolderURL()

        let ext = pickedURL.pathExtension.isEmpty ? "" : ".\(pickedURL.pathExtension)"
        let safeBase = "clip_\(UUID().uuidString)"
        let dest = dir.appendingPathComponent(safeBase + ext)

        let didStart = pickedURL.startAccessingSecurityScopedResource()
        defer { if didStart { pickedURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: pickedURL, to: dest)

        return dest.lastPathComponent
    }

    static func fileURL(for storedFileName: String) throws -> URL {
        let dir = try clipsFolderURL()
        return dir.appendingPathComponent(storedFileName)
    }

    static func delete(storedFileName: String) throws {
        let url = try fileURL(for: storedFileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
