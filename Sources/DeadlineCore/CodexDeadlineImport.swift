import Foundation
import CryptoKit

public enum CodexImportError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let detail) = self { return "Codex 导入文件无效：\(detail)" }
        return nil
    }
}

/// Local handoff format for deadlines confirmed by Codex. No mailbox credentials or message bodies.
public enum CodexDeadlineImport {
    public static func matchesExisting(_ incoming: Deadline, existing: Deadline, timeZone: TimeZone) -> Bool {
        guard incoming.id != existing.id else { return true }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let title = normalizedTitle(incoming.title)
        guard calendar.isDate(incoming.dueDate, inSameDayAs: existing.dueDate),
              !title.isEmpty, title == normalizedTitle(existing.title) else { return false }
        if incoming.hasTime && existing.hasTime && abs(incoming.dueDate.timeIntervalSince(existing.dueDate)) > 60 {
            return false
        }
        let incomingCode = courseCode(incoming.course + " " + incoming.title)
        let existingCode = courseCode(existing.course + " " + existing.title)
        return incomingCode == nil || existingCode == nil || incomingCode == existingCode
    }

    private static func normalizedTitle(_ title: String) -> String {
        let withoutCode = title.lowercased().replacingOccurrences(of: #"[a-z]{2,4}\s?\d{4}"#, with: "", options: .regularExpression)
        return String(withoutCode.filter { $0.isLetter || $0.isNumber })
    }

    private static func courseCode(_ text: String) -> String? {
        guard let range = text.range(of: #"[A-Z]{2,4}\s?\d{4}"#, options: .regularExpression) else { return nil }
        return String(text[range]).replacingOccurrences(of: " ", with: "")
    }

    private struct Package: Decodable {
        let version: Int
        let items: [Item]
    }
    private struct Item: Decodable {
        let id: String?
        let title: String
        let course: String?
        let dueAt: String
        let hasTime: Bool
        let evidence: String?
        let link: String?
    }

    public static func parse(_ data: Data, timeZone: TimeZone) throws -> [Deadline] {
        guard !data.isEmpty, data.count <= 1024 * 1024 else { throw CodexImportError.invalid("文件必须小于 1 MB。") }
        let package: Package
        do { package = try JSONDecoder().decode(Package.self, from: data) }
        catch { throw CodexImportError.invalid("JSON 结构不符合接口格式。") }
        guard package.version == 1, !package.items.isEmpty, package.items.count <= 100 else {
            throw CodexImportError.invalid("版本须为 1，每份文件包含 1 至 100 个事项。")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var result: [Deadline] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for item in package.items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let course = (item.course ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 200, course.count <= 120 else {
                throw CodexImportError.invalid("任务标题或课程名称长度不合法。")
            }
            let date: Date
            if item.hasTime {
                guard let parsed = formatter.date(from: item.dueAt) ?? ISO8601DateFormatter().date(from: item.dueAt) else {
                    throw CodexImportError.invalid("有具体时间的事项须使用带时区的 ISO 8601 时间。")
                }
                date = parsed
            } else {
                let pieces = item.dueAt.split(separator: "-").compactMap { Int($0) }
                guard pieces.count == 3, pieces[0] >= 2000, pieces[0] <= 2100,
                      let parsed = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])),
                      calendar.component(.year, from: parsed) == pieces[0],
                      calendar.component(.month, from: parsed) == pieces[1],
                      calendar.component(.day, from: parsed) == pieces[2] else {
                    throw CodexImportError.invalid("无具体时间的事项须使用 YYYY-MM-DD 日期。")
                }
                date = parsed
            }
            let rawID = item.id ?? [title, course, item.dueAt].joined(separator: "|")
            guard rawID.count <= 500 else { throw CodexImportError.invalid("事项 ID 过长。") }
            let digest = SHA256.hash(data: Data(rawID.utf8)).map { String(format: "%02x", $0) }.joined()
            let evidence = String((item.evidence ?? "").prefix(500))
            var link: URL?
            if let rawLink = item.link, !rawLink.isEmpty {
                guard let url = URL(string: rawLink), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil else { throw CodexImportError.invalid("邮件链接必须是 HTTPS 地址。") }
                link = url
            }
            let notes = evidence.isEmpty ? "由 Codex 从 Outlook 邮件核对后添加。" : "由 Codex 从 Outlook 邮件核对后添加。\n\(evidence)"
            result.append(Deadline(id: "codex-outlook:\(digest)", title: title, course: course, notes: notes,
                                   dueDate: date, hasTime: item.hasTime, source: .outlook, link: link))
        }
        return result
    }
}
