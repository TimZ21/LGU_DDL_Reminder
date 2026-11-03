namespace Shiqi.Core;

public sealed record ReminderPlan(string Key, Deadline Deadline, DateTimeOffset FireDate, string Subtitle);

public static class ReminderPlanner
{
    public static List<ReminderPlan> Plans(IEnumerable<Deadline> deadlines, Settings settings, DateTimeOffset after)
    {
        if (!settings.NotificationsEnabled) return [];
        var plans = new List<ReminderPlan>();
        foreach (var item in deadlines.Where(d => !d.Completed))
        {
            void Add(DateTimeOffset fire, string suffix, string subtitle)
            {
                if (fire > after) plans.Add(new($"{item.ReminderId}.{item.DueDate.ToUnixTimeSeconds()}.{suffix}", item, fire, subtitle));
            }
            if (item.HasTime)
                foreach (var minutes in settings.ReminderMinutes.Distinct())
                    Add(item.DueDate.AddMinutes(-minutes), "m" + minutes,
                        minutes == 0 ? settings.Text("截止时间到了", "Deadline reached") : settings.Text($"距截止 {minutes} 分钟", $"Due in {minutes} minutes"));
            else
                foreach (var offset in new[] { -1, 0 })
                {
                    var local = TimeZoneInfo.ConvertTime(item.DueDate, settings.Zone).Date.AddDays(offset).AddHours(9);
                    Add(Zones.LocalInstant(local, settings.Zone), $"{settings.TimeZoneId}.day{offset}",
                        offset == 0 ? settings.Text("今天到期 · 具体时间待确认", "Due today · Time to confirm") : settings.Text("明天到期 · 具体时间待确认", "Due tomorrow · Time to confirm"));
                }
        }
        return plans.OrderBy(p => p.FireDate).ToList();
    }
    public static List<ReminderPlan> Due(IEnumerable<Deadline> deadlines, Settings settings,
        IReadOnlyDictionary<string, DateTimeOffset> delivered, DateTimeOffset since, DateTimeOffset now)
    {
        // After resume/restart, only catch up the last five minutes; avoid a flood of old reminders.
        var lower = since > now.AddMinutes(-5) ? since : now.AddMinutes(-5);
        return Plans(deadlines, settings, lower).Where(p => p.FireDate <= now && !delivered.ContainsKey(p.Key)).ToList();
    }
}
