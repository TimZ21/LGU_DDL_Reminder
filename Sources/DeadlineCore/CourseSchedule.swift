import Foundation

public enum CourseSource: String, Codable { case manual, file, subscription, blackboard, sis }

public struct CourseMeeting: Identifiable, Codable, Equatable {
    public var id: String
    public var course: String
    public var location: String
    // Monday = 1, Sunday = 7; times are minutes after local midnight.
    public var weekday: Int
    public var startMinute: Int
    public var endMinute: Int
    public var validFrom: Date
    public var validUntil: Date?
    public var weekInterval: Int
    public var excludedDays: [Date]
    public var source: CourseSource

    public init(id: String = UUID().uuidString, course: String, location: String = "",
                weekday: Int, startMinute: Int, endMinute: Int, validFrom: Date,
                validUntil: Date? = nil, weekInterval: Int = 1, excludedDays: [Date] = [],
                source: CourseSource = .manual) {
        self.id = id; self.course = course; self.location = location
        self.weekday = weekday; self.startMinute = startMinute; self.endMinute = endMinute
        self.validFrom = validFrom; self.validUntil = validUntil; self.weekInterval = weekInterval
        self.excludedDays = excludedDays; self.source = source
    }

    public func occurs(on day: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone; calendar.firstWeekday = 2
        let current = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: validFrom)
        guard current >= first, validUntil.map({ current <= calendar.startOfDay(for: $0) }) ?? true,
              ((calendar.component(.weekday, from: current) + 5) % 7) + 1 == weekday,
              !excludedDays.contains(where: { calendar.isDate($0, inSameDayAs: current) }) else { return false }
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: current)!.start
        let weeks = calendar.dateComponents([.weekOfYear], from: firstWeek, to: currentWeek).weekOfYear ?? 0
        return weekInterval > 0 && weeks >= 0 && weeks % weekInterval == 0
    }
}

public struct CourseSchedule: Codable {
    public var meetings: [CourseMeeting] = []
    public var overrides: [String: CourseMeeting] = [:]
    public var hiddenIDs: Set<String> = []
    public var lastSync: Date?
    public init() {}

    public var visibleMeetings: [CourseMeeting] {
        meetings.filter { !hiddenIDs.contains($0.id) }.map { overrides[$0.id] ?? $0 }
    }
}

public struct ParsedCourseCalendar {
    public var meetings: [CourseMeeting]
    public var warnings: [String]
    public init(meetings: [CourseMeeting], warnings: [String]) {
        self.meetings = meetings; self.warnings = warnings
    }
}
