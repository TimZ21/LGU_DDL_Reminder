import AppKit
import Combine
import DeadlineCore
import ServiceManagement
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var codexDeadlines: [Deadline] = []
    @Published var now = Date()
    @Published var isSyncing = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var scheduledCount = 0
    @Published var isSyncingAppleReminders = false
    @Published var isRequestingRemindersAccess = false
    @Published var appleRemindersCount = 0
    @Published var appleRemindersLastSync: Date?
    @Published var appleRemindersError: String?
    @Published var showConnection = false
    @Published var showSettings = false
    @Published var showEditor = false
    @Published var showOutlook = false
    @Published var showCourseSchedule = false
    @Published private(set) var courseSchedule = CourseSchedule()
    @Published var courseError: String?
    @Published private(set) var courseFeedSummary: String?
    @Published var editingDeadline: Deadline?
    let isDemo = ProcessInfo.processInfo.arguments.contains("--demo") || Bundle.main.object(forInfoDictionaryKey: "DDLDemoMode") as? Bool == true
    private let notifications = NotificationService()
    private lazy var appleRemindersService = AppleRemindersService()
    private var feedURL: URL?
    private var canPersistCourses = true
    private var timer: Timer?
    private var lastAttempt: Date?
    private var schedulingTask: Task<Void, Never>?
    private var appleRemindersTask: Task<Void, Never>?
    private var started = false
    private var canPersist = true
    private var wakeObserver: NSObjectProtocol?
    private var codexModifiedAt: Date?
    private var codexEditsModifiedAt: Date?
    private var codexEdits = CodexUserEdits()

    init() {
        if isDemo { loadDemo(); return }
        do { snapshot = try LocalStorage.load() }
        catch {
            canPersist = false
            errorMessage = t("本地数据无法读取。为避免覆盖旧数据，暂时停止保存；请先备份 ~/Library/Application Support/DDLReminder。", "Local data could not be read. Saving is paused to protect existing data. Back up ~/Library/Application Support/DDLReminder first.")
        }
        reloadCodexDisplay()
        do { courseSchedule = try CourseScheduleStorage.load() }
        catch {
            canPersistCourses = false
            courseError = t("课程表数据无法读取；已停止保存，以免覆盖原文件。", "Could not read the course schedule. Saving is paused to protect it.")
        }
        let startupLanguage = language
        Task.detached { [weak self] in
            let connection = Result { try Keychain.read(language: startupLanguage) }
            await self?.applyStartupConnection(connection)
        }
    }

    private func applyStartupConnection(_ connection: Result<String?, Error>) {
        switch connection {
        case .success(let text):
            if let text {
                do {
                    feedURL = try FeedAddress.validate(text, language: language)
                    isConnected = true
                    Task { await sync() }
                } catch { errorMessage = error.localizedDescription }
            }
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }

    var preferences: Preferences { snapshot.preferences }
    var language: AppLanguage { preferences.language }
    func t(_ chinese: String, _ english: String) -> String { language.text(chinese, english) }
    var displayedDeadlines: [Deadline] { snapshot.deadlines + codexDeadlines }
    func isCodexDisplay(_ item: Deadline) -> Bool { item.id.hasPrefix("codex:") }
    var active: [Deadline] { displayedDeadlines.filter { !$0.completed }.sorted { $0.dueDate < $1.dueDate } }
    var upcoming: [Deadline] { active.filter { !$0.isOverdue(at: now, timeZone: preferences.timeZone) } }
    var overdue: [Deadline] { active.filter { $0.isOverdue(at: now, timeZone: preferences.timeZone) } }
    var nextSevenDays: [Deadline] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = preferences.timeZone
        let end = calendar.date(byAdding: .day, value: 7, to: now)!
        return upcoming.filter { $0.dueDate <= end }
    }
    var nextDay: [Deadline] { upcoming.filter { $0.hasTime && $0.dueDate <= now.addingTimeInterval(86400) } }
    var uncertain: [Deadline] { active.filter { !$0.hasTime } }
    var courseCount: Int { Set(active.map(\.course).filter { !$0.isEmpty }).count }
    var stale: Bool { isConnected && (snapshot.lastSync == nil || now.timeIntervalSince(snapshot.lastSync!) > Double(preferences.syncMinutes * 60 + 120)) }

    func start() async {
        guard !started else { return }; started = true
        if !isDemo { notificationStatus = await notifications.authorization(); reschedule() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }; self.now = Date(); self.reloadCodexDisplay()
                if !self.isDemo { self.reschedule() }
                if self.isConnected, !self.isSyncing,
                   self.lastAttempt == nil || self.now.timeIntervalSince(self.lastAttempt!) >= Double(self.preferences.syncMinutes * 60) {
                    await self.sync()
                }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date(); self?.reschedule()
                if self?.isConnected == true { await self?.sync() }
            }
        }
    }

    func connect(_ text: String) async -> Bool {
        guard !isDemo else { notice = t("演示模式不会连接真实账号。", "Demo mode does not connect to real accounts."); return false }
        guard !isSyncing else { return false }
        isSyncing = true; defer { isSyncing = false }
        do {
            let url = try FeedAddress.validate(text, language: language)
            let content = try await FeedClient().fetch(url, language: language)
            let result = try ICalendarParser(language: language).parse(content, defaultTimeZone: preferences.timeZone)
            try Keychain.write(url.absoluteString, language: language)
            feedURL = url; isConnected = true; lastAttempt = Date()
            merge(result, source: .blackboard); snapshot.lastSync = Date(); errorMessage = nil
            importBlackboardCourseEvents(content)
            save(); reschedule(); notice = t("已连接 Blackboard，导入 \(result.deadlines.count) 个日历事项。", "Connected to Blackboard. Imported \(result.deadlines.count) calendar items.")
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func sync() async {
        guard !isSyncing, let url = feedURL, !isDemo else { return }
        isSyncing = true; lastAttempt = Date(); defer { isSyncing = false }
        do {
            let content = try await FeedClient().fetch(url, language: language)
            let result = try ICalendarParser(language: language).parse(content, defaultTimeZone: preferences.timeZone)
            merge(result, source: .blackboard); snapshot.lastSync = Date(); now = Date()
            importBlackboardCourseEvents(content)
            errorMessage = nil; save(); reschedule()
        } catch { errorMessage = error.localizedDescription }
    }

    func importFile(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
                throw CalendarError.message(t("请选择小于 5 MB 的 UTF-8 日历文件。", "Choose a UTF-8 calendar file smaller than 5 MB."))
            }
            let result = try ICalendarParser(language: language).parse(text, source: .file, defaultTimeZone: preferences.timeZone)
            snapshot.deadlines = DeadlineMerger.merge(previous: snapshot.deadlines, parsed: result, source: .file, removeMissing: false)
            snapshot.warnings = result.warnings
            save(); reschedule(); notice = t("已导入 \(result.deadlines.count) 个事项。文件不会自动更新，建议连接订阅链接。", "Imported \(result.deadlines.count) items. Files do not update automatically; connect a subscription for updates.")
        } catch { errorMessage = error.localizedDescription }
    }

    func importCourseFile(_ url: URL) {
        guard !isDemo, canPersistCourses else { return }
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024 else {
                throw CalendarError.message(t("请选择小于 5 MB 的课表文件。", "Choose a schedule file smaller than 5 MB."))
            }
            let source: CourseSource = url.pathExtension.lowercased() == "zip" ? .sis : .file
            let texts: [String]
            if source == .sis { texts = try CourseArchiveReader.calendarTexts(from: url) }
            else if let text = String(data: data, encoding: .utf8) { texts = [text] }
            else { throw CalendarError.message(t("课表文件不是 UTF-8 格式。", "The schedule file is not UTF-8.")) }
            var meetings: [CourseMeeting] = []; var warnings: [String] = []
            for text in texts {
                let parsed = try CourseCalendarParser().parse(text, source: source, timeZone: preferences.timeZone)
                meetings += parsed.meetings; warnings += parsed.warnings
            }
            let result = ParsedCourseCalendar(meetings: meetings, warnings: warnings)
            guard !result.meetings.isEmpty else { throw CalendarError.message(t("该文件没有可识别的课程时间，已保留原课程表。", "No class meetings were found. The existing schedule was kept.")) }
            applyCourseImport(result, source: source)
            notice = t("已导入 \(result.meetings.count) 个课程时段。", "Imported \(result.meetings.count) class periods.")
        } catch { courseError = error.localizedDescription }
    }

    private func applyCourseImport(_ result: ParsedCourseCalendar, source: CourseSource) {
        let incoming = Set(result.meetings.map(\.id))
        // Refresh exact source identities only; never compare course titles or task content.
        courseSchedule.meetings.removeAll { $0.source == source && incoming.contains($0.id) }
        courseSchedule.meetings += result.meetings
        courseSchedule.lastSync = Date()
        courseError = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        saveCourses()
    }

    private func importBlackboardCourseEvents(_ content: String) {
        guard canPersistCourses else { return }
        do {
            let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            let total = lines.filter { $0 == "BEGIN:VEVENT" }.count
            let starts = lines.filter { $0.hasPrefix("DTSTART:") || $0.hasPrefix("DTSTART;") }.count
            let ends = lines.filter { $0.hasPrefix("DTEND:") || $0.hasPrefix("DTEND;") }.count
            let durations = lines.filter { $0.hasPrefix("DURATION:") }.count
            let result = try CourseCalendarParser().parse(content, source: .blackboard, timeZone: preferences.timeZone)
            courseFeedSummary = t("Blackboard 订阅：\(total) 个事件，\(starts) 个开始时间，\(ends) 个结束时间，\(durations) 个持续时间；识别到 \(result.meetings.count) 个课表时段。", "Blackboard feed: \(total) events, \(starts) starts, \(ends) ends, \(durations) durations; \(result.meetings.count) schedule periods found.")
            if !result.meetings.isEmpty { applyCourseImport(result, source: .blackboard) }
            else { courseError = nil }
        } catch { courseError = error.localizedDescription }
    }

    func upsertCourse(_ meeting: CourseMeeting) {
        guard canPersistCourses, !isDemo else { return }
        if let index = courseSchedule.meetings.firstIndex(where: { $0.id == meeting.id }) {
            if courseSchedule.meetings[index].source == .manual { courseSchedule.meetings[index] = meeting }
            else { courseSchedule.overrides[meeting.id] = meeting }
        } else { courseSchedule.meetings.append(meeting) }
        saveCourses()
    }
    func deleteCourse(_ meeting: CourseMeeting) {
        guard canPersistCourses, !isDemo else { return }
        if meeting.source == .manual { courseSchedule.meetings.removeAll { $0.id == meeting.id } }
        else { courseSchedule.hiddenIDs.insert(meeting.id) }
        saveCourses()
    }
    private func saveCourses() {
        guard !isDemo, canPersistCourses else { return }
        do { try CourseScheduleStorage.save(courseSchedule) }
        catch { courseError = t("课程表保存失败；请检查磁盘空间和权限。", "Could not save the schedule. Check disk space and permissions.") }
    }

    private func merge(_ result: ParsedCalendar, source: DeadlineSource) {
        snapshot.deadlines = DeadlineMerger.merge(previous: snapshot.deadlines, parsed: result, source: source)
        snapshot.warnings = result.warnings
    }

    func disconnect() {
        guard !isSyncing, !isDemo else { return }
        do {
            try Keychain.delete(language: language); feedURL = nil; isConnected = false; snapshot.lastSync = nil
            snapshot.deadlines.removeAll { $0.source == .blackboard }; snapshot.warnings = []
            save(); reschedule(); notice = t("已断开 Blackboard 连接。", "Disconnected from Blackboard.")
        } catch { errorMessage = error.localizedDescription }
    }
    func toggle(_ item: Deadline) {
        if isCodexDisplay(item) {
            var updated = item
            updated.completed.toggle()
            saveCodexUserChange(updated)
            return
        }
        guard let i = snapshot.deadlines.firstIndex(where: { $0.id == item.id }) else { return }
        snapshot.deadlines[i].completed.toggle(); save(); reschedule()
    }
    func setCourse(_ value: String, for itemID: String) {
        guard let index = snapshot.deadlines.firstIndex(where: { $0.id == itemID }),
              snapshot.deadlines[index].source != .manual else { return }
        let course = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !course.isEmpty else { return }
        if snapshot.deadlines[index].sourceCourse == nil {
            snapshot.deadlines[index].sourceCourse = snapshot.deadlines[index].course
        }
        snapshot.deadlines[index].course = course
        save(); reschedule()
    }
    func upsert(_ item: Deadline) {
        if isCodexDisplay(item) { saveCodexUserChange(item); return }
        if let index = snapshot.deadlines.firstIndex(where: { $0.id == item.id }) {
            var updated = item; updated.reminderID = snapshot.deadlines[index].reminderID
            snapshot.deadlines[index] = updated
        }
        else { snapshot.deadlines.append(item) }
        save(); reschedule()
    }
    func importOutlook(_ candidates: [MailDeadlineCandidate]) {
        for candidate in candidates {
            var item = candidate.deadline()
            item.id = UUID().uuidString
            snapshot.deadlines.append(item)
        }
        save(); reschedule()
        notice = t("已添加你选中的 \(candidates.count) 个截止日期。", "Added the \(candidates.count) deadlines you selected.")
    }
    func reloadCodexDisplay() {
        guard !isDemo, CodexDisplay.modifiedAt != codexModifiedAt || CodexDisplay.editsModifiedAt != codexEditsModifiedAt else { return }
        do {
            let base = try CodexDisplay.load()
            let edits = try CodexDisplay.loadEdits()
            codexDeadlines = base.filter { !edits.hidden.contains($0.id) }.map { edits.replacements[$0.id] ?? $0 }
            codexEdits = edits
            codexModifiedAt = CodexDisplay.modifiedAt
            codexEditsModifiedAt = CodexDisplay.editsModifiedAt
            if started { reschedule() }
        } catch {
            errorMessage = t("无法读取 Codex 附加任务文件。", "Could not read the Codex display file.")
        }
    }
    private func saveCodexUserChange(_ item: Deadline) {
        codexEdits.replacements[item.id] = item
        do {
            try CodexDisplay.saveEdits(codexEdits)
            codexEditsModifiedAt = nil
            reloadCodexDisplay()
        } catch { errorMessage = t("Codex 条目修改未能保存。", "Could not save the Codex entry change.") }
    }
    func delete(_ item: Deadline) {
        if isCodexDisplay(item) {
            codexEdits.hidden.insert(item.id)
            do {
                try CodexDisplay.saveEdits(codexEdits)
                codexEditsModifiedAt = nil
                reloadCodexDisplay()
            } catch { errorMessage = t("Codex 条目删除未能保存。", "Could not save the Codex entry deletion.") }
            return
        }
        snapshot.deadlines.removeAll { $0.id == item.id }; save(); reschedule()
    }
    func updatePreferences(_ value: Preferences) {
        guard value != snapshot.preferences else { return }
        snapshot.preferences = value; save(); reschedule()
    }
    func requestNotifications(test: Bool = false) async {
        guard !isDemo else { notice = t("演示模式不会发送通知。", "Demo mode does not send notifications."); return }
        do {
            let granted = try await notifications.requestPermission()
            notificationStatus = await notifications.authorization()
            if granted {
                var settings = preferences; settings.notificationsEnabled = true; updatePreferences(settings)
                if test { try await notifications.test(language: language); notice = t("5 秒后会收到测试通知，请检查屏幕右上角。", "A test notification will arrive in 5 seconds. Check the top-right corner of your screen.") }
            } else { notice = t("请在系统设置 → 通知 → 拾期中允许通知。", "Allow Shiqi notifications in System Settings → Notifications.") }
        } catch { errorMessage = t("无法安排通知：\(error.localizedDescription)", "Could not schedule notifications: \(error.localizedDescription)") }
    }
    func refreshPermission() async {
        guard !isDemo else { return }
        notificationStatus = await notifications.authorization(); reschedule()
    }
    private func reschedule() {
        guard !isDemo else { return }
        syncAppleReminders()
        let previousTask = schedulingTask
        previousTask?.cancel()
        let plans = ReminderPlanner.plans(for: displayedDeadlines, preferences: preferences, now: Date())
        let zone = preferences.timeZone; let enabled = preferences.notificationsEnabled
        schedulingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Finish an in-flight UNUserNotificationCenter.add before cancelling stale alerts.
                await previousTask?.value
                try Task.checkCancellation()
                if !enabled { await self.notifications.clear(); self.scheduledCount = 0; return }
                self.scheduledCount = try await self.notifications.reconcile(plans, zone: zone, language: self.language)
            } catch is CancellationError { }
            catch { self.errorMessage = t("提醒排程失败，请打开提醒设置重试。", "Could not schedule reminders. Open reminder settings and try again.") }
        }
    }
    @discardableResult
    private func save() -> Bool {
        guard !isDemo, canPersist else { return false }
        do { try LocalStorage.save(snapshot); return true }
        catch {
            errorMessage = t("数据保存失败，请检查磁盘空间和权限。当前窗口的数据尚未保存。", "Could not save data. Check disk space and permissions. Changes in this window have not been saved.")
            return false
        }
    }

    func setAppleRemindersEnabled(_ enabled: Bool) async {
        guard !isDemo else {
            appleRemindersError = t("演示模式不会访问真实的提醒事项。", "Demo mode does not access real Reminders."); return
        }
        guard !isRequestingRemindersAccess else { return }
        if !enabled {
            var settings = preferences; settings.appleRemindersEnabled = false
            updatePreferences(settings); appleRemindersError = nil
            return
        }
        isRequestingRemindersAccess = true
        defer { isRequestingRemindersAccess = false }
        do {
            guard try await appleRemindersService.requestPermission() else {
                appleRemindersError = t("请在系统设置 → 隐私与安全性 → 提醒事项中允许拾期访问，然后重新开启。", "Allow Shiqi in System Settings → Privacy & Security → Reminders, then enable sync again.")
                return
            }
            var settings = preferences; settings.appleRemindersEnabled = true
            appleRemindersError = nil; updatePreferences(settings)
        } catch {
            appleRemindersError = t("无法获得提醒事项权限，请检查系统设置后重试。", "Could not obtain Reminders access. Check System Settings and retry.")
        }
    }

    func syncAppleReminders() {
        let previousTask = appleRemindersTask
        previousTask?.cancel()
        guard !isDemo, canPersist, preferences.appleRemindersEnabled else {
            isSyncingAppleReminders = false; return
        }
        appleRemindersTask = Task { [weak self] in
            guard let self else { return }
            // Take the baseline after the preceding EventKit sync applies its result.
            await previousTask?.value
            guard !Task.isCancelled, self.preferences.appleRemindersEnabled else { return }
            self.isSyncingAppleReminders = true
            defer { self.isSyncingAppleReminders = false }
            guard self.save() else { return } // Persist migrated identities before exporting.
            let deadlines = self.snapshot.deadlines
            do {
                let result = try await self.appleRemindersService.reconcile(deadlines,
                    state: self.snapshot.appleReminders, timeZone: self.preferences.timeZone, language: self.language)
                var completionChanged = false
                for index in self.snapshot.deadlines.indices {
                    let item = self.snapshot.deadlines[index]
                    guard let original = deadlines.first(where: { $0.reminderID == item.reminderID }),
                          item.completed == original.completed,
                          let completed = result.completions[item.reminderID], completed != item.completed else { continue }
                    self.snapshot.deadlines[index].completed = completed; completionChanged = true
                }
                self.snapshot.appleReminders = result.state
                self.save()
                self.appleRemindersCount = result.count; self.appleRemindersLastSync = Date()
                self.appleRemindersError = nil
                // Cancel advance alerts when a task was completed in Reminders.
                if completionChanged { self.reschedule() }
            } catch is CancellationError { }
            catch { self.appleRemindersError = error.localizedDescription }
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                notice = t("请在系统设置 → 通用 → 登录项中允许拾期。", "Allow Shiqi in System Settings → General → Login Items.")
            }
            objectWillChange.send()
        } catch { errorMessage = t("无法修改登录启动设置。请先把拾期拖到「应用程序」文件夹，再重试。", "Could not change login settings. Move Shiqi to Applications and try again.") }
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval }

    func format(_ date: Date, pattern: String = "M月d日 EEEE HH:mm") -> String {
        let formatter = DateFormatter(); formatter.locale = language.locale; formatter.timeZone = preferences.timeZone
        formatter.dateFormat = language.datePattern(pattern); return formatter.string(from: date)
    }
    func countdown(_ item: Deadline) -> String {
        if item.completed { return t("已完成", "Completed") }
        if item.isOverdue(at: now, timeZone: preferences.timeZone) { return t("已逾期", "Overdue") }
        if !item.hasTime { return t("时间待确认", "Time to confirm") }
        let seconds = item.dueDate.timeIntervalSince(now)
        if seconds < 3600 {
            let minutes = max(1, Int(ceil(seconds / 60)))
            return t("剩余 \(minutes) 分钟", "\(minutes) min left")
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600); let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return t("剩余 \(hours) 小时 \(minutes) 分钟", "\(hours)h \(minutes)m left")
        }
        let days = Int(seconds / 86400)
        return t("剩余 \(days) 天", "\(days) \(days == 1 ? "day" : "days") left")
    }

    private func loadDemo() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = preferences.timeZone
        let day = calendar.startOfDay(for: now)
        func due(_ days: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: days, to: day)!)!
        }
        snapshot.deadlines = [
            Deadline(title: "Problem Set 03 · 概率与随机变量", course: "MAT2040 · Probability", notes: "演示数据。请以 Blackboard 课程中发布的要求为准。", dueDate: now.addingTimeInterval(7200), source: .blackboard),
            Deadline(title: "Assignment 02 · 数据结构", course: "CSC3100 · Data Structures", dueDate: due(1, 23, 59), source: .blackboard),
            Deadline(title: "Reading Response · 学术写作", course: "ENG1002 · English", dueDate: due(3, 17, 0), source: .blackboard),
            Deadline(title: "小组项目 · 提交选题", course: "DDA2001 · Data Science", dueDate: due(5, 0, 0), hasTime: false, source: .blackboard),
            Deadline(title: "Lab 01 · 实验报告", course: "CSC1001 · Introduction to CS", dueDate: due(-1, 23, 59), source: .blackboard),
            Deadline(title: "Quiz 01 · 线性代数", course: "MAT1002 · Linear Algebra", dueDate: due(-2, 18, 0), source: .blackboard, completed: true)
        ]
        snapshot.lastSync = now
    }
}
