using System.Globalization;
using System.Text.Json.Serialization;

namespace Shiqi.Core;

public enum DeadlineSource { Blackboard, Manual, File }

public sealed record Deadline
{
    [JsonRequired] public string Id { get; init; } = Guid.NewGuid().ToString();
    [JsonRequired] public string ReminderId { get; init; } = Guid.NewGuid().ToString();
    [JsonRequired] public string Title { get; init; } = "";
    [JsonRequired] public string Course { get; init; } = "";
    [JsonRequired] public string Notes { get; init; } = "";
    [JsonRequired] public DateTimeOffset DueDate { get; init; }
    [JsonRequired] public bool HasTime { get; init; } = true;
    [JsonRequired] public DeadlineSource Source { get; init; } = DeadlineSource.Manual;
    public string? Link { get; init; }
    [JsonRequired] public bool Completed { get; init; }

    public bool IsOverdue(DateTimeOffset now, TimeZoneInfo zone) => HasTime ? DueDate < now
        : TimeZoneInfo.ConvertTime(DueDate, zone).Date < TimeZoneInfo.ConvertTime(now, zone).Date;
}

public sealed record Settings
{
    public string Language { get; init; } = "zh";
    public string TimeZoneId { get; init; } = "Asia/Shanghai";
    public int SyncMinutes { get; init; } = 15;
    public int[] ReminderMinutes { get; init; } = [1440, 180, 30, 0];
    public bool NotificationsEnabled { get; init; } = true;
    public TimeZoneInfo Zone => Zones.Find(TimeZoneId);
    public string Text(string chinese, string english) => Language == "en" ? english : chinese;
    public string ZoneLabel => TimeZoneId == "Asia/Shanghai" ? Text("深圳 (UTC+8)", "Shenzhen (UTC+8)")
        : TimeZoneId == "Asia/Hong_Kong" ? Text("香港 (UTC+8)", "Hong Kong (UTC+8)") : TimeZoneId;
    public string Format(Deadline item) => TimeZoneInfo.ConvertTime(item.DueDate, Zone).ToString(
        item.HasTime ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd", CultureInfo.InvariantCulture)
        + (item.HasTime ? "" : Text(" · 具体时间待确认", " · Time to confirm"));
    public void Validate()
    {
        if (Language is not ("zh" or "en") || SyncMinutes is not (5 or 15 or 30 or 60)
            || ReminderMinutes is null || ReminderMinutes.Length > 12 || ReminderMinutes.Any(x => x < 0 || x > 10080))
            throw new InvalidDataException("Invalid settings.");
        _ = Zone;
    }
}

public sealed class Snapshot
{
    public int SchemaVersion { get; set; } = 1;
    [JsonRequired] public List<Deadline> Deadlines { get; set; } = [];
    [JsonRequired] public Settings Settings { get; set; } = new();
    public DateTimeOffset? LastSync { get; set; }
    public List<string> Warnings { get; set; } = [];
    // Keys contain local identities and dates, never a calendar subscription URL.
    public Dictionary<string, DateTimeOffset> DeliveredReminders { get; set; } = [];
    public void Validate()
    {
        if (SchemaVersion != 1 || Deadlines is null || Settings is null || Warnings is null || DeliveredReminders is null)
            throw new InvalidDataException("Unsupported or incomplete saved data.");
        Settings.Validate();
        if (Deadlines.Count > 50000 || Deadlines.Any(d => string.IsNullOrWhiteSpace(d.Id)
            || string.IsNullOrWhiteSpace(d.ReminderId) || d.Title is null || d.Course is null || d.Notes is null
            || !Enum.IsDefined(d.Source) || d.DueDate == default)
            || Deadlines.Select(d => d.Id).Distinct().Count() != Deadlines.Count)
            throw new InvalidDataException("Invalid saved deadlines.");
    }
}

public static class Zones
{
    public static TimeZoneInfo Find(string id)
    {
        if (id is "UTC" or "Etc/UTC" or "GMT") return TimeZoneInfo.Utc;
        if (id is "China Standard Time" or "Hong Kong Standard Time") id = "Asia/Shanghai";
        if (TimeZoneInfo.TryFindSystemTimeZoneById(id, out var zone)) return zone;
        if (TimeZoneInfo.TryConvertIanaIdToWindowsId(id, out var windowsId)
            && TimeZoneInfo.TryFindSystemTimeZoneById(windowsId, out zone)) return zone;
        throw new FormatException("Unsupported time zone / 不支持的时区: " + id);
    }
    public static DateTimeOffset LocalInstant(DateTime local, TimeZoneInfo zone)
    {
        local = DateTime.SpecifyKind(local, DateTimeKind.Unspecified);
        if (zone.IsInvalidTime(local)) throw new FormatException("Invalid local time / 无效的本地时间");
        // Choose the earlier occurrence consistently for a fall-back clock ambiguity.
        var offset = zone.IsAmbiguousTime(local) ? zone.GetAmbiguousTimeOffsets(local).Max() : zone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToUniversalTime();
    }
}

public sealed record ParsedCalendar(List<Deadline> Deadlines, List<string> Warnings, HashSet<string> ProtectedPrefixes);
