import Foundation

enum CodexInbox {
    static var directory: URL { LocalStorage.directory.appendingPathComponent("CodexInbox", isDirectory: true) }

    static func pending() throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { url in
                guard url.pathExtension.lowercased() == "json",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(20)
            .map { $0 }
    }

    static func reject(_ url: URL) throws {
        let destination = url.deletingPathExtension().appendingPathExtension("rejected")
        try FileManager.default.moveItem(at: url, to: destination)
    }
}
