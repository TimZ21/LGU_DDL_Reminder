import Foundation
import DeadlineCore

// Codex appends source records. User actions in the app are stored separately.
struct CodexUserEdits: Codable {
    var replacements: [String: Deadline] = [:]
    var hidden: Set<String> = []
}

enum CodexDisplay {
    static var url: URL {
        LocalStorage.directory.appendingPathComponent("CodexDeadlines.jsonl")
    }

    static var modifiedAt: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static var editsURL: URL {
        LocalStorage.directory.appendingPathComponent("CodexUserEdits.json")
    }

    static var editsModifiedAt: Date? {
        try? editsURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func load() throws -> [Deadline] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.components(separatedBy: .newlines).filter { !$0.isEmpty }.map {
            try JSONDecoder().decode(Deadline.self, from: Data($0.utf8))
        }
    }

    static func loadEdits() throws -> CodexUserEdits {
        guard FileManager.default.fileExists(atPath: editsURL.path) else { return CodexUserEdits() }
        return try JSONDecoder().decode(CodexUserEdits.self, from: Data(contentsOf: editsURL))
    }

    static func saveEdits(_ edits: CodexUserEdits) throws {
        try FileManager.default.createDirectory(at: LocalStorage.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(edits).write(to: editsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: editsURL.path)
    }
}
