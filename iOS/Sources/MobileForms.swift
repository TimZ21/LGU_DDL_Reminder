import SwiftUI
import UIKit
import DeadlineCore

struct MobileConnectionView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var showDisconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(store.text("使用 Blackboard 共享日历", "Use Blackboard's shared calendar"), systemImage: "calendar.badge.plus").font(.headline)
                    Text(store.text("在 Blackboard 中打开日历，选择「Get External Calendar Link / Share Calendar」，复制完整订阅链接。", "Open Calendar in Blackboard, choose Get External Calendar Link / Share Calendar, and copy the complete subscription URL."))
                    Link(store.text("打开 Blackboard", "Open Blackboard"), destination: URL(string: "https://bb.cuhk.edu.cn")!)
                }
                Section {
                    SecureField(store.text("粘贴完整日历订阅链接", "Paste the full calendar subscription URL"), text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).privacySensitive()
                    Button {
                        Task { if await store.connect(address) { address = ""; dismiss() } }
                    } label: {
                        HStack { Text(store.text("连接并同步", "Connect and sync")); Spacer(); if store.isSyncing { ProgressView() } }
                    }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSyncing || store.isDemo)
                } footer: { Text(store.text("链接含私人令牌，只保存在此设备的系统钥匙串。请勿公开或上传 GitHub。需要时使用校园网或 VPN。", "The URL contains a private token and is stored only in this device's Keychain. Keep it private and out of GitHub. Use campus network or VPN if required.")) }
                if store.isConnected {
                    Section {
                        Label(store.text("已连接", "Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(MobilePalette.purple)
                        Button(store.text("断开订阅", "Disconnect subscription"), role: .destructive) { showDisconnect = true }.disabled(store.isSyncing)
                    } footer: { Text(store.text("断开后仍保留现有 DDL、完成状态和已安排的提醒。", "Disconnecting keeps existing deadlines, completion status, and scheduled alerts.")) }
                }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(store.text("连接日历", "Connect calendar")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.text("完成", "Done")) { dismiss() }.disabled(store.isSyncing).accessibilityIdentifier("connection.done") } }
                .interactiveDismissDisabled(store.isSyncing)
                .confirmationDialog(store.text("断开当前订阅？", "Disconnect this subscription?"), isPresented: $showDisconnect, titleVisibility: .visible) {
                    Button(store.text("断开订阅", "Disconnect"), role: .destructive) { store.disconnect(); dismiss() }
                }
        }
    }
}

struct MobileEditorView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private let existing: Deadline?
    @State private var title: String
    @State private var course: String
    @State private var notes: String
    @State private var due: Date
    @State private var hasTime: Bool
    init(item: Deadline? = nil) {
        existing = item
        _title = State(initialValue: item?.title ?? "")
        _course = State(initialValue: item?.course ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _due = State(initialValue: item?.dueDate ?? Date().addingTimeInterval(86400))
        _hasTime = State(initialValue: item?.hasTime ?? true)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.text("任务名称", "Task title"), text: $title).accessibilityIdentifier("editor.title")
                    TextField(store.text("课程（可选）", "Course (optional)"), text: $course).accessibilityIdentifier("editor.course")
                }
                Section {
                    Toggle(store.text("有具体截止时间", "Has a specific deadline time"), isOn: $hasTime)
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.text("截止日期", "Due date")).font(.headline)
                            DatePicker(store.text("截止日期", "Due date"), selection: $due, displayedComponents: [.date])
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                        }
                        if hasTime {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.text("截止时间", "Due time")).font(.headline)
                                DatePicker(store.text("截止时间", "Due time"), selection: $due, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        DatePicker(store.text("截止日期", "Due date"), selection: $due, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    }
                    Text(store.preferences.timeZoneLabel).font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text(store.text("仅日期任务不会被当作零点截止；将在前一天和当天上午 9 点提醒。", "Date-only tasks are not treated as midnight deadlines. Alerts are at 9 AM the day before and on the due date."))
                }
                Section(store.text("备注", "Notes")) { TextEditor(text: $notes).frame(minHeight: 100).accessibilityIdentifier("editor.notes") }
            }.navigationTitle(store.text(existing == nil ? "添加 DDL" : "编辑 DDL", existing == nil ? "Add deadline" : "Edit deadline")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(store.text("取消", "Cancel")) { dismiss() }.accessibilityIdentifier("editor.cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(store.text("保存", "Save")) {
                            var item = existing ?? Deadline(title: title, dueDate: due)
                            item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            item.course = course.trimmingCharacters(in: .whitespacesAndNewlines); item.notes = notes
                            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = store.preferences.timeZone
                            item.dueDate = hasTime ? (calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)) ?? due) : calendar.startOfDay(for: due)
                            item.hasTime = hasTime
                            store.saveManual(item); dismiss()
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("editor.save")
                    }
                }
        }
    }
}

struct MobileDetailView: View {
    let reminderID: String
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var edit = false
    @State private var delete = false
    private var item: Deadline? { store.deadlines.first { $0.reminderID == reminderID } }
    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        if !item.course.isEmpty { Text(item.course).foregroundStyle(.secondary).textSelection(.enabled) }
                        Label(store.dateLabel(item, long: true), systemImage: "calendar").foregroundStyle(MobilePalette.purple)
                        Text(store.preferences.timeZoneLabel).font(.caption).foregroundStyle(.secondary)
                        Button { store.toggle(item) } label: {
                            Label(store.text(item.completed ? "恢复待办" : "标记完成", item.completed ? "Mark incomplete" : "Mark complete"), systemImage: item.completed ? "arrow.uturn.backward" : "checkmark.circle")
                        }
                    }
                    if !item.notes.isEmpty { Section(store.text("备注", "Notes")) { Text(item.notes).textSelection(.enabled) } }
                    Section {
                        Text(store.text("来源：", "Source: ") + sourceName(item.source)).font(.caption).foregroundStyle(.secondary)
                        if let link = item.link, ["https", "http"].contains(link.scheme?.lowercased() ?? "") {
                            Link(store.text("查看原任务", "Open original task"), destination: link)
                        }
                        if item.source == .manual {
                            Button(store.text("编辑", "Edit")) { edit = true }
                            Button(store.text("删除任务", "Delete task"), role: .destructive) { delete = true }
                        }
                    }
                }
            }.navigationTitle(store.text("DDL 详情", "Deadline details")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.text("完成", "Done")) { dismiss() }.accessibilityIdentifier("detail.done") } }
                .sheet(isPresented: $edit) { if let item { MobileEditorView(item: item) } }
                .confirmationDialog(store.text("删除这条手动任务？", "Delete this manual deadline?"), isPresented: $delete, titleVisibility: .visible) {
                    Button(store.text("删除", "Delete"), role: .destructive) { if let item { store.deleteManual(item) }; dismiss() }
                }
        }
    }
    private func sourceName(_ source: DeadlineSource) -> String {
        switch source { case .blackboard: return "Blackboard"; case .file: return store.text("日历文件", "Calendar file"); case .manual: return store.text("手动添加", "Manual") }
    }
}
