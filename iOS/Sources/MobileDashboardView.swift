import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DeadlineCore

enum MobilePalette {
    static let purple = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.83, green: 0.55, blue: 0.85, alpha: 1) : UIColor(red: 0.46, green: 0.06, blue: 0.43, alpha: 1)
    })
    static let gold = Color(red: 0.87, green: 0.64, blue: 0)
}

enum MobileFilter: String, CaseIterable {
    case upcoming, week, overdue, completed
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .upcoming: return language.text("待完成", "Upcoming")
        case .week: return language.text("近 7 天", "7 days")
        case .overdue: return language.text("已逾期", "Overdue")
        case .completed: return language.text("已完成", "Completed")
        }
    }
}

struct MobileDashboardView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var filter: MobileFilter = .upcoming
    @State private var search = ""
    @State private var showConnection = false
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showImport = false
    @State private var selected: Deadline?
    private var filtered: [Deadline] {
        store.deadlines.filter { item in
            let overdue = item.isOverdue(at: store.now, timeZone: store.preferences.timeZone)
            let matches: Bool
            switch filter {
            case .upcoming: matches = !item.completed && !overdue
            case .week: matches = !item.completed && !overdue && item.dueDate < store.now.addingTimeInterval(7 * 86400)
            case .overdue: matches = !item.completed && overdue
            case .completed: matches = item.completed
            }
            return matches && (search.isEmpty || (item.title + " " + item.course).localizedCaseInsensitiveContains(search))
        }.sorted { $0.dueDate < $1.dueDate }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            MobileAppMark().frame(width: 46, height: 46).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.text("课程 DDL 与提醒", "Course deadlines and reminders")).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dashboard.heading")
                                Text(store.text("给龙大学子的免费开源软件", "Free, open-source software for LGU students")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dashboard.subtitle")
                            }
                        }
                        HStack {
                            Text(store.preferences.timeZoneLabel).font(.caption).foregroundStyle(MobilePalette.purple)
                            Spacer()
                            if store.isSyncing { ProgressView().controlSize(.small) }
                            else { Image(systemName: store.isConnected ? "link" : "tray").foregroundStyle(MobilePalette.gold) }
                        }
                        if store.isDemo { Text(store.text("演示数据 · 不保存或连接账户", "Demo data · No saving or account access")).font(.caption).foregroundStyle(.secondary) }
                        if let sync = store.snapshot.lastSync {
                            Text(store.text("上次同步：", "Last sync: ") + store.syncLabel(sync)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MobileFilter.allCases, id: \.self) { value in
                                Button { filter = value } label: {
                                    Text(value.label(store.language)).font(.subheadline.weight(.semibold)).fixedSize()
                                        .padding(.horizontal, 13).padding(.vertical, 9)
                                        .foregroundStyle(filter == value ? Color(uiColor: .systemBackground) : MobilePalette.purple)
                                        .background(filter == value ? MobilePalette.purple : MobilePalette.purple.opacity(0.08), in: Capsule())
                                }.buttonStyle(.plain).accessibilityIdentifier("filter.\(value.rawValue)")
                                    .accessibilityAddTraits(filter == value ? [.isSelected] : [])
                            }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("filters")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                if !store.warnings.isEmpty {
                    Section {
                        ForEach(Array(store.warnings.enumerated()), id: \.offset) { _, message in
                            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    } header: { Text(store.text("导入提示", "Import notes")) }
                }
                Section {
                    if filtered.isEmpty {
                        ContentUnavailableView {
                            Label(store.text("这里还没有 DDL", "No deadlines here"), systemImage: filter == .completed ? "checkmark.circle" : "calendar")
                        } description: {
                            Text(store.text("连接 Blackboard、导入 .ics 日历，或手动添加。", "Connect Blackboard, import an .ics calendar, or add a deadline."))
                        } actions: {
                            if store.deadlines.isEmpty { Button(store.text("连接日历", "Connect calendar")) { showConnection = true } }
                        }.listRowBackground(Color.clear)
                    } else {
                        ForEach(filtered) { item in
                            HStack(alignment: .top, spacing: 13) {
                                Button { store.toggle(item) } label: {
                                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(item.completed ? MobilePalette.purple : Color.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                }.buttonStyle(.borderless)
                                    .accessibilityLabel(store.text(item.completed ? "恢复待办" : "标记完成", item.completed ? "Mark incomplete" : "Mark complete") + ": " + item.title)
                                    .accessibilityIdentifier("complete.\(item.title)")
                                Button { selected = item } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.title).font(.headline).foregroundStyle(.primary).strikethrough(item.completed).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                        if !item.course.isEmpty { Text(item.course).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                        Text(store.dateLabel(item)).font(.subheadline)
                                            .foregroundStyle(!item.completed && item.isOverdue(at: store.now, timeZone: store.preferences.timeZone) ? Color.red : MobilePalette.purple)
                                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("deadline.\(item.title)")
                            }
                        }
                    }
                } header: { Text("\(filter.label(store.language)) · \(filtered.count)") }
                Section {
                    Button { showConnection = true } label: {
                        Label(store.text(store.isConnected ? "管理 Blackboard 订阅" : "连接 Blackboard 日历", store.isConnected ? "Manage Blackboard subscription" : "Connect Blackboard calendar"), systemImage: "link")
                    }.disabled(store.isSyncing).accessibilityIdentifier("connection")
                    Button { showImport = true } label: { Label(store.text("导入 .ics 日历文件", "Import .ics calendar"), systemImage: "square.and.arrow.down") }
                    #if DEBUG
                    if store.isUITesting {
                        Button("Import test fixture") { store.importTestingFixture(regenerated: false) }.accessibilityIdentifier("test.import")
                        Button("Reimport changed UID") { store.importTestingFixture(regenerated: true) }.accessibilityIdentifier("test.reimport")
                    }
                    #endif
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(store.language.appName)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: store.text("搜索任务或课程", "Search tasks or courses"))
            .refreshable { await store.synchronize() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(store.text("设置", "Settings")).accessibilityIdentifier("settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(store.text("添加 DDL", "Add deadline")).accessibilityIdentifier("add")
                }
            }
            .sheet(isPresented: $showConnection) { MobileConnectionView() }
            .sheet(isPresented: $showSettings) { MobileSettingsView() }
            .sheet(isPresented: $showAdd) { MobileEditorView() }
            .sheet(item: $selected) { MobileDetailView(reminderID: $0.reminderID) }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.calendarEvent, UTType(filenameExtension: "ics") ?? .text]) { result in
                switch result {
                case .success(let url): store.importFile(url)
                case .failure: store.errorMessage = store.text("无法打开日历文件，请重试。", "Could not open the calendar file. Try again.")
                }
            }
            .onOpenURL { url in
                if url.isFileURL, url.pathExtension.lowercased() == "ics" { store.importFile(url) }
                else if let identity = AppleRemindersPlanner.identity(from: url) {
                    selected = store.deadlines.first { $0.reminderID == identity }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showDeadlineWindow)) { notification in
                if let id = notification.object as? String { selected = store.deadlines.first { $0.id == id } }
            }
            .alert(store.text("操作提示", "Notice"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button(store.text("确定", "OK"), role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}

struct MobileAppMark: View {
    var body: some View {
        Image("BrandMark").resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
