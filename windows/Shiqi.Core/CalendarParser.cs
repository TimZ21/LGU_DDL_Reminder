using System.Globalization;
using System.Text;

namespace Shiqi.Core;

// A direct port of DeadlineCore's conservative iCalendar subset. Never guess an unsupported date/rule.
public sealed class CalendarParser(Settings? settings = null)
{
    private readonly Settings settings = settings ?? new();
    private sealed record Property(string Name, Dictionary<string, string> Parameters, string Value);
    private sealed record CalendarDate(DateTimeOffset Instant, bool HasTime, TimeZoneInfo Zone);
    private string T(string zh, string en) => settings.Text(zh, en);

    public ParsedCalendar Parse(string text, DeadlineSource source = DeadlineSource.Blackboard, DateTimeOffset? now = null)
    {
        if (Encoding.UTF8.GetByteCount(text) > FeedClient.MaximumBytes) throw new FormatException(T("日历超过 5 MB。", "The calendar exceeds 5 MB."));
        var lines = new List<string>();
        foreach (var line in text.TrimStart('\uFEFF').Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if (line.Length > 0 && line[0] is ' ' or '\t' && lines.Count > 0) lines[^1] += line[1..];
            else lines.Add(line);
        }
        if (!lines.Contains("BEGIN:VCALENDAR") || !lines.Contains("END:VCALENDAR"))
            throw new FormatException(T("没有收到有效日历。请检查完整共享链接、校园网或 VPN。", "No valid calendar received. Check the full sharing link and campus network/VPN."));
        var zone = settings.Zone;
        var declared = lines.FirstOrDefault(l => l.StartsWith("X-WR-TIMEZONE:", StringComparison.Ordinal));
        if (declared is not null) zone = Zones.Find(declared[14..]);
        var blocks = new List<List<Property>>();
        List<Property>? current = null;
        string? kind = null;
        var nested = 0;
        foreach (var line in lines)
        {
            if (line is "BEGIN:VEVENT" or "BEGIN:VTODO")
            {
                if (current is not null) throw new FormatException(T("日历事件结构不完整。", "Incomplete calendar event structure."));
                current = []; kind = line[6..]; nested = 0;
            }
            else if (line is "END:VEVENT" or "END:VTODO")
            {
                if (current is null || line[4..] != kind || nested != 0) throw new FormatException(T("日历事件结构不完整。", "Incomplete calendar event structure."));
                blocks.Add(current); current = null;
            }
            else if (current is not null)
            {
                if (line.StartsWith("BEGIN:", StringComparison.Ordinal)) nested++;
                else if (line.StartsWith("END:", StringComparison.Ordinal))
                {
                    if (nested == 0) throw new FormatException(T("日历文件被截断。", "The calendar is truncated."));
                    nested--;
                }
                else if (nested == 0 && ReadProperty(line) is { } property) current.Add(property);
            }
        }
        if (current is not null) throw new FormatException(T("日历文件被截断，已保留原数据。", "The calendar is truncated. Previous data is kept."));
        Property? First(List<Property> props, string key) => props.FirstOrDefault(p => p.Name == key);
        var overrideKeys = new HashSet<string>();
        foreach (var block in blocks)
        {
            if (First(block, "UID") is { } uid && First(block, "RECURRENCE-ID") is { } recurrence)
                try { overrideKeys.Add(uid.Value + "|" + ParseDate(recurrence, zone).Instant.ToUnixTimeSeconds()); } catch (FormatException) { }
        }
        var output = new Dictionary<string, Deadline>();
        var warnings = new List<string>();
        var protectedIds = new HashSet<string>();
        foreach (var block in blocks)
        {
            var title = Unescape(First(block, "SUMMARY")?.Value ?? T("未命名日历事项", "Untitled calendar item"));
            var uid = First(block, "UID")?.Value ?? StableId(string.Join("|", block.Select(p => p.Value)));
            var prefix = source.ToString().ToLowerInvariant() + ":" + uid;
            if (First(block, "STATUS")?.Value.ToUpperInvariant() == "CANCELLED") continue;
            try
            {
                var start = First(block, "DUE") ?? First(block, "DTSTART")
                    ?? throw new FormatException(T("没有提供截止日期", "No due date provided"));
                var date = ParseDate(start, zone);
                var recurrence = First(block, "RECURRENCE-ID");
                var recurrenceDate = recurrence is null ? (DateTimeOffset?)null : ParseDate(recurrence, zone).Instant;
                var rule = First(block, "RRULE");
                var recurring = rule is not null || First(block, "RDATE") is not null;
                var dates = rule is null ? new List<DateTimeOffset> { date.Instant }
                    : Occurrences(rule.Value, date.Instant, date.Zone, now ?? DateTimeOffset.UtcNow);
                foreach (var extra in block.Where(p => p.Name == "RDATE"))
                    foreach (var value in extra.Value.Split(',')) dates.Add(ParseDate(extra with { Value = value }, zone).Instant);
                var excluded = new HashSet<DateTimeOffset>();
                foreach (var exception in block.Where(p => p.Name == "EXDATE"))
                    foreach (var value in exception.Value.Split(',')) excluded.Add(ParseDate(exception with { Value = value }, zone).Instant);
                var course = Unescape((First(block, "X-BB-COURSE-NAME") ?? First(block, "X-BLACKBOARD-COURSE-NAME") ?? First(block, "CATEGORIES"))?.Value ?? "");
                var notes = Unescape(First(block, "DESCRIPTION")?.Value ?? "");
                var rawLink = First(block, "URL")?.Value;
                var link = Uri.TryCreate(rawLink, UriKind.Absolute, out var parsedLink) && parsedLink.Scheme == "https" && parsedLink.UserInfo.Length == 0 ? parsedLink.AbsoluteUri : null;
                foreach (var due in dates.Distinct().Order().Where(d => !excluded.Contains(d)))
                {
                    var stamp = (recurrenceDate ?? due).ToUnixTimeSeconds();
                    if (recurrence is null && recurring && overrideKeys.Contains(uid + "|" + stamp)) continue;
                    var id = recurring || recurrence is not null ? prefix + "|" + stamp : prefix;
                    output[id] = new Deadline { Id = id, Title = title, Course = course, Notes = notes,
                        DueDate = due, HasTime = date.HasTime, Source = source, Link = link };
                }
            }
            catch (Exception e) when (e is FormatException or ArgumentException or OverflowException)
            {
                protectedIds.Add(prefix);
                warnings.Add(T($"「{title}」未能导入：{e.Message}", $"Could not import “{title}”: {e.Message}"));
            }
        }
        return new(output.Values.OrderBy(d => d.DueDate).ToList(), warnings, protectedIds);
    }

