import Foundation

public enum AppLanguage: String, Codable, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    public func text(_ chinese: String, _ english: String) -> String { self == .chinese ? chinese : english }
    public var locale: Locale { Locale(identifier: self == .chinese ? "zh_CN" : "en_GB") }
    public var appName: String { text("拾期", "Shiqi") }
    public func timeZoneName(_ identifier: String) -> String {
        switch identifier {
        case "Asia/Shanghai": return text("深圳 (UTC+8)", "Shenzhen (UTC+8)")
        case "Asia/Hong_Kong": return text("香港 (UTC+8)", "Hong Kong (UTC+8)")
        default: return identifier.replacingOccurrences(of: "_", with: " ")
        }
    }
    public func duration(_ minutes: Int) -> String {
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return text("\(days) 天", "\(days) \(days == 1 ? "day" : "days")")
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return text("\(hours) 小时", "\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        return text("\(minutes) 分钟", "\(minutes) \(minutes == 1 ? "minute" : "minutes")")
    }
    // Display formats only. Stored dates and iCalendar parsing never depend on UI language.
    public func datePattern(_ chinesePattern: String) -> String {
        guard self == .english else { return chinesePattern }
        switch chinesePattern {
        case "M月d日 EEEE HH:mm": return "EEE, d MMM HH:mm"
        case "M月d日 EEEE（具体时间待确认）": return "EEE, d MMM '· Time to confirm'"
        case "yyyy年M月d日 EEEE": return "EEEE, d MMMM yyyy"
        case "yyyy年M月d日 EEEE HH:mm:ss": return "EEEE, d MMMM yyyy HH:mm:ss"
        case "M/d E · 时间待确认": return "d MMM E '· Time to confirm'"
        case "M/d E HH:mm": return "d MMM E HH:mm"
        case "M/d HH:mm": return "d MMM HH:mm"
        default: return chinesePattern
        }
    }
}
