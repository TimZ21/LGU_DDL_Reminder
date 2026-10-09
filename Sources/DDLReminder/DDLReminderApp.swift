import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .showDeadlineWindow, object: nil); return true
    }
}

@main
struct DDLReminderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        Window(store.t("拾期 · DDL", "Shiqi · DDL"), id: "main") {
            DashboardView().environmentObject(store)
                .environment(\.locale, store.language.locale)
                .task { await store.start() }
        }
        .defaultSize(width: 1080, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(store.t("添加截止日期", "Add deadline")) { store.editingDeadline = nil; store.showEditor = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appSettings) {
                Button(store.t("提醒设置…", "Reminder settings…")) { store.showSettings = true }.keyboardShortcut(",")
                Button(store.t("同步 Blackboard", "Sync Blackboard")) { Task { await store.sync() } }.keyboardShortcut("r")
                    .disabled(!store.isConnected || store.isSyncing)
            }
        }
        MenuBarExtra {
            MenuPanel().environmentObject(store)
                .environment(\.locale, store.language.locale)
        } label: {
            Image(systemName: "calendar.badge.clock")
            if !store.nextDay.isEmpty { Text("\(store.nextDay.count)") }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.t("拾期", "Shiqi"), systemImage: "calendar.badge.clock").font(.headline)
                Spacer()
                Text(store.t("\(store.upcoming.count) 待办", "\(store.upcoming.count) upcoming")).foregroundStyle(.secondary).font(.caption)
            }
            Divider()
            if store.upcoming.isEmpty {
                Text(store.isConnected ? store.t("目前没有待办事项", "No upcoming tasks") : store.t("连接 Blackboard，开始记录截止日期", "Connect Blackboard to track your deadlines"))
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(Array(store.upcoming.prefix(4))) { item in
                    Button {
                        openDashboard()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(store.format(item.dueDate, pattern: item.hasTime ? "M/d E HH:mm" : "M/d E · 时间待确认"))
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            if !store.overdue.isEmpty {
                Label(store.t("\(store.overdue.count) 个事项已逾期", "\(store.overdue.count) overdue tasks"), systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button(store.t("打开拾期", "Open Shiqi")) { openDashboard() }.buttonStyle(PrimaryButtonStyle()).tint(Palette.controlAccent)
                Button { Task { await store.sync() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .disabled(!store.isConnected || store.isSyncing)
                Spacer()
                Button(store.t("退出", "Quit")) { NSApp.terminate(nil) }.foregroundStyle(.secondary)
            }
            Text(store.t("显示时区：\(store.preferences.timeZoneLabel)", "Time zone: \(store.preferences.timeZoneLabel)")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(18).frame(width: 320)
    }
    private func openDashboard() { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
}
