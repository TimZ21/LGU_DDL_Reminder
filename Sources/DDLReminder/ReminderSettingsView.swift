import SwiftUI
import AppKit
import DeadlineCore

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = Preferences()
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(store.t("提醒与设置", "Reminders & settings")).font(.system(size: 23, weight: .semibold)); Spacer(); Button(store.t("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(store.t("让重要的时间，提前一点到达", "A little notice goes a long way")).font(.headline)
                        Toggle(store.t("发送系统通知", "Send system notifications"), isOn: $preferences.notificationsEnabled)
                        HStack(spacing: 16) {
                            ForEach([1440, 180, 60, 30, 10, 0], id: \.self) { minutes in
                                Toggle(minutes == 0 ? store.t("到期时", "At due time") : store.language.duration(minutes), isOn: Binding(
                                    get: { preferences.reminderMinutes.contains(minutes) },
                                    set: { value in
                                        preferences.reminderMinutes.removeAll { $0 == minutes }
                                        if value { preferences.reminderMinutes.append(minutes) }
                                    }
                                ))
                            }
                        }.toggleStyle(.checkbox).font(.system(size: 12))
                        Text(store.t("只有日期的事项，在前一天和当天 09:00 提醒，并注明具体时间待确认。", "Date-only items are reminded at 09:00 the day before and on the due date, with the time marked unconfirmed."))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(store.t("允许通知 / 发送测试通知", "Allow / test notifications")) { Task { await store.requestNotifications(test: true) } }
                            Spacer()
                            Text(store.t("已安排 \(store.scheduledCount) 条近期提醒", "\(store.scheduledCount) upcoming reminders scheduled")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(Palette.accent) }
                        if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                    }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 12) {
                        Label(store.t("macOS 提醒事项", "macOS Reminders"), systemImage: "checklist").font(.headline)
                        Toggle(store.t("同步 DDL 到提醒事项", "Sync deadlines to Reminders"), isOn: Binding(
                            get: { store.preferences.appleRemindersEnabled },
                            set: { enabled in Task { await store.setAppleRemindersEnabled(enabled) } }
                        )).disabled(store.isRequestingRemindersAccess)
                        Text(store.t("自动同步到「拾期 · DDL」专用列表，包含课程、备注、截止日期和具体时间。完成与恢复待办状态可在两边同步。", "Syncs to the dedicated 拾期 · DDL list with courses, notes, due dates, and exact times. Completion and reopening sync in both directions."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(store.t("拾期运行时每分钟检查；任务内容以拾期为准。关闭同步会保留已导出的事项，其他列表不受影响。", "Checks every minute while Shiqi runs; task details come from Shiqi. Turning sync off keeps exported tasks; other lists are unaffected."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(store.t("提醒事项会在具体截止时间提醒；若开启两种通知，可能收到重复提醒。使用 iCloud 列表时，导出的课程数据会通过你的 iCloud 同步。", "Reminders alerts at exact due times; enabling both notification systems may produce duplicate alerts. An iCloud list syncs exported course data through your iCloud account."))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(store.t("立即同步到提醒事项", "Sync to Reminders now")) { store.syncAppleReminders() }
                                .disabled(!store.preferences.appleRemindersEnabled || store.isSyncingAppleReminders)
                            Button(store.t("打开提醒事项", "Open Reminders")) {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                                }
                            }
                            Spacer()
                            if store.isRequestingRemindersAccess || store.isSyncingAppleReminders { ProgressView().controlSize(.small) }
                            else if store.preferences.appleRemindersEnabled, store.appleRemindersLastSync != nil {
                                Text(store.t("已同步 \(store.appleRemindersCount) 个事项", "\(store.appleRemindersCount) tasks synced"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let error = store.appleRemindersError { Text(error).font(.caption).foregroundStyle(.orange) }
                    }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    Form {
                        Picker("语言 / Language", selection: $preferences.language) {
                            Text("简体中文").tag(AppLanguage.chinese)
                            Text("English").tag(AppLanguage.english)
                        }
                        Picker(store.t("显示与默认解析时区", "Display & default time zone"), selection: $preferences.timeZoneID) {
                            Text(store.t("深圳 (UTC+8)", "Shenzhen (UTC+8)")).tag("Asia/Shanghai")
                            Text(store.t("香港 (UTC+8)", "Hong Kong (UTC+8)")).tag("Asia/Hong_Kong")
                            if !["Asia/Shanghai", "Asia/Hong_Kong"].contains(TimeZone.current.identifier) {
                                Text(store.t("系统时区 · \(store.language.timeZoneName(TimeZone.current.identifier))", "System time zone · \(store.language.timeZoneName(TimeZone.current.identifier))")).tag(TimeZone.current.identifier)
                            }
                        }
                        Picker(store.t("自动同步", "Auto-sync"), selection: $preferences.syncMinutes) {
                            ForEach([5, 15, 30, 60], id: \.self) { Text(store.t("每 \($0) 分钟", "Every \($0) minutes")).tag($0) }
                        }
                        Toggle(store.t("登录 Mac 时启动拾期", "Launch Shiqi at login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Label(store.t("关闭窗口后，菜单栏继续运行并自动同步。", "Closing the window keeps Shiqi running and syncing in the menu bar."), systemImage: "menubar.rectangle")
                        Text(store.t("系统负责已排程的通知；退出应用会停止同步。Mac 关机时无法提醒，睡眠或专注模式也可能延迟通知。", "macOS delivers scheduled notifications. Quitting stops sync; shutdown prevents alerts, and sleep or Focus can delay them."))
                        Text(store.t("更改时区不会改变已有任务的实际截止时刻；无时区的日历时间会在下次同步时按所选时区解析。", "Changing the display zone keeps existing deadline instants intact. Calendar dates without a time zone use this setting on the next sync."))
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        AppMark().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.t("给龙大学子的免费开源软件", "Free, open-source software for LGU students")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
                            Text(store.t("独立开发 · MIT License · 非学校官方产品，未经校方背书", "Independent project · MIT License · Not an official or university-endorsed product"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    Text(store.t("拾期 1.2.0 · 原生 macOS 应用 · 可选同步到提醒事项", "Shiqi 1.2.0 · Native macOS app · Optional Reminders sync"))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(2)
            }
        }.padding(26).frame(width: 740, height: 680).tint(Palette.controlAccent)
            .onAppear { preferences = store.preferences; loaded = true }
            .onChange(of: preferences) { if loaded { store.updatePreferences($0) } }
            .onChange(of: store.preferences) { if loaded, preferences != $0 { preferences = $0 } }
    }
}
