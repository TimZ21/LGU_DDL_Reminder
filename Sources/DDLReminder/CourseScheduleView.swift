import SwiftUI
import DeadlineCore
import UniformTypeIdentifiers

struct CourseScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var weekOffset = 0
    @State private var showImporter = false
    @State private var editorTarget: EditorTarget?

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let meeting: CourseMeeting?
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = store.preferences.timeZone
        result.firstWeekday = 2
        return result
    }
    private var weekStart: Date {
        let today = calendar.startOfDay(for: store.now)
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: monday)!
    }
    private func date(_ day: Int) -> Date { calendar.date(byAdding: .day, value: day - 1, to: weekStart)! }
    private func classes(_ day: Int) -> [CourseMeeting] {
        store.courseSchedule.visibleMeetings.filter { $0.occurs(on: date(day), timeZone: store.preferences.timeZone) }
            .sorted { $0.startMinute == $1.startMinute ? $0.course < $1.course : $0.startMinute < $1.startMinute }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleBar
            if let error = store.courseError {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let summary = store.courseFeedSummary {
                Text(summary).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            toolbar
            if store.courseSchedule.visibleMeetings.isEmpty {
                emptyState
            } else {
                weekGrid
            }
        }.padding(22).frame(minWidth: 1050, minHeight: 620)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data, .zip]) { result in
                switch result { case .success(let url): store.importCourseFile(url); case .failure(let error): store.courseError = error.localizedDescription }
            }
            .sheet(item: $editorTarget) { target in CourseMeetingEditor(meeting: target.meeting).environmentObject(store) }
    }
    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("课程表", "Class schedule")).font(.title2.bold())
                Text(store.t("Blackboard 日历中的时段会随 DDL 自动同步；可在这里修改或隐藏。", "Blackboard calendar periods sync with deadlines. Edit or hide them here."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.t("关闭", "Close")) { dismiss() }
        }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
            Button(store.t("本周", "This week")) { weekOffset = 0 }
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
            Text(store.format(weekStart, pattern: "yyyy年M月d日") + " – " + store.format(date(7), pattern: "M月d日"))
                .font(.subheadline.weight(.medium))
            Spacer()
            Button { Task { await store.sync() } } label: {
                Label(store.t("同步 Blackboard", "Sync Blackboard"), systemImage: "arrow.triangle.2.circlepath")
            }.disabled(!store.isConnected || store.isSyncing)
            Button { showImporter = true } label: { Label(store.t("导入 SIS / .ics", "Import SIS / .ics"), systemImage: "square.and.arrow.down") }
            Button { editorTarget = EditorTarget(meeting: nil) } label: { Label(store.t("添加课程", "Add class"), systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar").font(.largeTitle).foregroundStyle(.secondary)
            Text(store.t("还没有课程时段", "No classes yet")).font(.headline)
            Text(store.t("连接 Blackboard 后同步日历，或导入 .ics 课表、手动添加。", "Sync a connected Blackboard calendar, import an .ics schedule, or add a class."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var weekGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 7), spacing: 8) {
                ForEach(1...7, id: \.self) { day in dayColumn(day) }
            }
        }
    }
    private func dayColumn(_ day: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.format(date(day), pattern: "EEE M/d"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(day == 1 ? Palette.accent : Color.secondary)
            ForEach(classes(day)) { meeting in courseCard(meeting) }
            Spacer(minLength: 4)
        }.frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    }
    private func courseCard(_ meeting: CourseMeeting) -> some View {
        Button { editorTarget = EditorTarget(meeting: meeting) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.course).font(.caption.weight(.semibold)).lineLimit(3)
                Text(time(meeting.startMinute) + "–" + time(meeting.endMinute))
                    .font(.caption2).monospacedDigit()
                if !meeting.location.isEmpty { Text(meeting.location).font(.caption2).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

private struct CourseMeetingEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meeting: CourseMeeting?
    @State private var course = ""
    @State private var location = ""
    @State private var weekday = 1
    @State private var startHour = 9
    @State private var startMinute = 0
    @State private var endHour = 10
    @State private var endMinute = 0
    @State private var validFrom = Date()
    @State private var validUntil = Date().addingTimeInterval(120 * 86400)
    @State private var hasEnd = true
    @State private var interval = 1
    @State private var error: String?

    init(meeting: CourseMeeting?) {
        self.meeting = meeting
        guard let meeting else { return }
        _course = State(initialValue: meeting.course)
        _location = State(initialValue: meeting.location)
        _weekday = State(initialValue: meeting.weekday)
        _startHour = State(initialValue: meeting.startMinute / 60)
        _startMinute = State(initialValue: meeting.startMinute % 60)
        _endHour = State(initialValue: meeting.endMinute / 60)
        _endMinute = State(initialValue: meeting.endMinute % 60)
        _validFrom = State(initialValue: meeting.validFrom)
        _validUntil = State(initialValue: meeting.validUntil ?? Date().addingTimeInterval(120 * 86400))
        _hasEnd = State(initialValue: meeting.validUntil != nil)
        _interval = State(initialValue: meeting.weekInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(meeting == nil ? store.t("添加课程", "Add class") : store.t("编辑课程", "Edit class")).font(.title3.bold())
            Form {
                TextField(store.t("课程名称", "Course name"), text: $course)
                TextField(store.t("地点", "Location"), text: $location)
                Picker(store.t("星期", "Day"), selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in Text(dayName(day)).tag(day) }
                }
                HStack {
                    Picker(store.t("开始", "Starts"), selection: $startHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 155)
                    Picker("", selection: $startMinute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 80)
                }
                HStack {
                    Picker(store.t("结束", "Ends"), selection: $endHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 155)
                    Picker("", selection: $endMinute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 80)
                }
                DatePicker(store.t("生效日期", "From"), selection: $validFrom, displayedComponents: .date)
                Toggle(store.t("设置结束日期", "Set end date"), isOn: $hasEnd)
                if hasEnd { DatePicker(store.t("结束日期", "Until"), selection: $validUntil, displayedComponents: .date) }
                Picker(store.t("重复", "Repeats"), selection: $interval) {
                    Text(store.t("每周", "Weekly")).tag(1)
                    Text(store.t("每两周", "Every 2 weeks")).tag(2)
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                if let meeting {
                    Button(store.t("删除／隐藏", "Delete / Hide"), role: .destructive) {
                        store.deleteCourse(meeting); dismiss()
                    }
                }
                Spacer()
                Button(store.t("取消", "Cancel")) { dismiss() }
                Button(store.t("保存", "Save")) { save() }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(20).frame(width: 440, height: 580)
    }
    private func dayName(_ day: Int) -> String {
        let names = store.language == .chinese ? ["周一", "周二", "周三", "周四", "周五", "周六", "周日"] : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return names[day - 1]
    }
    private func save() {
        let name = course.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = startHour * 60 + startMinute; let end = endHour * 60 + endMinute
        guard !name.isEmpty, start < end, !hasEnd || validUntil >= validFrom else {
            error = store.t("请填写课程名称，并检查时间与日期。", "Enter a course name and check the times and dates."); return
        }
        var updated = meeting ?? CourseMeeting(course: name, weekday: weekday, startMinute: start, endMinute: end, validFrom: validFrom)
        updated.course = name; updated.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.weekday = weekday; updated.startMinute = start; updated.endMinute = end
        updated.validFrom = validFrom; updated.validUntil = hasEnd ? validUntil : nil; updated.weekInterval = interval
        store.upsertCourse(updated); dismiss()
    }
}
