import SwiftUI
import AppKit
import DeadlineCore
import UserNotifications
import UniformTypeIdentifiers

enum Palette {
    // Shiqi's purple/gold palette, with text shades adapted for appearance and contrast.
    static let controlAccent = Color(red: 117 / 255, green: 15 / 255, blue: 109 / 255)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.81, green: 0.56, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 117 / 255, green: 15 / 255, blue: 109 / 255, alpha: 1)
    })
    static let gold = Color(red: 221 / 255, green: 163 / 255, blue: 0)
    static let goldInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.77, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.51, green: 0.34, blue: 0.0, alpha: 1)
    })
    static let ink = Color.primary
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, controlSize == .large ? 10 : 7)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(isEnabled ? Palette.controlAccent : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum DeadlineFilter: String, CaseIterable {
    case upcoming = "即将截止", week = "未来 7 天", overdue = "已逾期", completed = "已完成"
    var icon: String {
        switch self { case .upcoming: return "tray"; case .week: return "calendar"; case .overdue: return "exclamationmark.circle"; case .completed: return "checkmark.circle" }
    }
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .upcoming: return language.text("即将截止", "Upcoming")
        case .week: return language.text("未来 7 天", "Next 7 days")
        case .overdue: return language.text("已逾期", "Overdue")
        case .completed: return language.text("已完成", "Completed")
        }
    }
}

