import Foundation

public struct MailMessage: Equatable {
    public let id: String
    public let subject: String
    public let body: String
    public let sender: String
    public let receivedAt: Date
    public let link: URL?

    public init(id: String, subject: String, body: String, sender: String, receivedAt: Date, link: URL? = nil) {
        self.id = id; self.subject = subject; self.body = body; self.sender = sender
        self.receivedAt = receivedAt; self.link = link
    }
}

public struct MailDeadlineCandidate: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let course: String
    public let dueDate: Date
    public let hasTime: Bool
    public let evidence: String
    public let sender: String
    public let link: URL?

    public func deadline() -> Deadline {
        Deadline(id: id, title: title, course: course,
                 notes: "Outlook · \(sender)\n\(evidence)", dueDate: dueDate,
                 hasTime: hasTime, source: .outlook, link: link)
    }
}

public struct MailDeadlineExtractor {
    public init() {}

    public func candidates(from messages: [MailMessage], timeZone: TimeZone, now: Date = Date()) -> [MailDeadlineCandidate] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var result: [MailDeadlineCandidate] = []
        for message in messages {
            let lines = (message.subject + "\n" + message.body)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 1000 }
            let course = firstMatch(in: message.subject + " " + message.body,
                                    pattern: #"\b[A-Z]{2,4}\s?\d{4}\b"#)?.replacingOccurrences(of: " ", with: "") ?? ""
            for line in lines where isDeadlineLine(line) {
                guard let parsed = parseDate(in: line, receivedAt: message.receivedAt, calendar: calendar) else { continue }
                // Ignore dates that are already long gone; old mail often contains historic examples.
                guard parsed.date >= calendar.date(byAdding: .day, value: -30, to: now)! else { continue }
                let identifier = "outlook:\(message.id):\(Int(parsed.date.timeIntervalSince1970))"
                if result.contains(where: { $0.id == identifier }) { continue }
                result.append(MailDeadlineCandidate(id: identifier, title: message.subject.isEmpty ? "Email deadline" : message.subject,
                                                    course: course, dueDate: parsed.date, hasTime: parsed.hasTime,
                                                    evidence: String(line.prefix(300)), sender: message.sender, link: message.link))
            }
        }
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    private func isDeadlineLine(_ text: String) -> Bool {
        text.range(of: #"(?i)(deadline|due\s*(date|by|on)?|submit\s*(by|before)|registration\s*(ends|closes)|截止|最迟|提交期限|报名截止|DDL)"#,
                   options: .regularExpression) != nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private func parseDate(in line: String, receivedAt: Date, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        let year = calendar.component(.year, from: receivedAt)
        let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let shortNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var parts: (Int, Int, Int)?
        if let match = captures(#"(?i)\b(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?\b"#, in: line),
           let y = Int(match[1]), let m = Int(match[2]), let d = Int(match[3]) { parts = (y, m, d) }
        if parts == nil, let match = captures(#"(?i)(?<!\d)(\d{1,2})月(\d{1,2})日?"#, in: line),
           let m = Int(match[1]), let d = Int(match[2]) { parts = (year, m, d) }
        if parts == nil, let match = captures(#"(?i)\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d{2}))?\b"#, in: line),
           let d = Int(match[2]), let m = monthIndex(match[1], monthNames, shortNames) { parts = (Int(match[3]) ?? year, m, d) }
        if parts == nil, let match = captures(#"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)(?:,?\s+(20\d{2}))?\b"#, in: line),
           let d = Int(match[1]), let m = monthIndex(match[2], monthNames, shortNames) { parts = (Int(match[3]) ?? year, m, d) }
        guard let (y, m, d) = parts, (1...12).contains(m), (1...31).contains(d) else { return nil }

        var hour = 0, minute = 0, hasTime = false
        if let match = captures(#"(?i)\b(\d{1,2}):(\d{2})\s*(AM|PM)\b"#, in: line),
           let h = Int(match[1]), let min = Int(match[2]), (1...12).contains(h), (0...59).contains(min) {
            hour = h % 12 + (match[3].lowercased() == "pm" ? 12 : 0); minute = min; hasTime = true
        } else if let match = captures(#"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)"#, in: line),
                  let h = Int(match[1]), let min = Int(match[2]) {
            hour = h; minute = min; hasTime = true
        }
        var components = DateComponents(); components.year = y; components.month = m; components.day = d
        components.hour = hour; components.minute = minute
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date).year == y,
              calendar.component(.month, from: date) == m,
              calendar.component(.day, from: date) == d else { return nil }
        return (date, hasTime)
    }

    private func monthIndex(_ name: String, _ full: [String], _ short: [String]) -> Int? {
        let value = name.lowercased().replacingOccurrences(of: "sept", with: "sep")
        return full.firstIndex(of: value).map { $0 + 1 } ?? short.firstIndex(of: value).map { $0 + 1 }
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
