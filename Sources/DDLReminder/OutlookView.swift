import AppKit
import SwiftUI
import DeadlineCore
import UniformTypeIdentifiers

struct OutlookView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var tenantID = ""
    @State private var connected = false
    @State private var busy = false
    @State private var authorization: OutlookAuthorization?
    @State private var authTask: Task<Void, Never>?
    @State private var candidates: [MailDeadlineCandidate] = []
    @State private var selected = Set<String>()
    @State private var error: String?
    @State private var showMailImporter = false
    private let service = OutlookService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.t("Outlook 邮件中的 DDL", "Deadlines in Outlook mail"))
                    .font(.system(size: 23, weight: .semibold))
                Spacer()
                Button(store.t("关闭", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(store.t("只在你点击扫描时读取最近 180 天收件箱中的邮件。邮件正文仅在本机分析；找到的日期由你确认后才加入任务。",
                         "Inbox mail from the last 180 days is read only when you scan. Message text is analyzed locally; you choose which dates to add."))
                .font(.callout).foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.orange).font(.callout)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button(store.t("导入 Outlook 邮件文件（.eml）", "Import Outlook mail files (.eml)")) {
                    showMailImporter = true
                }.buttonStyle(PrimaryButtonStyle())
                Text(store.t("无需 Entra 管理员权限", "No Entra admin access needed"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !connected {
                connectionForm
            } else {
                HStack {
                    Label(store.t("Outlook 已授权", "Outlook authorized"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    Button(store.t("断开 Outlook", "Disconnect Outlook")) { disconnect() }
                }
                Button(busy ? store.t("正在扫描…", "Scanning…") : store.t("扫描收件箱", "Scan inbox")) {
                    Task { await scan() }
                }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
            }
            if !candidates.isEmpty { reviewList }
            Spacer(minLength: 0)
            Text(store.t("仅申请 Microsoft Graph 的 Mail.Read 委托权限；不发送、删除或修改邮件。授权令牌保存在 macOS 钥匙串。",
                         "Uses delegated Microsoft Graph Mail.Read only; it never sends, deletes, or changes mail. Authorization tokens stay in macOS Keychain."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width: 710, height: 620).tint(Palette.controlAccent)
            .onAppear { connected = OutlookKeychain.isConnected() }
            .onDisappear { authTask?.cancel() }
            .fileImporter(isPresented: $showMailImporter,
                          allowedContentTypes: [UTType(filenameExtension: "eml") ?? .data],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("连接 Microsoft 365 / Outlook", "Connect Microsoft 365 / Outlook"))
                .font(.headline)
            TextField("Application (client) ID", text: $clientID).textFieldStyle(.roundedBorder)
            TextField(store.t("Directory (tenant) ID（可选）", "Directory (tenant) ID (optional)"), text: $tenantID)
                .textFieldStyle(.roundedBorder)
            Text(store.t("Client ID 需从 Microsoft Entra → 应用注册取得。该应用须允许公共客户端流，并配置 Microsoft Graph 的 Mail.Read 委托权限。学校可能要求管理员批准。",
                         "Get the Client ID from Microsoft Entra → App registrations. Enable public client flows and delegated Microsoft Graph Mail.Read. Your school may require admin approval."))
                .font(.caption).foregroundStyle(.secondary)
            Link(store.t("查看微软的应用注册说明", "Microsoft app registration guide"),
                 destination: URL(string: "https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app")!)
                .font(.caption)
            Button(busy ? store.t("正在连接…", "Connecting…") : store.t("获取微软授权码", "Get Microsoft sign-in code")) {
                Task { await begin() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(busy || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let authorization {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("在微软登录页面输入此代码：", "Enter this code on Microsoft's sign-in page:"))
                    Text(authorization.userCode).font(.system(size: 24, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button(store.t("复制代码", "Copy code")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(authorization.userCode, forType: .string)
                        }
                        Button(store.t("打开微软登录页面", "Open Microsoft sign-in")) {
                            NSWorkspace.shared.open(authorization.verificationURL)
                        }
                    }
                    Text(store.t("完成登录及授权后，拾期会自动继续。", "Shiqi will continue after you sign in and grant access."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var reviewList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.t("候选 DDL（\(candidates.count)）", "Candidate deadlines (\(candidates.count))"))
                .font(.headline)
            Text(store.t("勾选要添加的任务；请核对日期、课程和邮件原文。添加后可在任务详情中编辑。",
                         "Select items to add. Check the date, course, and email text. You can edit an item after adding it."))
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                                if value { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                            })).labelsHidden()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title).font(.callout.weight(.medium))
                                Text(candidate.course.isEmpty ? store.t("课程待确认", "Course to confirm") : candidate.course)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(store.format(candidate.dueDate, pattern: candidate.hasTime ? "yyyy年M月d日 HH:mm" : "yyyy年M月d日") +
                                     (candidate.hasTime ? "" : store.t(" · 时间待确认", " · Time to confirm")))
                                    .font(.caption).foregroundStyle(Palette.accent)
                                Text(candidate.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(maxHeight: 255)
            Button(store.t("添加选中的 \(selected.count) 条", "Add \(selected.count) selected")) {
                store.importOutlook(candidates.filter { selected.contains($0.id) })
                candidates.removeAll { selected.contains($0.id) }
                selected.removeAll()
            }.buttonStyle(PrimaryButtonStyle()).disabled(selected.isEmpty)
        }
    }

    private func begin() async {
        error = nil; busy = true
        do {
            let auth = try await service.begin(clientID: clientID, tenantID: tenantID.isEmpty ? "organizations" : tenantID)
            authorization = auth
            busy = false
            authTask?.cancel()
            authTask = Task {
                do {
                    try await service.finish(auth)
                    connected = true; authorization = nil; error = nil
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription; authorization = nil }
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }

    private func scan() async {
        error = nil; busy = true
        defer { busy = false }
        do {
            let messages = try await service.recentMessages()
            candidates = MailDeadlineExtractor().candidates(from: messages, timeZone: store.preferences.timeZone)
                .filter { candidate in !store.snapshot.deadlines.contains(where: { $0.id == candidate.id }) }
            selected.removeAll()
            if candidates.isEmpty {
                error = store.t("最近 180 天的收件箱邮件中未识别到新的 DDL。请检查邮件原文，或手动添加。",
                                "No new deadline was recognized in the last 180 days of inbox mail. Check the messages or add it manually.")
            }
        } catch { self.error = error.localizedDescription }
    }

    private func disconnect() {
        do { try OutlookKeychain.delete(); connected = false; candidates = []; selected = [] }
        catch { self.error = error.localizedDescription }
    }

    private func importFiles(_ urls: [URL]) {
        error = nil
        guard urls.count <= 50 else { error = store.t("一次最多导入 50 封邮件。", "Import up to 50 messages at a time."); return }
        var messages: [MailMessage] = []
        var failures = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { messages.append(try EMLParser().parse(Data(contentsOf: url))) }
            catch { failures += 1 }
        }
        candidates = MailDeadlineExtractor().candidates(from: messages, timeZone: store.preferences.timeZone)
            .filter { candidate in !store.snapshot.deadlines.contains(where: { $0.id == candidate.id }) }
        selected.removeAll()
        if failures > 0 {
            error = store.t("有 \(failures) 个文件不是可读取的 .eml 邮件。", "\(failures) files were not readable .eml messages.")
        } else if candidates.isEmpty {
            error = store.t("这些邮件中未识别到新的截止日期；可以手动添加。", "No new deadline was recognized in these messages; you can add one manually.")
        }
    }
}
