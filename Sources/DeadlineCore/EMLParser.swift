import Foundation
import CryptoKit

public enum EMLParserError: LocalizedError {
    case invalid
    public var errorDescription: String? { "邮件文件不是受支持的 .eml 格式。" }
}

public struct EMLParser {
    public init() {}

    public func parse(_ data: Data) throws -> MailMessage {
        guard !data.isEmpty, data.count <= 5 * 1024 * 1024 else { throw EMLParserError.invalid }
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let raw else { throw EMLParserError.invalid }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let split = normalized.range(of: "\n\n") else { throw EMLParserError.invalid }
        let headers = parseHeaders(String(normalized[..<split.lowerBound]))
        guard headers["from"] != nil, headers["subject"] != nil else { throw EMLParserError.invalid }
        let body = String(normalized[split.upperBound...])
        let content = extractBody(headers: headers, body: body)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let date = parseDate(headers["date"] ?? "") ?? Date()
        return MailMessage(id: "eml-\(digest)", subject: decodeHeader(headers["subject"] ?? ""),
                           body: content, sender: decodeHeader(headers["from"] ?? ""), receivedAt: date)
    }

    private func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let key = current { headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces) }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value; current = key
        }
        return headers
    }

    private func extractBody(headers: [String: String], body: String) -> String {
        let parts = textParts(headers: headers, body: body, depth: 0)
        guard let best = parts.first(where: { $0.isPlain }) ?? parts.first else { return "" }
        return String(best.text.prefix(20_000))
    }

    private func textParts(headers: [String: String], body: String, depth: Int) -> [(text: String, isPlain: Bool)] {
        guard depth < 6,
              !headers["content-disposition", default: ""].lowercased().contains("attachment") else { return [] }
        let contentType = headers["content-type", default: "text/plain"].lowercased()
        if contentType.hasPrefix("multipart/"), let boundary = parameter("boundary", in: headers["content-type"] ?? "") {
            let parts = body.components(separatedBy: "--" + boundary)
            var found: [(text: String, isPlain: Bool)] = []
            for part in parts {
                guard let split = part.range(of: "\n\n") else { continue }
                let partHeaders = parseHeaders(String(part[..<split.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
                guard partHeaders["content-type"] != nil else { continue }
                found += textParts(headers: partHeaders, body: String(part[split.upperBound...]), depth: depth + 1)
            }
            return found
        }
        guard contentType.hasPrefix("text/plain") || contentType.hasPrefix("text/html") else { return [] }
        let decoded = decodeBody(body, headers: headers)
        let plain = contentType.hasPrefix("text/plain")
        return [(text: plain ? decoded : htmlToText(decoded), isPlain: plain)]
    }

    private func decodeBody(_ body: String, headers: [String: String]) -> String {
        let encoding = headers["content-transfer-encoding", default: ""].lowercased()
        let bytes: Data
        if encoding.contains("base64") {
            bytes = Data(base64Encoded: body, options: .ignoreUnknownCharacters) ?? Data()
        } else if encoding.contains("quoted-printable") {
            bytes = decodeQuotedPrintable(body)
        } else { bytes = Data(body.utf8) }
        let charset = parameter("charset", in: headers["content-type"] ?? "")?.lowercased() ?? "utf-8"
        if charset == "iso-8859-1" || charset == "latin1" { return String(data: bytes, encoding: .isoLatin1) ?? "" }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    private func decodeQuotedPrintable(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        var output = Data(); var index = 0
        while index < bytes.count {
            if bytes[index] == 61, index + 1 < bytes.count { // '='
                if bytes[index + 1] == 10 { index += 2; continue }
                if index + 2 < bytes.count,
                   let hi = hex(bytes[index + 1]), let lo = hex(bytes[index + 2]) {
                    output.append(hi * 16 + lo); index += 3; continue
                }
            }
            output.append(bytes[index]); index += 1
        }
        return output
    }

    private func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private func parameter(_ name: String, in text: String) -> String? {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*(?:\"([^\"]+)\"|([^;\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in [1, 2] {
            if let range = Range(match.range(at: index), in: text) { return String(text[range]) }
        }
        return nil
    }

    private func decodeHeader(_ text: String) -> String {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: output),
                  let encodedRange = Range(match.range(at: 3), in: text),
                  let encodingRange = Range(match.range(at: 2), in: text) else { continue }
            let encoded = String(text[encodedRange])
            let bytes = String(text[encodingRange]).lowercased() == "b"
                ? (Data(base64Encoded: encoded) ?? Data())
                : decodeQuotedPrintable(encoded.replacingOccurrences(of: "_", with: " "))
            if let decoded = String(data: bytes, encoding: .utf8) { output.replaceSubrange(whole, with: decoded) }
        }
        return output
    }

    private func htmlToText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"(?i)<(br\s*/?|/p|/div|/li)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, value) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\""] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }

    private func parseDate(_ text: String) -> Date? {
        let cleaned = text.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }
}
