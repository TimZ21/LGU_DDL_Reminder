import Foundation
import Security
import DeadlineCore

struct OutlookAuthorization {
    let clientID: String
    let tenantID: String
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let interval: Int
    let expiresAt: Date
}

private struct OutlookCredential: Codable {
    let clientID: String
    let tenantID: String
    let refreshToken: String
}

enum OutlookKeychain {
    private static let service = "cn.shuning.ddlreminder.outlook"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "microsoft-graph"]
    }
    static func isConnected() -> Bool { (try? read()) != nil }
    fileprivate static func read() throws -> OutlookCredential? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw OutlookError.message("无法读取 Outlook 授权信息，请重新连接。") }
        return try JSONDecoder().decode(OutlookCredential.self, from: data)
    }
    fileprivate static func write(_ credential: OutlookCredential) throws {
        let data = try JSONEncoder().encode(credential)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OutlookError.message("无法将 Outlook 授权保存到 macOS 钥匙串。") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OutlookError.message("无法移除 Outlook 授权信息。") }
    }
}

enum OutlookError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct OutlookService {
    private let loginHost = "login.microsoftonline.com"
    private let graphHost = "graph.microsoft.com"

    func begin(clientID: String, tenantID: String) async throws -> OutlookAuthorization {
        let client = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let tenant = tenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: client) != nil,
              tenant == "organizations" || UUID(uuidString: tenant) != nil else {
            throw OutlookError.message("请输入有效的 Client ID；租户 ID 可留空或填写 UUID。")
        }
        let data = try await post(path: "/\(tenant)/oauth2/v2.0/devicecode",
                                  fields: ["client_id": client, "scope": "offline_access Mail.Read"])
        let reply = try JSONDecoder().decode(DeviceCodeReply.self, from: data)
        guard let url = URL(string: reply.verificationUri), url.scheme == "https", url.host == loginHost else {
            throw OutlookError.message("微软返回了无效的授权地址。")
        }
        return OutlookAuthorization(clientID: client, tenantID: tenant,
                                    deviceCode: reply.deviceCode, userCode: reply.userCode,
                                    verificationURL: url, interval: max(reply.interval ?? 5, 5),
                                    expiresAt: Date().addingTimeInterval(Double(reply.expiresIn)))
    }

    func finish(_ auth: OutlookAuthorization) async throws {
        var interval = auth.interval
        while Date() < auth.expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()
            do {
                let data = try await post(path: "/\(auth.tenantID)/oauth2/v2.0/token",
                    fields: ["grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                             "client_id": auth.clientID, "device_code": auth.deviceCode])
                let token = try JSONDecoder().decode(TokenReply.self, from: data)
                guard let refresh = token.refreshToken else { throw OutlookError.message("微软未返回可续期授权，请确认应用请求了 offline_access。") }
                try OutlookKeychain.write(OutlookCredential(clientID: auth.clientID, tenantID: auth.tenantID, refreshToken: refresh))
                return
            } catch let error as OAuthError {
                switch error.code {
                case "authorization_pending": continue
                case "slow_down": interval += 5
                case "authorization_declined": throw OutlookError.message("你取消了 Outlook 授权。")
                case "expired_token": throw OutlookError.message("授权码已过期，请重新连接。")
                default: throw OutlookError.message(error.safeDescription)
                }
            }
        }
        throw OutlookError.message("授权码已过期，请重新连接。")
    }

    func recentMessages() async throws -> [MailMessage] {
        guard let credential = try OutlookKeychain.read() else { throw OutlookError.message("请先连接 Outlook。") }
        let tokenData = try await post(path: "/\(credential.tenantID)/oauth2/v2.0/token",
            fields: ["grant_type": "refresh_token", "client_id": credential.clientID,
                     "refresh_token": credential.refreshToken, "scope": "offline_access Mail.Read"])
        let token = try JSONDecoder().decode(TokenReply.self, from: tokenData)
        if let rotated = token.refreshToken, rotated != credential.refreshToken {
            try OutlookKeychain.write(OutlookCredential(clientID: credential.clientID, tenantID: credential.tenantID, refreshToken: rotated))
        }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-180 * 86400))
        var components = URLComponents(string: "https://\(graphHost)/v1.0/me/mailFolders/inbox/messages")!
        components.queryItems = [URLQueryItem(name: "$select", value: "id,subject,body,from,receivedDateTime,webLink"),
                                 URLQueryItem(name: "$filter", value: "receivedDateTime ge \(since)"),
                                 URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
                                 URLQueryItem(name: "$top", value: "50")]
        var next = components.url
        var messages: [MailMessage] = []
        for _ in 0..<6 {
            guard let url = next else { break }
            guard url.scheme == "https", url.host == graphHost, url.path.hasPrefix("/v1.0/me/") else {
                throw OutlookError.message("微软返回了无效的邮件分页地址。")
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
            let data = try await send(request, allowedHost: graphHost)
            let page = try JSONDecoder().decode(MessagePage.self, from: data)
            for message in page.value {
                guard let received = ISO8601DateFormatter().date(from: message.receivedDateTime) else { continue }
                messages.append(MailMessage(id: message.id, subject: message.subject ?? "",
                                            body: String((message.body?.content ?? "").prefix(20_000)),
                                            sender: message.from?.emailAddress?.address ?? "",
                                            receivedAt: received, link: message.webLink.flatMap(URL.init(string:))))
            }
            next = page.nextLink.flatMap(URL.init(string:))
        }
        return messages
    }

    private func post(path: String, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://\(loginHost)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents(); body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        return try await send(request, allowedHost: loginHost)
    }

    private func send(_ request: URLRequest, allowedHost: String) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let delegate = SameHostRedirect(allowedHost: allowedHost)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= 5 * 1024 * 1024, let http = response as? HTTPURLResponse else {
                throw OutlookError.message("Outlook 响应无效或过大。")
            }
            if (200...299).contains(http.statusCode) { return data }
            if allowedHost == loginHost,
               let reply = try? JSONDecoder().decode(OAuthFailure.self, from: data) {
                throw OAuthError(code: reply.error)
            }
            if http.statusCode == 401 { throw OutlookError.message("Outlook 授权已失效，请断开后重新连接。") }
            if http.statusCode == 403 { throw OutlookError.message("学校账号未允许 Mail.Read；可能需要学校管理员批准。") }
            throw OutlookError.message("Outlook 请求失败（HTTP \(http.statusCode)）。")
        } catch let error as OutlookError { throw error }
        catch let error as OAuthError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw OutlookError.message("无法连接 Microsoft Outlook，请检查网络和学校账号授权。") }
    }
}

