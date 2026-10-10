#if os(macOS)
import AppKit
#endif
import Foundation
import Security
import UserNotifications
import DeadlineCore

enum Keychain {
    private static let service = "cn.shuning.ddlreminder"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "blackboard-calendar"]
    }
    static func read(language: AppLanguage = .chinese) throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw CalendarError.message(language.text("无法读取钥匙串中的订阅链接，请重新连接 Blackboard。", "Could not read the subscription from Keychain. Reconnect Blackboard."))
        }
        return string
    }
    static func write(_ value: String, language: AppLanguage = .chinese) throws {
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CalendarError.message(language.text("无法保存订阅链接到系统钥匙串。请检查钥匙串访问权限。", "Could not save the subscription to Keychain. Check Keychain access permissions.")) }
    }
    static func delete(language: AppLanguage = .chinese) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalendarError.message(language.text("无法移除钥匙串中的订阅链接。", "Could not remove the subscription from Keychain."))
        }
    }
}

final class FeedClient: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never send a private calendar token to a different host or insecure connection.
        guard request.url?.scheme == "https", request.url?.host == task.originalRequest?.url?.host else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
    func fetch(_ url: URL, language: AppLanguage = .chinese) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 45
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("text/calendar, text/plain;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CalendarError.message(language.text("Blackboard 暂时无法提供日历。请检查校园网/VPN，或重新获取共享链接。", "Blackboard could not provide the calendar. Check your campus network/VPN or obtain a new sharing link."))
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw CalendarError.message(language.text("Blackboard 拒绝了日历访问（HTTP \(http.statusCode)）。请确认使用的是「Get External Calendar Link / Share Calendar」生成的完整链接；必要时重新生成，或使用校园网/VPN。", "Blackboard denied calendar access (HTTP \(http.statusCode)). Use the full Get External Calendar Link / Share Calendar URL; regenerate it or check campus network/VPN access."))
                }
                throw CalendarError.message(language.text("日历请求失败（HTTP \(http.statusCode)）。已保留原有数据，请稍后重试或重新获取共享链接。", "Calendar request failed (HTTP \(http.statusCode)). Existing data is kept. Try again later or obtain a new sharing link."))
            }
            let maximum = 5 * 1024 * 1024
            guard response.expectedContentLength <= maximum else { throw CalendarError.message(language.text("日历超过 5 MB，暂时无法导入。", "The calendar exceeds 5 MB and cannot be imported.")) }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count > maximum { throw CalendarError.message(language.text("日历超过 5 MB，暂时无法导入。", "The calendar exceeds 5 MB and cannot be imported.")) }
            }
            guard let text = String(data: data, encoding: .utf8) else { throw CalendarError.message(language.text("日历文件不是有效的 UTF-8 格式。", "The calendar is not valid UTF-8.")) }
            return text
        } catch is CancellationError { throw CancellationError() }
        catch let error as CalendarError { throw error }
        catch let error as URLError {
            let reason: String
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed: reason = language.text("无法解析服务器地址，请检查链接域名、网络和校园 VPN", "Could not resolve the server. Check the link domain, network, and campus VPN")
            case .timedOut: reason = language.text("连接超时，请检查网络和校园 VPN", "Connection timed out. Check your network and campus VPN")
            case .notConnectedToInternet, .networkConnectionLost: reason = language.text("网络未连接或连接中断", "The network is offline or the connection was interrupted")
            case .userAuthenticationRequired: reason = language.text("该地址要求登录，请使用日历共享链接，或导出 .ics 文件导入", "This address requires sign-in. Use a calendar sharing link or import an exported .ics file")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                reason = language.text("HTTPS 证书验证失败，请检查系统日期或联系学校 IT", "HTTPS certificate validation failed. Check the system date or contact university IT")
            default: reason = language.text("无法建立日历连接，请检查网络、校园 VPN 和完整订阅链接", "Could not connect to the calendar. Check the network, campus VPN, and full subscription link")
            }
            throw CalendarError.message(language.text("\(reason)（网络代码 \(error.code.rawValue)）。已保留原有数据。", "\(reason) (network code \(error.code.rawValue)). Existing data is kept."))
        }
        catch {
            // URLSession errors can contain private feed URLs. Do not expose them in UI/logs.
            throw CalendarError.message(language.text("无法连接 Blackboard。请确认网络、校园 VPN 和订阅链接；已保留上次同步的数据。", "Could not connect to Blackboard. Check the network, campus VPN, and subscription link. The last synced data is kept."))
        }
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            #endif
            #if os(iOS)
            NotificationCenter.default.post(name: .showDeadlineWindow, object: response.notification.request.content.userInfo["deadlineID"] as? String)
            #else
            NotificationCenter.default.post(name: .showDeadlineWindow, object: nil)
            #endif
        }
        completionHandler()
    }
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func reconcile(_ plans: [ReminderPlan], zone: TimeZone, language: AppLanguage = .chinese) async throws -> Int {
        let allowed = await authorization()
        guard !Task.isCancelled else { throw CancellationError() }
        guard allowed == .authorized || allowed == .provisional else { return 0 }
        // A bounded rolling queue prioritizes the next alerts and is replenished every minute.
        let selected = Array(plans.prefix(60))
        let ids = Set(selected.map(\.id))
        let existing = await center.pendingNotificationRequests()
        try Task.checkCancellation()
        let stale = existing.filter { $0.identifier.hasPrefix("ddl.") && !ids.contains($0.identifier) }
        center.removePendingNotificationRequests(withIdentifiers: stale.map(\.identifier))
        let formatter = DateFormatter(); formatter.locale = language.locale; formatter.timeZone = zone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for plan in selected {
            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = plan.deadline.title; content.subtitle = plan.subtitle
            formatter.dateFormat = language.datePattern(plan.deadline.hasTime ? "M月d日 EEEE HH:mm" : "M月d日 EEEE（具体时间待确认）")
            content.body = [plan.deadline.course, language.text("到期：", "Due: ") + formatter.string(from: plan.deadline.dueDate), language.timeZoneName(zone.identifier)].filter { !$0.isEmpty }.joined(separator: "\n")
            content.sound = .default
            content.userInfo = ["deadlineID": plan.deadline.id]
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
            // Adding an existing identifier updates changed titles/course details without duplicates.
            try await center.add(request)
        }
        return selected.count
    }
    func clear() async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("ddl.") }.map(\.identifier))
    }
    func test(language: AppLanguage = .chinese) async throws {
        let content = UNMutableNotificationContent()
        content.title = language.text("拾期提醒已就绪", "Shiqi reminders are ready")
        content.body = language.text("你的 DDL 会在设定的时间提醒。测试通知已送达。", "Your deadlines will be reminded at the times you chose. This is a test notification.")
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
}

extension Notification.Name { static let showDeadlineWindow = Notification.Name("showDeadlineWindow") }

enum LocalStorage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DDLReminder", isDirectory: true)
    }
    static func load() throws -> Snapshot {
        let url = directory.appendingPathComponent("deadlines.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }
    static func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        let url = directory.appendingPathComponent("deadlines.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: directory.appendingPathComponent("deadlines.backup.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let backup = directory.appendingPathComponent("deadlines.backup.json")
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path) }
    }
}
