import Foundation

public struct CourseCalendarParser {
    public init() {}

    private struct Property {
        var value: String
        var parameters: [String: String]
    }
    private typealias Event = [String: [Property]]

    public func parse(_ text: String, source: CourseSource,
                      timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) throws -> ParsedCourseCalendar {
        let lines = unfold(text)
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else {
            throw CalendarError.message("不是有效的 .ics 日历文件。")
        }
        var events: [Event] = []
        var current: Event?; var nested = 0
        for line in lines {
            if line == "BEGIN:VEVENT" { current = [:]; nested = 0 }
            else if line == "END:VEVENT" {
                if let current { events.append(current) }
                current = nil
            } else if current != nil {
                if line.hasPrefix("BEGIN:") { nested += 1 }
                else if line.hasPrefix("END:") { nested = max(0, nested - 1) }
                else if nested == 0, let (name, property) = parseProperty(line) { current?[name, default: []].append(property) }
            }
        }
        guard current == nil else { throw CalendarError.message("日历文件不完整。") }
        var exceptions: [String: [(Date, Event)]] = [:]
        for event in events {
            guard let uid = value("UID", event), let recurrence = first("RECURRENCE-ID", event),
                  let date = try? parseDate(recurrence, defaultZone: timeZone).date else { continue }
            exceptions[uid, default: []].append((date, event))
        }
        var meetings: [CourseMeeting] = []
        var warnings: [String] = []
        for event in events where first("RECURRENCE-ID", event) == nil {
            guard value("STATUS", event)?.uppercased() != "CANCELLED" else { continue }
            do {
                let uid = value("UID", event) ?? stableID(String(describing: event))
                let extra = exceptions[uid] ?? []
                let excluded = try excludedDays(event, zone: timeZone) + extra.map(\.0)
                meetings += try makeMeetings(event, uid: uid, source: source, zone: timeZone, excluded: excluded)
                for (original, replacement) in extra where value("STATUS", replacement)?.uppercased() != "CANCELLED" {
                    meetings += try makeMeetings(replacement, uid: "\(uid)|moved|\(Int(original.timeIntervalSince1970))",
                                                 source: source, zone: timeZone, excluded: [], oneOff: true)
                }
            } catch {
                warnings.append("\(unescape(value("SUMMARY", event) ?? "未命名事项"))：\(error.localizedDescription)")
            }
        }
        return ParsedCourseCalendar(meetings: meetings.sorted { $0.weekday == $1.weekday ? $0.startMinute < $1.startMinute : $0.weekday < $1.weekday },
                                    warnings: warnings)
    }

