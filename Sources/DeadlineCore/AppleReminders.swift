import Foundation

public struct AppleRemindersState: Codable, Equatable {
    public var calendarID: String?
    public var completions: [String: Bool] = [:]
    public init() {}
}

public enum AppleRemindersPlanner {
    // App changes since the last successful sync take precedence. Otherwise a
    // completion/reopening in Reminders comes back into the app. First export
    // always respects the app's existing completion state.
    public static func completion(local: Bool, remote: Bool?, lastSynced: Bool?) -> Bool {
        guard let remote, let lastSynced, local == lastSynced else { return local }
        return remote
    }

    public static func dueComponents(for item: Deadline, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let fields: Set<Calendar.Component> = item.hasTime
            ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day]
        var components = calendar.dateComponents(fields, from: item.dueDate)
        components.calendar = Calendar(identifier: .gregorian)
        // A date-only reminder floats with the date; it must not become midnight.
        components.timeZone = item.hasTime ? timeZone : nil
        return components
    }

    public static func link(for reminderID: String) -> URL? {
        guard UUID(uuidString: reminderID) != nil else { return nil }
        return URL(string: "shiqi://deadline/\(reminderID)")
    }
    public static func identity(from url: URL?) -> String? {
        guard let url, url.scheme == "shiqi", url.host == "deadline", url.query == nil,
              url.fragment == nil, url.user == nil, url.password == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, UUID(uuidString: parts[0]) != nil else { return nil }
        return parts[0]
    }
}
