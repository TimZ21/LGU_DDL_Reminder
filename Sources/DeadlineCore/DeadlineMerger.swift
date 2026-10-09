import Foundation

public enum DeadlineMerger {
    private struct TaskFingerprint: Hashable {
        let title: String
        let course: String
        let dueDate: Date
        let hasTime: Bool

        init(_ item: Deadline) {
            title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            course = (item.sourceCourse ?? item.course).trimmingCharacters(in: .whitespacesAndNewlines)
            dueDate = item.dueDate
            hasTime = item.hasTime
        }
    }

    // Subscription sync replaces its source; independent file imports are additive.
    public static func merge(previous: [Deadline], parsed: ParsedCalendar, source: DeadlineSource,
                             removeMissing: Bool = true) -> [Deadline] {
        let eligible = previous.indices.filter {
            previous[$0].source == source ||
            ([.blackboard, .file].contains(source) && [.blackboard, .file].contains(previous[$0].source))
        }
        let byID = Dictionary(grouping: eligible, by: { previous[$0].id })
        let byCalendarID = Dictionary(grouping: eligible.filter { calendarID(previous[$0]) != nil },
                                      by: { calendarID(previous[$0])! })
        let byTask = Dictionary(grouping: eligible, by: { TaskFingerprint(previous[$0]) })
        let incomingByTask = Dictionary(grouping: parsed.deadlines.indices, by: { TaskFingerprint(parsed.deadlines[$0]) })
        var matches: [Int: Int] = [:]
        var consumed = Set<Int>()

        func match(_ index: Int, candidates: [Int]?) {
            guard matches[index] == nil, let candidates, candidates.count == 1,
                  let prior = candidates.first, !consumed.contains(prior) else { return }
            matches[index] = prior
            consumed.insert(prior)
        }

        // Reserve identity matches before considering changed UIDs. A recurrence ID
        // is part of calendarID, so completing one occurrence does not complete others.
        for index in parsed.deadlines.indices { match(index, candidates: byID[parsed.deadlines[index].id]) }
        for index in parsed.deadlines.indices {
            if let id = calendarID(parsed.deadlines[index]) { match(index, candidates: byCalendarID[id]) }
        }
        for index in parsed.deadlines.indices where matches[index] == nil {
            let key = TaskFingerprint(parsed.deadlines[index])
            // Blackboard can regenerate UIDs on every export. Only match a unique,
            // identical title/course/instant/time-kind pair; notes and timestamps vary.
            guard !key.title.isEmpty, incomingByTask[key]?.count == 1 else { continue }
            match(index, candidates: byTask[key])
        }

        let fresh = parsed.deadlines.enumerated().map { index, value -> Deadline in
            var item = value
            if let priorIndex = matches[index] {
                let prior = previous[priorIndex]
                // Completion is a local user choice, including after a source reschedule.
                item.completed = prior.completed
                if prior.sourceCourse != nil {
                    item.sourceCourse = item.course
                    item.course = prior.course
                }
                if source == .file && prior.source == .blackboard {
                    // Importing the same event from a file must not detach it from sync.
                    item.id = prior.id
                    item.source = prior.source
                }
            }
            return item
        }
        let retained = previous.indices.filter { index in
            guard !consumed.contains(index) else { return false }
            let item = previous[index]
            guard removeMissing, item.source == source else { return true }
            return parsed.protectedPrefixes.contains { item.id == $0 || item.id.hasPrefix($0 + "|") }
        }.map { previous[$0] }
        return (retained + fresh).sorted { $0.dueDate < $1.dueDate }
    }

    private static func calendarID(_ item: Deadline) -> String? {
        guard item.source == .blackboard || item.source == .file else { return nil }
        let prefix = item.source.rawValue + ":"
        guard item.id.hasPrefix(prefix) else { return nil }
        return String(item.id.dropFirst(prefix.count))
    }
}