    private static Property? ReadProperty(string line)
    {
        var quoted = false;
        var colon = -1;
        for (var i = 0; i < line.Length; i++)
        {
            if (line[i] == '"') quoted = !quoted;
            if (line[i] == ':' && !quoted) { colon = i; break; }
        }
        if (colon < 1) return null;
        var pieces = new List<string>(); var piece = new StringBuilder(); quoted = false;
        foreach (var c in line[..colon])
        {
            if (c == '"') quoted = !quoted;
            if (c == ';' && !quoted) { pieces.Add(piece.ToString()); piece.Clear(); } else piece.Append(c);
        }
        pieces.Add(piece.ToString());
        var parameters = new Dictionary<string, string>();
        foreach (var parameter in pieces.Skip(1))
        {
            var pair = parameter.Split('=', 2);
            if (pair.Length == 2) parameters[pair[0].ToUpperInvariant()] = pair[1].Trim('"');
        }
        return new(pieces[0].ToUpperInvariant(), parameters, line[(colon + 1)..]);
    }

    private static CalendarDate ParseDate(Property p, TimeZoneInfo defaultZone)
    {
        var hasTime = p.Parameters.GetValueOrDefault("VALUE") != "DATE" && p.Value.Contains('T');
        var zone = p.Value.EndsWith('Z') ? TimeZoneInfo.Utc : p.Parameters.TryGetValue("TZID", out var id) ? Zones.Find(id) : defaultZone;
        var raw = p.Value.TrimEnd('Z');
        if (raw.Length != (hasTime ? 15 : 8) || !DateTime.TryParseExact(raw,
            hasTime ? "yyyyMMdd'T'HHmmss" : "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var local))
            throw new FormatException("Invalid date or time / 日期或时间无效");
        return new(Zones.LocalInstant(local, zone), hasTime, zone);
    }

    private static List<DateTimeOffset> Occurrences(string rule, DateTimeOffset start, TimeZoneInfo zone, DateTimeOffset now)
    {
        var fields = new Dictionary<string, string>();
        foreach (var piece in rule.Split(';'))
        {
            var pair = piece.Split('=', 2);
            if (pair.Length != 2 || !fields.TryAdd(pair[0].ToUpperInvariant(), pair[1].ToUpperInvariant())) throw new FormatException("Invalid recurrence rule / 重复规则无效");
        }
        string[] supported = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"];
        var frequency = fields.GetValueOrDefault("FREQ");
        if (fields.Keys.Except(supported).Any() || frequency is not ("DAILY" or "WEEKLY") || fields.GetValueOrDefault("WKST", "MO") != "MO")
            throw new FormatException("Unsupported recurrence; add manually / 暂不支持此重复规则，请手动补充");
        if (!int.TryParse(fields.GetValueOrDefault("INTERVAL", "1"), out var interval) || interval <= 0
            || !int.TryParse(fields.GetValueOrDefault("COUNT", "100000"), out var count) || count <= 0)
            throw new FormatException("Invalid recurrence rule / 重复规则无效");
        var lower = now.AddDays(-30); var upper = now.AddYears(1);
        if (fields.TryGetValue("UNTIL", out var until))
        {
            var end = ParseDate(new("UNTIL", [], until), zone);
            var limit = end.HasTime ? end.Instant : Zones.LocalInstant(TimeZoneInfo.ConvertTime(end.Instant, zone).Date.AddDays(1), zone).AddTicks(-1);
            if (limit < upper) upper = limit;
        }
        var codes = new Dictionary<string, DayOfWeek> { ["SU"] = DayOfWeek.Sunday, ["MO"] = DayOfWeek.Monday,
            ["TU"] = DayOfWeek.Tuesday, ["WE"] = DayOfWeek.Wednesday, ["TH"] = DayOfWeek.Thursday, ["FR"] = DayOfWeek.Friday, ["SA"] = DayOfWeek.Saturday };
        var localStart = TimeZoneInfo.ConvertTime(start, zone).DateTime;
        var weekdays = new HashSet<DayOfWeek> { localStart.DayOfWeek };
        if (fields.TryGetValue("BYDAY", out var byDay))
        {
            var days = byDay.Split(',');
            if (days.Any(d => !codes.ContainsKey(d))) throw new FormatException("Unsupported recurrence weekdays / 不支持此重复星期规则");
            weekdays = days.Select(d => codes[d]).ToHashSet();
        }
        var weekStart = localStart.Date.AddDays(-(((int)localStart.DayOfWeek + 6) % 7));
        var result = new List<DateTimeOffset>(); var index = 0;
        for (var day = 0; ; day++)
        {
            if (day > 40000) throw new FormatException("Recurring range too large / 重复范围过大");
            var local = localStart.AddDays(day);
            var instant = Zones.LocalInstant(local, zone);
            if (instant > upper || index >= count) break;
            var weeks = (int)(local.Date - weekStart).TotalDays / 7;
            var matches = frequency == "DAILY" ? day % interval == 0 && (!fields.ContainsKey("BYDAY") || weekdays.Contains(local.DayOfWeek))
                : weeks % interval == 0 && weekdays.Contains(local.DayOfWeek);
            if (!matches) continue;
            index++;
            if (instant >= lower) result.Add(instant);
        }
        return result;
    }

    private static string Unescape(string text)
    {
        var result = new StringBuilder(); var escaped = false;
        foreach (var c in text)
        {
            if (escaped) { result.Append(c is 'n' or 'N' ? '\n' : c); escaped = false; }
            else if (c == '\\') escaped = true; else result.Append(c);
        }
        if (escaped) result.Append('\\');
        return result.ToString();
    }
    private static string StableId(string text)
    {
        var hash = 14695981039346656037UL;
        foreach (var b in Encoding.UTF8.GetBytes(text)) hash = unchecked((hash ^ b) * 1099511628211UL);
        return hash.ToString("x", CultureInfo.InvariantCulture);
    }
}
