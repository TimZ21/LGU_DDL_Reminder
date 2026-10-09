import Foundation

public enum DeadlineSource: String, Codable { case blackboard, manual, file }

public struct Deadline: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var course: String
    public var notes: String
    public var dueDate: Date
    public var hasTime: Bool
    public var source: DeadlineSource
    public var link: URL?
    public var completed: Bool

    public init(id: String = UUID().uuidString, title: String, course: String = "", notes: String = "",
                dueDate: Date, hasTime: Bool = true, source: DeadlineSource = .manual,
                link: URL? = nil, completed: Bool = false) {
        self.id = id; self.title = title; self.course = course; self.notes = notes
        self.dueDate = dueDate; self.hasTime = hasTime; self.source = source
        self.link = link; self.completed = completed
    }

    public func isOverdue(at now: Date, timeZone: TimeZone) -> Bool {
        if hasTime { return dueDate < now }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}

public struct Preferences: Codable, Equatable {
    public var siteURL = "https://bb.cuhk.edu.cn"
    public var timeZoneID = "Asia/Shanghai"
    public var syncMinutes = 15
    public var reminderMinutes = [1440, 180, 30, 0]
    public var notificationsEnabled = true
    public var language: AppLanguage = .chinese
    public init() {}
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 28800)! }
    public var timeZoneLabel: String { language.timeZoneName(timeZoneID) }

    private enum CodingKeys: String, CodingKey {
        case siteURL, timeZoneID, syncMinutes, reminderMinutes, notificationsEnabled, language
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        siteURL = try values.decodeIfPresent(String.self, forKey: .siteURL) ?? siteURL
        timeZoneID = try values.decodeIfPresent(String.self, forKey: .timeZoneID) ?? timeZoneID
        syncMinutes = try values.decodeIfPresent(Int.self, forKey: .syncMinutes) ?? syncMinutes
        reminderMinutes = try values.decodeIfPresent([Int].self, forKey: .reminderMinutes) ?? reminderMinutes
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
    }
}

public struct Snapshot: Codable {
    public var deadlines: [Deadline] = []
    public var preferences = Preferences()
    public var lastSync: Date?
    public var warnings: [String] = []
    public init() {}
}

public enum FeedAddress {
    public static func validate(_ text: String, language: AppLanguage = .chinese) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("webcal://") { value = "https://" + value.dropFirst(9) }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil else { throw CalendarError.message(language.text("请输入完整的 HTTPS 日历订阅链接，不是 Blackboard 首页地址。", "Enter the full HTTPS calendar subscription link, rather than the Blackboard homepage.")) }
        guard url.path != "", url.path != "/" else {
            throw CalendarError.message(language.text("这是网站首页，请在 Blackboard 日历中复制「共享日历 / Get External Calendar Link」的链接。", "This is the homepage. Copy the link from Share Calendar / Get External Calendar Link in Blackboard."))
        }
        return url
    }
}

public enum CalendarError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct ReminderPlan: Equatable {
    public var id: String
    public var deadline: Deadline
    public var fireDate: Date
    public var subtitle: String
}

public enum ReminderPlanner {
    public static func plans(for deadlines: [Deadline], preferences: Preferences, now: Date) -> [ReminderPlan] {
        guard preferences.notificationsEnabled else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = preferences.timeZone
        var plans: [ReminderPlan] = []
        let language = preferences.language
        for item in deadlines where !item.completed {
            if item.hasTime {
                for minutes in Set(preferences.reminderMinutes).filter({ $0 >= 0 }) {
                    let fire = item.dueDate.addingTimeInterval(-Double(minutes) * 60)
                    if fire > now {
                        plans.append(ReminderPlan(id: identifier(item, suffix: "m\(minutes)"), deadline: item,
                                                  fireDate: fire, subtitle: minutes == 0 ? language.text("截止时间到了", "Deadline reached") : language.text("距离截止还有 \(label(minutes))", "Due in \(language.duration(minutes))")))
                    }
                }
            } else {
                let day = calendar.startOfDay(for: item.dueDate)
                for offset in [-1, 0] {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: day),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date), fire > now else { continue }
                    plans.append(ReminderPlan(id: identifier(item, suffix: "day\(offset)"), deadline: item,
                                              fireDate: fire, subtitle: offset == 0 ? language.text("今天到期 · 具体时间待确认", "Due today · Time to confirm") : language.text("明天到期 · 具体时间待确认", "Due tomorrow · Time to confirm")))
                }
            }
        }
        return plans.sorted { $0.fireDate < $1.fireDate }
    }
    private static func identifier(_ item: Deadline, suffix: String) -> String {
        "ddl.\(item.id).\(Int(item.dueDate.timeIntervalSince1970)).\(suffix)"
    }
    public static func label(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}
