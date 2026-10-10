import SwiftUI
import DeadlineCore

struct DeadlineEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: Deadline?
    @State private var title = ""
    @State private var course = ""
    @State private var notes = ""
    @State private var date = Date().addingTimeInterval(86400)
    @State private var hasTime = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(item == nil ? store.t("添加截止日期", "Add deadline") : store.t("编辑截止日期", "Edit deadline")).font(.system(size: 23, weight: .semibold))
            Form {
                TextField(store.t("任务名称", "Task name"), text: $title)
                TextField(store.t("课程（可选）", "Course (optional)"), text: $course)
                Toggle(store.t("知道具体截止时间", "Exact due time is known"), isOn: $hasTime)
                DatePicker(store.t("截止日期", "Due date"), selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    .environment(\.timeZone, store.preferences.timeZone).environment(\.locale, store.language.locale)
                Text(store.t("时区：\(store.preferences.timeZoneLabel)", "Time zone: \(store.preferences.timeZoneLabel)")).font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("备注", "Notes")).font(.callout)
                TextEditor(text: $notes).font(.callout).frame(height: 90).padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            HStack {
                Button(store.t("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("保存", "Save")) { save() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 510).tint(Palette.controlAccent)
            .onAppear {
                if let item { title = item.title; course = item.course; notes = item.notes; date = item.dueDate; hasTime = item.hasTime }
            }
    }
    private func save() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = store.preferences.timeZone
        let due = hasTime ? date : calendar.startOfDay(for: date)
        let new = Deadline(id: item?.id ?? UUID().uuidString, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                           course: course.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
                           dueDate: due, hasTime: hasTime, source: item?.source ?? .manual,
                           link: item?.link, completed: item?.completed ?? false)
        store.upsert(new); dismiss()
    }
}

struct DeadlineDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var showEdit = false
    @State private var showCourseEdit = false
    @State private var confirmDelete = false
    private var item: Deadline? { store.displayedDeadlines.first { $0.id == itemID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let item {
                HStack { Text(store.t("事项详情", "Task details")).font(.headline); Spacer(); Button(store.t("关闭", "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
                Text(item.title).font(.system(size: 23, weight: .semibold)).textSelection(.enabled)
                Text(item.course.isEmpty ? store.t("课程未标注", "Course not specified") : item.course)
                    .foregroundStyle(.secondary).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.format(item.dueDate, pattern: item.hasTime ? "yyyy年M月d日 EEEE HH:mm:ss" : "yyyy年M月d日 EEEE"), systemImage: "calendar")
                        .font(.system(size: 18, weight: .medium)).textSelection(.enabled)
                    Text(item.hasTime ? store.t("时区：\(store.preferences.timeZoneLabel) · \(store.countdown(item))", "Time zone: \(store.preferences.timeZoneLabel) · \(store.countdown(item))") : store.t("只提供日期，具体几点待确认；不会假设是 23:59。", "Only a date is provided. Confirm the exact time; 23:59 is not assumed."))
                        .font(.caption).foregroundStyle(item.hasTime ? Color.secondary : Color.orange)
                    Text(store.t("来源：\(sourceName(item.source))", "Source: \(sourceName(item.source))")).font(.caption).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                if !item.notes.isEmpty {
                    ScrollView { Text(item.notes).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                }
                Text(store.t("「已完成」不代表 Blackboard 已提交或已评分；开启提醒事项同步后，完成状态会在两边同步。", "Completion does not mean submitted or graded in Blackboard. With Reminders sync enabled, completion syncs in both directions."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(item.completed ? store.t("设为待办", "Mark incomplete") : store.t("标记已完成", "Mark complete")) { store.toggle(item) }.buttonStyle(PrimaryButtonStyle())
                    if store.isCodexDisplay(item) || item.source == .manual || item.source == .outlook {
                        Button(store.t("编辑", "Edit")) { showEdit = true }
                        Button(store.t("删除", "Delete"), role: .destructive) { confirmDelete = true }
                    } else {
                        Button(item.course.isEmpty ? store.t("设置课程", "Set course") : store.t("修改课程", "Change course")) {
                            showCourseEdit = true
                        }
                    }
                    Spacer()
                    if let link = item.link { Link(item.source == .outlook ? store.t("在 Outlook 查看", "View in Outlook") : store.t("在 Blackboard 查看", "View in Blackboard"), destination: link) }
                }
                if item.source != .manual && item.source != .outlook {
                    Text(store.t("课程名称可在本机补填，自动同步后仍会保留。若时间缺失或发布在公告中，可手动添加一个 DDL。", "You can label the course locally; it stays after sync. Add a manual deadline when the time is missing or only listed in announcements."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text(store.t("此事项已被移除。", "This item has been removed.")); Button(store.t("关闭", "Close")) { dismiss() } }
        }.padding(26).frame(width: 570).tint(Palette.controlAccent)
            .sheet(isPresented: $showEdit) { if let item { DeadlineEditor(item: item).environmentObject(store) } }
            .sheet(isPresented: $showCourseEdit) { if let item { CourseEditor(item: item).environmentObject(store) } }
            .alert(store.t("删除此截止日期？", "Delete this deadline?"), isPresented: $confirmDelete) {
                Button(store.t("取消", "Cancel"), role: .cancel) {}
                Button(store.t("删除", "Delete"), role: .destructive) { if let item { store.delete(item) }; dismiss() }
            }
    }
    private func sourceName(_ source: DeadlineSource) -> String {
        switch source { case .blackboard: return store.t("Blackboard 自动同步", "Synced from Blackboard"); case .file: return store.t("日历文件（不会自动更新）", "Calendar file (no automatic updates)"); case .manual: return store.t("手动添加", "Added manually"); case .outlook: return store.t("Outlook 邮件", "Outlook mail") }
    }
}

private struct CourseEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: Deadline
    @State private var course = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t("设置课程", "Set course")).font(.system(size: 21, weight: .semibold))
            Text(item.title).font(.callout).foregroundStyle(.secondary)
            TextField(store.t("课程名称或代码", "Course name or code"), text: $course)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(store.t("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("保存", "Save")) {
                    store.setCourse(course, for: item.id)
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 430).tint(Palette.controlAccent)
            .onAppear { course = item.course }
    }
}
