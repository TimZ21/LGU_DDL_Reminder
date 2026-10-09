import Foundation

public struct ParsedCalendar {
    public var deadlines: [Deadline]
    public var warnings: [String]
    // Keep previous entries if their replacement cannot be parsed safely.
    public var protectedPrefixes: [String]
    public init(deadlines: [Deadline], warnings: [String], protectedPrefixes: [String]) {
        self.deadlines = deadlines; self.warnings = warnings; self.protectedPrefixes = protectedPrefixes
    }
}

public struct ICalendarParser {
    public var language: AppLanguage
    public init(language: AppLanguage = .chinese) { self.language = language }
    private struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }

    public func parse(_ text: String, source: DeadlineSource = .blackboard,
                      defaultTimeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!,
                      now: Date = Date()) throws -> ParsedCalendar {
        let normalized = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else { lines.append(line) }
        }
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else {
            throw CalendarError.message(language.text("没有收到有效的日历数据。链接可能已失效、需要校园网，或返回了登录页面。", "No valid calendar data was received. The link may have expired, require campus access, or return a sign-in page."))
        }
        var zone = defaultTimeZone
        if let line = lines.first(where: { $0.hasPrefix("X-WR-TIMEZONE:") }),
           let declared = TimeZone(identifier: String(line.dropFirst("X-WR-TIMEZONE:".count))) { zone = declared }
        var blocks: [[Property]] = []; var current: [Property]?; var nested = 0
        for line in lines {
            if line == "BEGIN:VEVENT" || line == "BEGIN:VTODO" {
                guard current == nil else { throw CalendarError.message(language.text("日历事件结构不完整，已保留之前的数据。", "The calendar event structure is incomplete. Previous data is kept.")) }
                current = []; nested = 0
            } else if line == "END:VEVENT" || line == "END:VTODO" {
                if let event = current { blocks.append(event); current = nil }
            } else if current != nil {
                if line.hasPrefix("BEGIN:") { nested += 1 }
                else if line.hasPrefix("END:") { nested = max(0, nested - 1) }
                else if nested == 0, let property = property(line) { current?.append(property) }
            }
        }
        guard current == nil else { throw CalendarError.message(language.text("日历文件被截断，已保留之前的数据。", "The calendar file is truncated. Previous data is kept.")) }
        var output: [Deadline] = []; var warnings: [String] = []; var protected: [String] = []
        // Overrides replace the matching generated occurrence, including moved/cancelled instances.
        let overrideKeys = Set(blocks.compactMap { properties -> String? in
            guard let uid = first("UID", in: properties)?.value,
                  let recurrence = first("RECURRENCE-ID", in: properties),
                  let date = try? parseDate(recurrence, defaultZone: zone).date else { return nil }
            return "\(uid)|\(Int(date.timeIntervalSince1970))"
        })
        for properties in blocks {
            let title = unescape(first("SUMMARY", in: properties)?.value ?? language.text("未命名日历事项", "Untitled calendar item"))
            let uid = first("UID", in: properties)?.value ?? stableID(properties.map(\.value).joined(separator: "|"))
            let prefix = "\(source.rawValue):\(uid)"
            if first("STATUS", in: properties)?.value.uppercased() == "CANCELLED" { continue }
            do {
                guard let start = first("DUE", in: properties) ?? first("DTSTART", in: properties) else {
                    throw CalendarError.message(language.text("没有提供截止日期", "No due date was provided"))
                }
                let parsed = try parseDate(start, defaultZone: zone)
                let recurrenceID = first("RECURRENCE-ID", in: properties)
                let recurrenceDate = try recurrenceID.map { try parseDate($0, defaultZone: zone).date }
                var dates = [parsed.date]
                let recurring = first("RRULE", in: properties) != nil || first("RDATE", in: properties) != nil
                if let rule = first("RRULE", in: properties) {
                    dates = try occurrences(rule.value, start: parsed.date, zone: parsed.zone, now: now)
                }
                for additional in properties.filter({ $0.name == "RDATE" }) {
                    for value in additional.value.split(separator: ",") {
                        var property = additional; property.value = String(value)
                        dates.append(try parseDate(property, defaultZone: zone).date)
                    }
                }
                var excluded = Set<Date>()
                for exception in properties.filter({ $0.name == "EXDATE" }) {
                    for value in exception.value.split(separator: ",") {
                        var property = exception; property.value = String(value)
                        excluded.insert(try parseDate(property, defaultZone: zone).date)
                    }
                }
                let course = unescape(first("X-BB-COURSE-NAME", in: properties)?.value
                    ?? first("X-BLACKBOARD-COURSE-NAME", in: properties)?.value
                    ?? first("CATEGORIES", in: properties)?.value ?? "")
                let notes = unescape(first("DESCRIPTION", in: properties)?.value ?? "")
                let link = first("URL", in: properties).flatMap { URL(string: $0.value) }
                for date in Set(dates).sorted() where !excluded.contains(date) {
                    let stamp = Int((recurrenceDate ?? date).timeIntervalSince1970)
                    if recurrenceID == nil && recurring && overrideKeys.contains("\(uid)|\(stamp)") { continue }
                    let id = recurring || recurrenceID != nil ? "\(prefix)|\(stamp)" : prefix
                    output.append(Deadline(id: id, title: title, course: course, notes: notes,
                                           dueDate: date, hasTime: parsed.hasTime, source: source,
                                           link: link?.scheme == "https" ? link : nil))
                }
            } catch {
                protected.append(prefix)
                warnings.append(language.text("「\(title)」未能导入：\(error.localizedDescription)", "Could not import “\(title)”: \(error.localizedDescription)"))
            }
        }
        var unique: [String: Deadline] = [:]
        for item in output { unique[item.id] = item }
        return ParsedCalendar(deadlines: unique.values.sorted { $0.dueDate < $1.dueDate },
                              warnings: warnings, protectedPrefixes: protected)
    }

    private func property(_ line: String) -> Property? {
        // Colons/semicolons inside quoted TZID parameters are not delimiters.
        var quoted = false; var colon: String.Index?
        for i in line.indices {
            if line[i] == "\"" { quoted.toggle() }
            if line[i] == ":", !quoted { colon = i; break }
        }
        guard let colon else { return nil }
        let header = String(line[..<colon]); var pieces: [String] = []; var piece = ""; quoted = false
        for character in header {
            if character == "\"" { quoted.toggle() }
            if character == ";", !quoted { pieces.append(piece); piece = "" } else { piece.append(character) }
        }
        pieces.append(piece)
        var parameters: [String: String] = [:]
        for item in pieces.dropFirst() {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { parameters[parts[0].uppercased()] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return Property(name: pieces[0].uppercased(), parameters: parameters, value: String(line[line.index(after: colon)...]))
    }
    private func first(_ key: String, in properties: [Property]) -> Property? { properties.first { $0.name == key } }

    private func parseDate(_ property: Property, defaultZone: TimeZone) throws -> (date: Date, hasTime: Bool, zone: TimeZone) {
        let value = property.value
        let hasTime = property.parameters["VALUE"] != "DATE" && value.contains("T")
        var zone = defaultZone
        if value.hasSuffix("Z") { zone = TimeZone(secondsFromGMT: 0)! }
        else if let id = property.parameters["TZID"] {
            let aliases = ["China Standard Time": "Asia/Shanghai", "Hong Kong Standard Time": "Asia/Hong_Kong"]
            guard let found = TimeZone(identifier: aliases[id] ?? id) else {
                throw CalendarError.message(language.text("不支持时区 \(id)，请在 Blackboard 确认时间后手动添加", "Unsupported time zone \(id). Confirm the time in Blackboard and add it manually"))
            }
            zone = found
        }
        let raw = value.hasSuffix("Z") ? String(value.dropLast()) : value
        let expected = hasTime ? 15 : 8
        guard raw.count == expected, raw.enumerated().allSatisfy({ $0.offset == 8 && hasTime ? $0.element == "T" : $0.element.isNumber }) else {
            throw CalendarError.message(language.text("日期格式无效", "Invalid date format"))
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        formatter.dateFormat = hasTime ? "yyyyMMdd'T'HHmmss" : "yyyyMMdd"; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            throw CalendarError.message(language.text("日期或时间无效", "Invalid date or time"))
        }
        return (date, hasTime, zone)
    }

    private func occurrences(_ rule: String, start: Date, zone: TimeZone, now: Date) throws -> [Date] {
        var fields: [String: String] = [:]
        for piece in rule.split(separator: ";") {
            let parts = piece.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0].uppercased()] = parts[1].uppercased() }
        }
        let supported: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        guard Set(fields.keys).isSubset(of: supported), let frequency = fields["FREQ"],
              ["DAILY", "WEEKLY"].contains(frequency), fields["WKST"] == nil || fields["WKST"] == "MO" else {
            throw CalendarError.message(language.text("此重复规则暂不支持，请手动补充相关截止日期", "This recurrence rule is not supported. Add the relevant deadlines manually"))
        }
        guard let interval = Int(fields["INTERVAL"] ?? "1"), interval > 0,
              let count = Int(fields["COUNT"] ?? "100000"), count > 0 else {
            throw CalendarError.message(language.text("重复规则无效", "Invalid recurrence rule"))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; calendar.firstWeekday = 2
        let lower = calendar.date(byAdding: .day, value: -30, to: now)!
        var upper = calendar.date(byAdding: .year, value: 1, to: now)!
        if let until = fields["UNTIL"] {
            let parsed = try parseDate(Property(name: "UNTIL", parameters: [:], value: until), defaultZone: zone)
            let end = parsed.hasTime ? parsed.date : calendar.date(byAdding: .day, value: 1, to: parsed.date)!.addingTimeInterval(-1)
            upper = min(upper, end)
        }
        let dayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        var weekdays: Set<Int> = [calendar.component(.weekday, from: start)]
        if let byDay = fields["BYDAY"] {
            let values = byDay.split(separator: ",").map(String.init)
            guard values.allSatisfy({ dayCodes[$0] != nil }) else {
                throw CalendarError.message(language.text("此重复规则暂不支持", "This recurrence rule is not supported"))
            }
            weekdays = Set(values.compactMap { dayCodes[$0] })
        }
        let startDay = calendar.startOfDay(for: start)
        let weekStart = calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: startDay)!
        var cursor = start; var index = 0; var result: [Date] = []; var visited = 0
        while cursor <= upper && index < count {
            visited += 1
            guard visited <= 40000 else { throw CalendarError.message(language.text("重复事件范围过大，请缩短日历范围", "The recurring event range is too large. Shorten the calendar range")) }
            let dayOffset = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: cursor)).day!
            let weeks = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: cursor)).day! / 7
            let weekday = calendar.component(.weekday, from: cursor)
            let matches = frequency == "DAILY" ? dayOffset % interval == 0 && (fields["BYDAY"] == nil || weekdays.contains(weekday))
                : weeks % interval == 0 && weekdays.contains(weekday)
            if matches {
                index += 1
                if cursor >= lower { result.append(cursor) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func unescape(_ text: String) -> String {
        var result = ""; var escaped = false
        for character in text {
            if escaped {
                result.append(character == "n" || character == "N" ? "\n" : character); escaped = false
            } else if character == "\\" { escaped = true } else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }
    private func stableID(_ value: String) -> String {
        // Deterministic fallback for feeds missing the required UID.
        let hash = value.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
