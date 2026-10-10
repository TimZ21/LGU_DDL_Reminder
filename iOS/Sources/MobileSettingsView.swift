import SwiftUI
import UIKit
import UserNotifications
import DeadlineCore

struct MobileSettingsView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var remindersBusy = false
    private var notificationLabel: String {
        switch store.notificationStatus {
        case .authorized, .provisional, .ephemeral: return store.text("已允许", "Allowed")
        case .denied: return store.text("未允许", "Not allowed")
        default: return store.text("尚未申请", "Not requested")
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("语言", "Language")) {
                    Picker(store.text("界面语言", "App language"), selection: Binding(get: { store.language }, set: { value in store.updatePreferences { $0.language = value } })) {
                        Text("简体中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.language")
                }
                Section {
                    Toggle(store.text("开启 DDL 通知", "Deadline notifications"), isOn: Binding(get: { store.preferences.notificationsEnabled }, set: { value in store.updatePreferences { $0.notificationsEnabled = value } }))
                    LabeledContent(store.text("系统权限", "System permission"), value: notificationLabel)
                    Button(store.text("申请权限并测试通知", "Allow and test notifications")) { Task { await store.requestNotifications(test: true) } }.disabled(store.isDemo)
                    if store.notificationStatus == .denied {
                        Button(store.text("打开系统设置", "Open Settings")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                    ForEach([1440, 360, 180, 60, 30, 0], id: \.self) { minutes in
                        Toggle(minutes == 0 ? store.text("截止时", "At deadline") : store.text("提前 ", "Before: ") + store.language.duration(minutes), isOn: Binding(get: { store.preferences.reminderMinutes.contains(minutes) }, set: { enabled in
                            store.updatePreferences { preferences in
                                preferences.reminderMinutes.removeAll { $0 == minutes }
                                if enabled { preferences.reminderMinutes.append(minutes) }
                            }
                        }))
                    }.disabled(!store.preferences.notificationsEnabled)
                    LabeledContent(store.text("已安排的通知", "Scheduled alerts"), value: "\(store.scheduledCount)")
                } header: { Text(store.text("通知提醒", "Notifications")) } footer: { Text(store.text("测试通知将在 5 秒后出现。最多优先安排最近 60 条提醒；打开 App 或后台刷新时会补充。已安排的本地通知不需要 App 保持打开。", "The test arrives in 5 seconds. The next 60 alerts are scheduled first and replenished when the app opens or refreshes in the background. Scheduled local alerts do not require the app to stay open.")) }
                Section {
                    Toggle(store.text("同步到提醒事项", "Sync to Reminders"), isOn: Binding(get: { store.preferences.appleRemindersEnabled }, set: { value in
                        remindersBusy = true
                        Task { await store.setRemindersEnabled(value); remindersBusy = false }
                    })).disabled(remindersBusy || store.isDemo)
                    if remindersBusy { ProgressView() }
                    LabeledContent(store.text("专用列表", "Dedicated list"), value: AppleRemindersService.listTitle)
                    if store.preferences.appleRemindersEnabled { LabeledContent(store.text("已同步事项", "Synced items"), value: "\(store.remindersCount)") }
                } header: { Text(store.text("Apple 提醒事项", "Apple Reminders")) } footer: { Text(store.text("开启后会请求系统权限。完成状态在此 App 与手机专用列表之间同步；关闭后保留已有提醒事项。使用 iCloud 账户时，列表可显示在其他 Apple 设备上。手机和 Mac 的导入数据各自独立，使用不同列表。", "Enabling requests system access. Completion syncs between this app and its phone list. Turning it off keeps existing reminders. An iCloud list can appear on other Apple devices. Phone and Mac imports are independent and use separate lists.")) }
                Section {
                    LabeledContent(store.text("显示时区", "Display time zone"), value: store.preferences.timeZoneLabel)
                    Picker(store.text("刷新间隔", "Refresh interval"), selection: Binding(get: { store.preferences.syncMinutes }, set: { value in store.updatePreferences { $0.syncMinutes = value } })) {
                        ForEach([15, 30, 60], id: \.self) { Text(store.language.duration($0)).tag($0) }
                    }
                    Button(store.text("现在同步", "Sync now")) { Task { await store.synchronize() } }.disabled(!store.isConnected || store.isSyncing)
                } header: { Text(store.text("同步与时间", "Sync and time")) } footer: { Text(store.text("App 打开时按间隔刷新，也可下拉同步。后台刷新由 iOS 决定，不能保证固定间隔；强制关闭 App 或关闭后台刷新会影响新 DDL 的获取。", "While open, the app refreshes at this interval; pull down to sync. iOS decides when background refresh runs, so intervals are not guaranteed. Force-quitting or disabling background refresh affects new deadline imports.")) }
                Section(store.text("关于拾期", "About Shiqi")) {
                    Text(store.text("给龙大学子的免费开源软件", "Free, open-source software for LGU students")).font(.headline)
                    Text(store.text("龙大是港中深学生使用的「龙岗大学」昵称，英文简称 LGU。拾期为独立学生项目，与学校无隶属或官方授权关系。", "LGU means Longgang University, a student nickname for CUHK-Shenzhen in Longgang. Shiqi is an independent student project, without university affiliation or endorsement.")).font(.footnote).foregroundStyle(.secondary)
                    LabeledContent(store.text("iOS 版本", "iOS version"), value: "1.0.0")
                    Link(store.text("GitHub 源码 · MIT 许可证", "GitHub source · MIT license"), destination: URL(string: "https://github.com/TimZ21/LGU_DDL_Reminder")!)
                }
            }.navigationTitle(store.text("设置", "Settings")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.text("完成", "Done")) { dismiss() }.accessibilityIdentifier("settings.done") } }
        }
    }
}
