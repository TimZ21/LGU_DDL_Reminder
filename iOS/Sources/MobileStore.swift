import Foundation
import Combine
import UserNotifications
import EventKit
import DeadlineCore

@MainActor
final class MobileStore: ObservableObject {
    static let shared = MobileStore()
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount = 0
    @Published private(set) var remindersCount = 0
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var now = Date()
    var isForeground = true
    let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private var feedURL: URL?
    private var started = false
    private var storageHealthy = true
    private let notifications = NotificationService()
    private let reminders = AppleRemindersService()
    private let client = FeedClient()
    private var reconcileTask: Task<Void, Never>?
    private var reconcileNeeded = false
    private var revision = 0
    private var completionRevisions: [String: Int] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: AnyCancellable?
    var language: AppLanguage { snapshot.preferences.language }
    var preferences: Preferences { snapshot.preferences }
    var deadlines: [Deadline] { snapshot.deadlines }
    var warnings: [String] { snapshot.warnings }
    func text(_ zh: String, _ en: String) -> String { language.text(zh, en) }

    init() {
        do {
            if isDemo { snapshot = Self.demoSnapshot() }
            else if isUITesting {
                if ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
                    snapshot = Snapshot()
                } else if FileManager.default.fileExists(atPath: Self.testURL.path) {
                    snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: Self.testURL))
                }
            } else { snapshot = try LocalStorage.load() }
            #if DEBUG
            if isUITesting, ProcessInfo.processInfo.arguments.contains("--layout-fixture") {
                snapshot = Self.demoSnapshot()
                snapshot.deadlines.insert(Deadline(
                    title: "Final research project: literature review, experiment analysis and revised submission / 期末研究项目：文献综述、实验分析与修订报告",
                    course: "CSC3000 · Advanced Research Methods and Interdisciplinary Data Analysis",
                    notes: String(repeating: "Check figures and references before submitting. 提交前检查图表与参考文献。\n", count: 8),
                    dueDate: Date().addingTimeInterval(3600)), at: 0)
            }
            #endif
        } catch {
            storageHealthy = false
            errorMessage = text("本地数据无法读取。为保护原有数据，已停止保存。请保留备份后重新安装或恢复数据。", "Local data could not be read. Saving has stopped to protect it. Preserve your backup before reinstalling or restoring data.")
        }
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self, self.isForeground else { return }
            self.now = date
            Task { await self.activate() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.enqueueReconciliation() }
        })
    }

    func start(refresh: Bool = true) async {
        guard !started else { return }; started = true
        guard !isDemo, !isUITesting, storageHealthy else { return }
        do {
            if let link = try Keychain.read(language: language) {
                feedURL = try FeedAddress.validate(link, language: language); isConnected = true
            }
        } catch { report(error) }
        if refresh { await activate() }
    }
    func activate() async {
        isForeground = true; now = Date()
        guard started, !isDemo, !isUITesting, storageHealthy else { return }
        notificationStatus = await notifications.authorization()
        if isConnected, !isSyncing, snapshot.lastSync.map({ now.timeIntervalSince($0) >= Double(preferences.syncMinutes * 60) }) ?? true {
            await synchronize()
        } else { await reconcileNow() }
    }
    func connect(_ address: String) async -> Bool {
        guard !isSyncing, storageHealthy, !isDemo, !isUITesting else { return false }
        isSyncing = true; defer { isSyncing = false }
        do {
            let url = try FeedAddress.validate(address, language: language)
            let content = try await client.fetch(url, language: language)
            let parsed = try parse(content, source: .blackboard)
            try Task.checkCancellation()
            try Keychain.write(url.absoluteString, language: language)
            feedURL = url; isConnected = true
            merge(parsed, source: .blackboard)
            statusMessage = text("日历已连接。", "Calendar connected.")
            await reconcileNow(); MobileBackgroundRefresh.schedule()
            return true
        } catch { report(error); return false }
    }
    func synchronize() async {
        guard !isSyncing, storageHealthy, !isDemo, !isUITesting, let url = feedURL else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            let content = try await client.fetch(url, language: language)
            let parsed = try parse(content, source: .blackboard)
            try Task.checkCancellation()
            merge(parsed, source: .blackboard)
            await reconcileNow()
        } catch { report(error) }
    }
    func disconnect() {
        guard !isSyncing, !isDemo, !isUITesting else { return }
        do {
            try Keychain.delete(language: language)
            feedURL = nil; isConnected = false; MobileBackgroundRefresh.cancel()
            statusMessage = text("已断开订阅。现有 DDL 和提醒已保留。", "Subscription disconnected. Existing deadlines and alerts are kept.")
        } catch { report(error) }
    }
    func refreshInBackground() async -> Bool {
        await start(refresh: false)
        isForeground = false
        guard !Task.isCancelled, isConnected, !isSyncing else { return false }
        let previous = snapshot.lastSync
        await synchronize()
        return !Task.isCancelled && snapshot.lastSync != previous
    }
    private func parse(_ content: String, source: DeadlineSource) throws -> ParsedCalendar {
        try ICalendarParser(language: language).parse(content, source: source, defaultTimeZone: preferences.timeZone, now: Date())
    }
    private func merge(_ parsed: ParsedCalendar, source: DeadlineSource) {
        snapshot.deadlines = DeadlineMerger.merge(previous: deadlines, parsed: parsed, source: source, removeMissing: source == .blackboard)
        snapshot.warnings = parsed.warnings
        if source == .blackboard { snapshot.lastSync = Date() }
        changed()
    }
    func importFile(_ url: URL) {
        guard storageHealthy else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5 * 1024 * 1024 else { throw CalendarError.message(text("日历超过 5 MB。", "The calendar exceeds 5 MB.")) }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 5 * 1024 * 1024, let content = String(data: data, encoding: .utf8) else {
                throw CalendarError.message(text("请选择小于 5 MB 的 UTF-8 .ics 日历。", "Choose a UTF-8 .ics calendar under 5 MB."))
            }
            merge(try parse(content, source: .file), source: .file)
            statusMessage = text("日历文件已导入。", "Calendar file imported.")
        } catch { report(error) }
    }
    func saveManual(_ item: Deadline) {
        guard storageHealthy else { return }
        if let index = snapshot.deadlines.firstIndex(where: { $0.id == item.id && $0.source == .manual }) {
            snapshot.deadlines[index] = item
        } else { snapshot.deadlines.append(item) }
        snapshot.deadlines.sort { $0.dueDate < $1.dueDate }; changed()
    }
    func toggle(_ item: Deadline) {
        guard storageHealthy, let index = snapshot.deadlines.firstIndex(where: { $0.id == item.id }) else { return }
        snapshot.deadlines[index].completed.toggle()
        completionRevisions[item.reminderID] = revision + 1
        changed()
    }
    func deleteManual(_ item: Deadline) {
        guard storageHealthy, item.source == .manual else { return }
        snapshot.deadlines.removeAll { $0.id == item.id }; changed()
    }
    func updatePreferences(_ update: (inout Preferences) -> Void) {
        guard storageHealthy else { return }
        update(&snapshot.preferences); changed(); MobileBackgroundRefresh.schedule()
    }
    func requestNotifications(test: Bool = false) async {
        guard !isDemo, !isUITesting else { return }
        do {
            if try await notifications.requestPermission() {
                updatePreferences { $0.notificationsEnabled = true }
                await reconcileNow()
                if test { try await notifications.test(language: language) }
            } else { errorMessage = text("请在 iPhone 设置 → 通知 → 拾期中开启通知。", "Enable Shiqi notifications in iPhone Settings → Notifications.") }
            notificationStatus = await notifications.authorization()
        } catch { report(error) }
    }
    func setRemindersEnabled(_ enabled: Bool) async {
        guard !isDemo, !isUITesting else { return }
        if !enabled { updatePreferences { $0.appleRemindersEnabled = false }; return }
        do {
            guard try await reminders.requestPermission() else { throw CalendarError.message(text("请在 iPhone 设置中允许拾期访问提醒事项。", "Allow Shiqi access to Reminders in iPhone Settings.")) }
            updatePreferences { $0.appleRemindersEnabled = true }
            await reconcileNow()
        } catch { report(error) }
    }
    private func changed() { revision += 1; persist(); enqueueReconciliation() }
    private static var testURL: URL { LocalStorage.directory.appendingPathComponent("uitesting.json") }
    private func persist() {
        guard storageHealthy, !isDemo else { return }
        do {
            if isUITesting {
                try FileManager.default.createDirectory(at: LocalStorage.directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: Self.testURL, options: .atomic)
            } else { try LocalStorage.save(snapshot) }
        } catch { errorMessage = text("无法保存更改，请检查设备存储空间。", "Could not save changes. Check device storage.") }
    }
    private func enqueueReconciliation() {
        guard !isDemo, !isUITesting, storageHealthy else { return }
        reconcileNeeded = true
        guard reconcileTask == nil else { return }
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            while self.reconcileNeeded && !Task.isCancelled {
                self.reconcileNeeded = false
                await self.reconcilePass()
            }
            self.reconcileTask = nil
        }
    }
    func cancelBackgroundRefresh() { reconcileTask?.cancel() }
    private func reconcileNow() async {
        enqueueReconciliation()
        await reconcileTask?.value
    }
    private func reconcilePass() async {
        let captured = snapshot
        let capturedRevision = revision
        let capturedCompletionRevisions = completionRevisions
        do {
            if captured.preferences.appleRemindersEnabled {
                let result = try await reminders.reconcile(captured.deadlines, state: captured.appleReminders,
                                                          timeZone: captured.preferences.timeZone, language: captured.preferences.language)
                // A user change made while EventKit was fetching must win on the next pass.
                let originals = Dictionary(uniqueKeysWithValues: captured.deadlines.map { ($0.reminderID, $0.completed) })
                for index in snapshot.deadlines.indices {
                    let item = snapshot.deadlines[index]
                    if completionRevisions[item.reminderID] == capturedCompletionRevisions[item.reminderID],
                       item.completed == originals[item.reminderID], let completion = result.completions[item.reminderID] {
                        snapshot.deadlines[index].completed = completion
                    }
                }
                snapshot.appleReminders = result.state; remindersCount = result.count; persist()
            } else { remindersCount = 0 }
        } catch { report(error) }
        do {
            let current = snapshot
            scheduledCount = try await notifications.reconcile(ReminderPlanner.plans(for: current.deadlines, preferences: current.preferences, now: Date()),
                                                              zone: current.preferences.timeZone, language: current.preferences.language)
        } catch { report(error) }
        if capturedRevision != revision { reconcileNeeded = true }
    }
    private func report(_ error: Error) {
        if error is CancellationError || Task.isCancelled { return }
        errorMessage = (error as? CalendarError)?.localizedDescription ?? text("操作失败。请检查权限、网络和设备存储后重试。", "The operation failed. Check access, network, and device storage, then retry.")
    }
    func dateLabel(_ item: Deadline, long: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = language.locale; formatter.timeZone = preferences.timeZone
        formatter.dateFormat = language == .chinese
            ? (long ? "yyyy年M月d日 EEEE" : "M月d日 EEEE") + (item.hasTime ? " HH:mm" : " · 时间待确认")
            : (long ? "EEEE, d MMMM yyyy" : "EEE, d MMM") + (item.hasTime ? " HH:mm" : " '· Time to confirm'")
        return formatter.string(from: item.dueDate)
    }
    func syncLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = language.locale; formatter.timeZone = preferences.timeZone
        formatter.dateStyle = .short; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private static func demoSnapshot() -> Snapshot {
        var result = Snapshot()
        let day = Calendar.current.startOfDay(for: Date())
        result.deadlines = [
            Deadline(title: "概率论 · 第三次作业", course: "MAT2040", notes: "提交 PDF 到 Blackboard。", dueDate: day.addingTimeInterval(2 * 86400 + 23 * 3600 + 59 * 60), source: .blackboard),
            Deadline(title: "Research proposal", course: "ENG2001", dueDate: day.addingTimeInterval(4 * 86400 + 18 * 3600), source: .file),
            Deadline(title: "小组展示", course: "CSC1001", dueDate: day.addingTimeInterval(6 * 86400), hasTime: false),
            Deadline(title: "Linear algebra worksheet", course: "MAT1001", dueDate: day.addingTimeInterval(-86400 + 18 * 3600), source: .blackboard),
            Deadline(title: "实验报告", course: "PHY1001", dueDate: day.addingTimeInterval(86400 + 12 * 3600), completed: true)
        ]
        return result
    }
    #if DEBUG
    func importTestingFixture(regenerated: Bool) {
        guard isUITesting else { return }
        do {
            let content = "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:mobile-\(regenerated ? "new" : "old")\nSUMMARY:Fixture assignment\nDTSTART;TZID=Asia/Shanghai:20271130T235900\nEND:VEVENT\nEND:VCALENDAR"
            merge(try parse(content, source: .file), source: .file)
        } catch { report(error) }
    }
    #endif
}