private final class SameHostRedirect: NSObject, URLSessionTaskDelegate {
    let allowedHost: String
    init(allowedHost: String) { self.allowedHost = allowedHost }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == allowedHost ? request : nil)
    }
}

private struct DeviceCodeReply: Decodable {
    let deviceCode: String, userCode: String, verificationUri: String
    let expiresIn: Int, interval: Int?
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code", verificationUri = "verification_uri"
        case expiresIn = "expires_in", interval
    }
}
private struct TokenReply: Decodable {
    let accessToken: String
    let refreshToken: String?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token" }
}
private struct OAuthFailure: Decodable { let error: String }
private struct OAuthError: LocalizedError {
    let code: String
    var errorDescription: String? { safeDescription }
    var safeDescription: String {
        switch code {
        case "invalid_client": return "Client ID 无效，或尚未启用 Public client flows。"
        case "invalid_grant": return "Outlook 授权已失效，请重新连接。"
        case "consent_required": return "学校账号需要管理员批准 Mail.Read。"
        default: return "Microsoft 登录失败（\(code.prefix(50))）。"
        }
    }
}
private struct MessagePage: Decodable {
    let value: [GraphMessage]
    let nextLink: String?
    enum CodingKeys: String, CodingKey { case value, nextLink = "@odata.nextLink" }
}
private struct GraphMessage: Decodable {
    let id: String
    let subject: String?
    let body: GraphBody?
    let from: GraphAddress?
    let receivedDateTime: String
    let webLink: String?
}
private struct GraphBody: Decodable { let content: String? }
private struct GraphAddress: Decodable { let emailAddress: GraphEmail? }
private struct GraphEmail: Decodable { let address: String? }
