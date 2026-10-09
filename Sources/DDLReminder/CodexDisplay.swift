import Foundation
import DeadlineCore

// An independent, append-only list. The app never writes to this file or compares
// its entries with Blackboard, manual, or Outlook tasks.
enum CodexDisplay {
    static var url: URL {
        LocalStorage.directory.appendingPathComponent("CodexDeadlines.jsonl")
    }

    static var modifiedAt: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func load() throws -> [Deadline] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.components(separatedBy: .newlines).filter { !$0.isEmpty }.map {
            try JSONDecoder().decode(Deadline.self, from: Data($0.utf8))
        }
    }
}
