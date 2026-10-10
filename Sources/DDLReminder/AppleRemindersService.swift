#if os(macOS)
import AppKit
#else
import UIKit
#endif
import EventKit
import DeadlineCore

struct AppleRemindersResult {
    var state: AppleRemindersState
    var completions: [String: Bool]
    var count: Int
}

@MainActor
final class AppleRemindersService {
    #if os(macOS)
    static let listTitle = "拾期 · DDL"
    #else
    // The phone's independently-imported calendar must not overwrite Mac exports.
    static let listTitle = "拾期 · iOS DDL"
    #endif
    private let store = EKEventStore()

    var authorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        #if os(macOS)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
        #else
        return status == .fullAccess
        #endif
    }

    func requestPermission() async throws -> Bool {
        if authorized { return true }
        let granted: Bool
        #if os(macOS)
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        #else
        granted = try await store.requestFullAccessToReminders()
        #endif
        // Discard objects fetched before permission was granted.
        store.reset()
        return granted && authorized
    }

    func reconcile(_ deadlines: [Deadline], state: AppleRemindersState,
                   timeZone: TimeZone, language: AppLanguage) async throws -> AppleRemindersResult {
        guard authorized else {
            #if os(iOS)
            throw CalendarError.message(language.text("请在 iPhone 设置 → 隐私与安全性 → 提醒事项中允许拾期访问。", "Allow Shiqi in Settings → Privacy & Security → Reminders."))
            #else
            throw CalendarError.message(language.text("请在系统设置 → 隐私与安全性 → 提醒事项中允许拾期访问。", "Allow Shiqi in System Settings → Privacy & Security → Reminders."))
            #endif
        }
        try Task.checkCancellation()
        let calendar = try destination(state: state, language: language)
        let predicate = store.predicateForReminders(in: [calendar])
        let fetched: [EKReminder]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard let fetched, authorized else {
            throw CalendarError.message(language.text("无法读取拾期的提醒事项列表，请检查访问权限后重试。", "Could not read Shiqi's Reminders list. Check access and retry."))
        }
        // Only reminders carrying our app link belong to this integration.
        // User-created reminders in the same list are left alone.
        let owned = fetched.compactMap { reminder -> (String, EKReminder)? in
            guard let id = AppleRemindersPlanner.identity(from: reminder.url) else { return nil }
            return (id, reminder)
        }
        let byID = Dictionary(grouping: owned, by: { $0.0 })
        let activeIDs = Set(deadlines.map(\.reminderID))
        var nextState = AppleRemindersState()
        nextState.calendarID = calendar.calendarIdentifier
        var completions: [String: Bool] = [:]
        var changed = false
        let now = Date()
        do {
            for item in deadlines {
                let matches = byID[item.reminderID] ?? []
                // Cloud copies can briefly duplicate an item; keep one and consolidate
                // completion so an already-completed copy does not become pending.
                let remoteCompletion = matches.isEmpty ? nil : matches.contains { $0.1.isCompleted }
                let completed = AppleRemindersPlanner.completion(local: item.completed, remote: remoteCompletion,
                                                                lastSynced: state.completions[item.reminderID])
                let reminder = matches.first?.1 ?? EKReminder(eventStore: store)
                let due = AppleRemindersPlanner.dueComponents(for: item, timeZone: timeZone)
                let notes = [item.course, item.notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
                let url = AppleRemindersPlanner.link(for: item.reminderID)
                // Reminders supplies the at-due-time alert. Shiqi's configurable
                // advance notifications remain independent.
                let alarmDate: Date? = item.hasTime && !completed && item.dueDate > now ? item.dueDate : nil
                let alarms = reminder.alarms ?? []
                let alarmsMatch = alarmDate.map { date in
                    alarms.count == 1 && alarms[0].absoluteDate == date
                } ?? alarms.isEmpty
                if matches.isEmpty || reminder.title != item.title || (reminder.notes ?? "") != notes ||
                    reminder.dueDateComponents != due || reminder.isCompleted != completed ||
                    reminder.url != url || !alarmsMatch || needsStartDate(reminder, due: due) {
                    reminder.calendar = calendar; reminder.title = item.title; reminder.notes = notes
                    reminder.dueDateComponents = due; reminder.url = url
                    #if os(iOS)
                    // EventKit requires a start date for reminders with an iOS due date.
                    reminder.startDateComponents = due
                    #endif
                    reminder.isCompleted = completed
                    reminder.alarms = alarmDate.map { [EKAlarm(absoluteDate: $0)] } ?? []
                    try store.save(reminder, commit: false)
                    changed = true
                }
                for duplicate in matches.dropFirst() {
                    try store.remove(duplicate.1, commit: false); changed = true
                }
                completions[item.reminderID] = completed
                nextState.completions[item.reminderID] = completed
            }
            // Removing a DDL removes only its managed counterpart, never other lists
            // or the user's manually-added tasks. Disabling sync never calls this.
            for (id, reminder) in owned where !activeIDs.contains(id) && state.completions[id] != nil {
                try store.remove(reminder, commit: false); changed = true
            }
            if changed { try store.commit() }
        } catch {
            store.reset() // Roll back staged writes; leave the previous baseline intact.
            throw CalendarError.message(language.text("提醒事项同步失败，请检查列表是否可写、账户状态和访问权限后重试。", "Reminders sync failed. Check that the list is writable, the account is available, and access is allowed, then retry."))
        }
        return AppleRemindersResult(state: nextState, completions: completions, count: deadlines.count)
    }

    private func needsStartDate(_ reminder: EKReminder, due: DateComponents) -> Bool {
        #if os(iOS)
        return reminder.startDateComponents != due
        #else
        return false
        #endif
    }

    private func destination(state: AppleRemindersState, language: AppLanguage) throws -> EKCalendar {
        let calendars = store.calendars(for: .reminder)
        if let id = state.calendarID, let existing = calendars.first(where: { $0.calendarIdentifier == id }) {
            guard existing.allowsContentModifications else {
                throw CalendarError.message(language.text("拾期的提醒事项列表不可写，请检查提醒事项账户。", "Shiqi's Reminders list is read-only. Check your Reminders account."))
            }
            return existing
        }
        if let existing = calendars.first(where: { $0.title == Self.listTitle && $0.allowsContentModifications }) {
            return existing
        }
        // Prefer the user's default Reminders account (including iCloud). A local
        // source is a fallback; an unavailable account must not look like success.
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? calendars.first(where: \.allowsContentModifications)?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            #if os(iOS)
            throw CalendarError.message(language.text("没有可用的提醒事项账户。请先打开 iPhone 提醒事项并设置本机或 iCloud 列表。", "No Reminders account is available. Open iPhone Reminders and set up a local or iCloud list first."))
            #else
            throw CalendarError.message(language.text("没有可用的提醒事项账户。请先打开 macOS 提醒事项并设置本机或 iCloud 列表。", "No Reminders account is available. Open macOS Reminders and set up a local or iCloud list first."))
            #endif
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = Self.listTitle; calendar.source = source
        #if os(macOS)
        calendar.cgColor = NSColor(srgbRed: 0.40, green: 0.24, blue: 0.63, alpha: 1).cgColor
        #else
        calendar.cgColor = UIColor(red: 0.40, green: 0.24, blue: 0.63, alpha: 1).cgColor
        #endif
        do { try store.saveCalendar(calendar, commit: true) }
        catch {
            store.reset()
            throw CalendarError.message(language.text("无法创建「拾期 · DDL」列表，请检查提醒事项账户后重试。", "Could not create the Shiqi DDL list. Check your Reminders account and retry."))
        }
        return calendar
    }
}