    private func makeMeetings(_ event: Event, uid: String, source: CourseSource, zone: TimeZone,
                              excluded: [Date], oneOff: Bool = false) throws -> [CourseMeeting] {
        guard let startProperty = first("DTSTART", event), let endProperty = first("DTEND", event) else {
            throw CalendarError.message("缺少开始或结束时间")
        }
        let start = try parseDate(startProperty, defaultZone: zone)
        let end = try parseDate(endProperty, defaultZone: zone)
        guard start.hasTime, end.hasTime, end.date > start.date, end.date.timeIntervalSince(start.date) <= 12 * 3600 else {
            throw CalendarError.message("课程须有同一天内的开始和结束时间")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard calendar.isDate(start.date, inSameDayAs: end.date.addingTimeInterval(-1)) else {
            throw CalendarError.message("暂不支持跨天课程")
        }
        let startMinute = calendar.component(.hour, from: start.date) * 60 + calendar.component(.minute, from: start.date)
        let endMinute = calendar.component(.hour, from: end.date) * 60 + calendar.component(.minute, from: end.date)
        let firstDay = calendar.startOfDay(for: start.date)
        let title = unescape(value("SUMMARY", event) ?? "未命名课程")
        let location = unescape(value("LOCATION", event) ?? "")
        let rule = oneOff ? nil : value("RRULE", event)
        var interval = 1
        var days = [weekday(start.date, calendar: calendar)]
        var until: Date? = firstDay
        if let rule {
            let fields = Dictionary(uniqueKeysWithValues: rule.split(separator: ";").compactMap { part -> (String, String)? in
                let pair = part.split(separator: "=", maxSplits: 1)
                return pair.count == 2 ? (String(pair[0]).uppercased(), String(pair[1]).uppercased()) : nil
            })
            guard let frequency = fields["FREQ"], frequency == "WEEKLY" || frequency == "DAILY",
                  let parsedInterval = Int(fields["INTERVAL"] ?? "1"), parsedInterval > 0,
                  frequency != "DAILY" || parsedInterval == 1 else {
                throw CalendarError.message("暂不支持此重复规则")
            }
            interval = frequency == "WEEKLY" ? parsedInterval : 1
            if let byday = fields["BYDAY"] {
                let codes = ["MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6, "SU": 7]
                let parts = byday.split(separator: ",").map(String.init)
                guard parts.allSatisfy({ codes[$0] != nil }) else { throw CalendarError.message("暂不支持此重复星期") }
                days = parts.compactMap { codes[$0] }
            } else if frequency == "DAILY" { days = Array(1...7) }
            until = nil
            if let rawUntil = fields["UNTIL"] {
                let parsed = try parseDate(Property(value: rawUntil, parameters: [:]), defaultZone: zone)
                until = calendar.startOfDay(for: parsed.date)
            }
            if let countText = fields["COUNT"], let count = Int(countText), count > 0 {
                until = min(until ?? .distantFuture, try countedEnd(firstDay, days: days, interval: interval,
                                                                      count: count, calendar: calendar))
            }
        }
        return days.map { day in
            CourseMeeting(id: "\(source.rawValue):\(uid)|\(day)", course: title, location: location,
                          weekday: day, startMinute: startMinute, endMinute: endMinute,
                          validFrom: firstDay, validUntil: until, weekInterval: interval,
                          excludedDays: excluded, source: source)
        }
    }

    private func countedEnd(_ first: Date, days: [Int], interval: Int, count: Int,
                            calendar: Calendar) throws -> Date {
        var cursor = first; var hits = 0
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        for _ in 0..<800 {
            let week = calendar.dateInterval(of: .weekOfYear, for: cursor)!.start
            let offset = calendar.dateComponents([.weekOfYear], from: firstWeek, to: week).weekOfYear ?? 0
            if offset % interval == 0 && days.contains(weekday(cursor, calendar: calendar)) {
                hits += 1
                if hits == count { return cursor }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        throw CalendarError.message("重复课程范围过大")
    }

    private func excludedDays(_ event: Event, zone: TimeZone) throws -> [Date] {
        try (event["EXDATE"] ?? []).flatMap { property in
            try property.value.split(separator: ",").map { raw -> Date in
                var single = property; single.value = String(raw)
                return try parseDate(single, defaultZone: zone).date
            }
        }
    }

    private func parseDate(_ property: Property, defaultZone: TimeZone) throws -> (date: Date, hasTime: Bool) {
        let value = property.value
        let hasTime = value.contains("T") && property.parameters["VALUE"] != "DATE"
        var zone = defaultZone
        if value.hasSuffix("Z") { zone = TimeZone(secondsFromGMT: 0)! }
        else if let tzid = property.parameters["TZID"] {
            let aliases = ["China Standard Time": "Asia/Shanghai", "中国标准时间": "Asia/Shanghai",
                           "Hong Kong Standard Time": "Asia/Hong_Kong"]
            guard let selected = TimeZone(identifier: aliases[tzid] ?? tzid) else { throw CalendarError.message("未知时区 \(tzid)") }
            zone = selected
        }
        let raw = value.hasSuffix("Z") ? String(value.dropLast()) : value
        let format: String
        switch raw.count {
        case 8 where !hasTime: format = "yyyyMMdd"
        case 13 where hasTime: format = "yyyyMMdd'T'HHmm"
        case 15 where hasTime: format = "yyyyMMdd'T'HHmmss"
        default: throw CalendarError.message("无效的课程日期格式")
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        formatter.dateFormat = format; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            throw CalendarError.message("无效的课程日期")
        }
        return (date, hasTime)
    }

    private func weekday(_ date: Date, calendar: Calendar) -> Int { ((calendar.component(.weekday, from: date) + 5) % 7) + 1 }
    private func value(_ name: String, _ event: Event) -> String? { first(name, event)?.value }
    private func first(_ name: String, _ event: Event) -> Property? { event[name]?.first }
    private func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }
    private func stableID(_ value: String) -> String {
        String(value.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
    }
    private func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty { result[result.count - 1] += String(line.dropFirst()) }
            else { result.append(line) }
        }
        return result
    }
    private func parseProperty(_ line: String) -> (String, Property)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let header = line[..<colon].split(separator: ";").map(String.init)
        guard let name = header.first else { return nil }
        var parameters: [String: String] = [:]
        for part in header.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return (name.uppercased(), Property(value: String(line[line.index(after: colon)...]), parameters: parameters))
    }
}