struct AppMark: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: w * 0.22), with: .color(Palette.controlAccent))
            context.fill(Path(roundedRect: CGRect(x: w * 0.2, y: h * 0.24, width: w * 0.6, height: h * 0.58), cornerRadius: w * 0.065), with: .color(.white))
            context.fill(Path(CGRect(x: w * 0.2, y: h * 0.38, width: w * 0.6, height: h * 0.025)), with: .color(Palette.gold))
            for x in [0.31, 0.65] {
                context.fill(Path(roundedRect: CGRect(x: w * x, y: h * 0.15, width: w * 0.04, height: h * 0.14), cornerRadius: w * 0.02), with: .color(.white))
            }
            var check = Path()
            check.move(to: CGPoint(x: w * 0.33, y: h * 0.60))
            check.addLine(to: CGPoint(x: w * 0.45, y: h * 0.72))
            check.addLine(to: CGPoint(x: w * 0.67, y: h * 0.50))
            context.stroke(check, with: .color(Palette.controlAccent), style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round, lineJoin: .round))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter = DeadlineFilter.upcoming
    @State private var query = ""
    @State private var selectedItem: Deadline?
    @State private var showImporter = false

    private var items: [Deadline] {
        let selected: [Deadline]
        switch filter {
        case .upcoming: selected = store.upcoming
        case .week: selected = store.nextSevenDays
        case .overdue: selected = store.overdue
        case .completed: selected = store.displayedDeadlines.filter(\.completed).sorted { $0.dueDate > $1.dueDate }
        }
        return selected.filter { query.isEmpty || ($0.title + $0.course + $0.notes).localizedCaseInsensitiveContains(query) }
    }
    private var grouped: [(String, [Deadline])] {
        var keys: [String] = []; var values: [String: [Deadline]] = [:]
        for item in items {
            let key = store.format(item.dueDate, pattern: "yyyy年M月d日 EEEE")
            if values[key] == nil { keys.append(key) }
            values[key, default: []].append(item)
        }
        return keys.map { ($0, values[$0]!) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if store.isDemo { banner(store.t("演示模式 · 以下是示例任务，不是真实课程数据", "Demo mode · Sample tasks, not your course data"), icon: "sparkles", color: Palette.accent) }
                        if let error = store.errorMessage {
                            dismissibleBanner(error, icon: "exclamationmark.triangle", color: .orange) { store.errorMessage = nil }
                        }
                        if let notice = store.notice {
                            dismissibleBanner(notice, icon: "checkmark.circle", color: Palette.accent) { store.notice = nil }
                        }
                        if !store.snapshot.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(store.t("有 \(store.snapshot.warnings.count) 个事项需要核对", "\(store.snapshot.warnings.count) items need checking"), systemImage: "exclamationmark.triangle").font(.callout.weight(.semibold))
                                ForEach(store.snapshot.warnings, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                            }.foregroundStyle(.orange).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if !store.isConnected && !store.isDemo { connectCard }
                        statCards
                        if store.notificationStatus != .authorized && !store.isDemo {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge").foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.t("打开通知，让截止日期主动找你", "Get a heads-up before each deadline")).font(.callout.weight(.medium))
                                    Text(store.t("默认提前 24 小时、3 小时、30 分钟，以及到期时提醒", "Reminders: 24 hours, 3 hours, 30 minutes before, and at the deadline")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(store.t("开启提醒", "Enable reminders")) { Task { await store.requestNotifications() } }.buttonStyle(.bordered)
                            }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        HStack {
                            Text(filter.label(store.language)).font(.system(size: 19, weight: .semibold))
                            Text("\(items.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField(store.t("搜索课程或任务", "Search courses or tasks"), text: $query).textFieldStyle(.plain)
                            }.padding(8).frame(width: 190).background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                        }
                        if items.isEmpty { emptyState }
                        else {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(grouped, id: \.0) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.0).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 2)
                                        VStack(spacing: 0) {
                                            ForEach(group.1) { item in
                                                DeadlineRow(item: item, onDetail: { selectedItem = item })
                                                if item.id != group.1.last?.id { Divider().padding(.leading, 58) }
                                            }
                                        }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                            Text(store.t("同步 Blackboard 日历中的全部事项；公告、附件里的 DDL 请手动补充。", "All Blackboard calendar items are included. Add deadlines from announcements or attachments manually."))
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                    }.padding(28)
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background).frame(minWidth: 880, minHeight: 620).tint(Palette.controlAccent)
        .sheet(isPresented: $store.showConnection) { ConnectionView().environmentObject(store) }
        .sheet(isPresented: $store.showSettings) { ReminderSettingsView().environmentObject(store) }
        .sheet(isPresented: $store.showEditor) { DeadlineEditor(item: store.editingDeadline).environmentObject(store) }
        .sheet(isPresented: $store.showOutlook) { OutlookView().environmentObject(store) }
        .sheet(isPresented: $store.showCourseSchedule) { CourseScheduleView().environmentObject(store) }
        .sheet(item: $selectedItem) { DeadlineDetailView(itemID: $0.id).environmentObject(store) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]) { result in
            switch result { case .success(let url): store.importFile(url); case .failure(let error): store.errorMessage = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDeadlineWindow)) { _ in
            openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: scenePhase) { phase in if phase == .active { store.reloadCodexDisplay(); Task { await store.refreshPermission() } } }
        .onOpenURL { url in
            guard let id = AppleRemindersPlanner.identity(from: url),
                  let item = store.snapshot.deadlines.first(where: { $0.reminderID == id }) else { return }
            store.showSettings = false; store.showConnection = false; store.showEditor = false
            selectedItem = item
            openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("拾期", "Shiqi")).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.accent)
                    Text(store.t("龙大", "LGU")).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.goldInk)
                }
            }.padding(.top, 38).padding(.bottom, 34)
            Text(store.t("我的任务", "MY TASKS")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 12).padding(.leading, 10)
            ForEach(DeadlineFilter.allCases, id: \.self) { value in
                Button { filter = value } label: {
                    HStack(spacing: 10) {
                        Image(systemName: value.icon).frame(width: 18)
                        Text(value.label(store.language)).font(.system(size: 13, weight: filter == value ? .semibold : .regular))
                        Spacer()
                        Text("\(count(value))").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }.padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
                        .background(filter == value ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(filter == value ? Palette.accent : .primary)
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Button { store.showCourseSchedule = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.day.timeline.left").frame(width: 18)
                    Text(store.t("课程表", "Class schedule")).font(.system(size: 13))
                    Spacer()
                    Text("\(store.courseSchedule.visibleMeetings.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 11)
            }.buttonStyle(.plain)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(store.isConnected ? Palette.accent : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(store.isConnected ? store.t("Blackboard 已连接", "Blackboard connected") : store.t("Blackboard 未连接", "Blackboard not connected")).font(.system(size: 11, weight: .medium))
                }
                Text(store.t("龙大校园日历", "LGU campus calendar")).font(.system(size: 10)).foregroundStyle(.secondary)
                Button(store.isConnected ? store.t("管理连接", "Manage connection") : store.t("连接 Blackboard", "Connect Blackboard")) { store.showConnection = true }
                    .font(.system(size: 12)).buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
            Button { store.showSettings = true } label: {
                Label(store.t("提醒与设置", "Reminders & settings"), systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20).padding(.leading, 8)
            }.buttonStyle(.plain)
            Button { store.showOutlook = true } label: {
                Label(store.t("Outlook 邮件", "Outlook mail"), systemImage: "envelope").font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            }.buttonStyle(.plain).padding(.bottom, 16)
        }.padding(.horizontal, 18).frame(width: 214).background(Palette.accent.opacity(0.035))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t("每一步，都从容一点。", "A little more time to breathe.")).font(.system(size: 25, weight: .semibold))
                Text(store.format(store.now, pattern: "yyyy年M月d日 EEEE") + "  ·  " + store.preferences.timeZoneLabel)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(store.t("给龙大学子的免费开源软件", "Free, open-source software for LGU students"))
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
            Spacer()
            Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }.help(store.t("导入 .ics 日历文件", "Import an .ics calendar file"))
            Button { store.showOutlook = true } label: { Image(systemName: "envelope") }.help(store.t("从 Outlook 查找 DDL", "Find deadlines in Outlook"))
            Button {
                store.editingDeadline = nil; store.showEditor = true
            } label: { Label(store.t("添加 DDL", "Add deadline"), systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle()).controlSize(.large)
        }.padding(.horizontal, 28).padding(.top, 38).padding(.bottom, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.gold.opacity(0.35)).frame(height: 1).padding(.horizontal, 28) }
    }
    private var statCards: some View {
        HStack(spacing: 12) {
            stat(store.t("未来 7 天", "Next 7 days"), value: store.nextSevenDays.count, hint: store.t("按截止时间排序", "Ordered by due date"), symbol: "calendar", color: Palette.accent)
            stat(store.t("24 小时内", "Within 24 hours"), value: store.nextDay.count, hint: store.t("留一点时间给检查", "Make time for a final check"), symbol: "clock", color: Palette.goldInk)
            stat(store.t("时间待确认", "Time to confirm"), value: store.uncertain.count, hint: store.t("仅日期，具体几点未知", "Date given, exact time missing"), symbol: "questionmark.circle", color: .secondary)
        }
    }
    private func stat(_ title: String, value: Int, hint: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(color) }
            Text("\(value)").font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
    private var connectCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "link.circle.fill").font(.system(size: 39)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("把 Blackboard 的截止日期带到桌面", "Bring your Blackboard deadlines to your desktop")).font(.system(size: 17, weight: .semibold))
                Text(store.t("连接一次日历订阅，自动更新。关闭窗口后，拾期仍在菜单栏陪你。", "Connect once for automatic updates. Shiqi stays in the menu bar when you close this window."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.t("开始连接", "Get connected")) { store.showConnection = true }.buttonStyle(PrimaryButtonStyle())
        }.padding(22).background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "leaf" : "magnifyingglass").font(.system(size: 35, weight: .light)).foregroundStyle(Palette.accent.opacity(0.7))
            Text(query.isEmpty ? (filter == .overdue ? store.t("没有逾期，保持这个节奏", "No overdue tasks. Keep it up.") : store.t("这里暂时没有任务", "No tasks here yet")) : store.t("没有找到匹配的任务", "No matching tasks"))
                .font(.system(size: 15, weight: .medium))
            Text(query.isEmpty ? store.t("同步 Blackboard，或手动添加一个截止日期。", "Sync Blackboard or add a deadline manually.") : store.t("试试课程名称或任务关键词。", "Try a course name or a keyword."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 42)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.stale ? "exclamationmark.circle" : "arrow.triangle.2.circlepath").foregroundStyle(store.stale ? .orange : .secondary)
            Text(store.isSyncing ? store.t("正在同步…", "Syncing…") : syncLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(store.t("数据保存在本机", "Stored on your Mac")).font(.system(size: 10)).foregroundStyle(.tertiary)
            Button(store.t("立即同步", "Sync now")) { Task { await store.sync() } }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                .disabled(!store.isConnected || store.isSyncing)
        }.padding(.horizontal, 28).padding(.vertical, 12).background(Palette.card.opacity(0.6))
    }
    private var syncLabel: String {
        guard let date = store.snapshot.lastSync else { return store.t("尚未同步 · 每 \(store.preferences.syncMinutes) 分钟自动更新", "Not synced yet · Updates every \(store.preferences.syncMinutes) min") }
        return store.t("上次同步 \(store.format(date, pattern: "M/d HH:mm"))", "Last synced \(store.format(date, pattern: "M/d HH:mm"))") + (store.stale ? store.t(" · 数据可能不是最新的", " · Data may be out of date") : store.t(" · 每 \(store.preferences.syncMinutes) 分钟更新", " · Updates every \(store.preferences.syncMinutes) min"))
    }
    private func count(_ value: DeadlineFilter) -> Int {
        switch value { case .upcoming: return store.upcoming.count; case .week: return store.nextSevenDays.count; case .overdue: return store.overdue.count; case .completed: return store.displayedDeadlines.filter(\.completed).count }
    }
    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.system(size: 12)).foregroundStyle(color).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    private func dismissibleBanner(_ text: String, icon: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(store.t("关闭提示", "Dismiss message"))
        }.font(.system(size: 12)).foregroundStyle(color).padding(12).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DeadlineRow: View {
    @EnvironmentObject private var store: AppStore
    let item: Deadline
    let onDetail: () -> Void
    private var urgent: Bool { item.hasTime && !item.completed && item.dueDate.timeIntervalSince(store.now) < 86400 }
    var body: some View {
        HStack(spacing: 13) {
            Button { store.toggle(item) } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(item.completed ? Palette.accent : Color.secondary.opacity(0.45))
            }.buttonStyle(.plain).help(item.completed ? store.t("重新设为待办", "Mark incomplete") : store.t("标记为已完成", "Mark complete"))
                .accessibilityLabel(item.completed ? store.t("重新设为待办", "Mark incomplete") : store.t("标记为已完成", "Mark complete"))
            Button(action: onDetail) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).font(.system(size: 14, weight: .medium)).strikethrough(item.completed).lineLimit(2)
                        HStack(spacing: 7) {
                            Text(item.course.isEmpty ? (item.source == .manual ? store.t("手动添加", "Added manually") : store.t("课程未标注", "Course not specified")) : item.course)
                            Text("·")
                            Text(item.hasTime ? store.format(item.dueDate, pattern: "HH:mm") : store.t("具体时间待确认", "Exact time to confirm"))
                        }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    Text(store.countdown(item)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(urgent ? Palette.goldInk : Palette.accent)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background((urgent ? Palette.gold : Palette.accent).opacity(urgent ? 0.16 : 0.09), in: Capsule())
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(17)
    }
}
