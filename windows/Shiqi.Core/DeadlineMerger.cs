namespace Shiqi.Core;

public static class DeadlineMerger
{
    private static string? CalendarId(Deadline d) => d.Source == DeadlineSource.Manual ? null
        : d.Id.StartsWith(d.Source.ToString().ToLowerInvariant() + ":", StringComparison.Ordinal) ? d.Id[(d.Id.IndexOf(':') + 1)..] : null;
    private static (string, string, DateTimeOffset, bool) Fingerprint(Deadline d) => (d.Title.Trim(), d.Course.Trim(), d.DueDate, d.HasTime);

    public static List<Deadline> Merge(IReadOnlyList<Deadline> previous, ParsedCalendar parsed, DeadlineSource source, bool removeMissing = true)
    {
        var eligible = Enumerable.Range(0, previous.Count).Where(i => previous[i].Source == source
            || source != DeadlineSource.Manual && previous[i].Source != DeadlineSource.Manual).ToArray();
        var byId = eligible.GroupBy(i => previous[i].Id).ToDictionary(g => g.Key, g => g.ToArray());
        var byCalendar = eligible.Where(i => CalendarId(previous[i]) is not null).GroupBy(i => CalendarId(previous[i])!).ToDictionary(g => g.Key, g => g.ToArray());
        var byTask = eligible.GroupBy(i => Fingerprint(previous[i])).ToDictionary(g => g.Key, g => g.ToArray());
        var incoming = parsed.Deadlines.GroupBy(Fingerprint).ToDictionary(g => g.Key, g => g.Count());
        var matches = new Dictionary<int, int>(); var consumed = new HashSet<int>();
        void Match(int index, int[]? candidates)
        {
            if (!matches.ContainsKey(index) && candidates is { Length: 1 } && consumed.Add(candidates[0])) matches[index] = candidates[0];
        }
        for (var i = 0; i < parsed.Deadlines.Count; i++) Match(i, byId.GetValueOrDefault(parsed.Deadlines[i].Id));
        for (var i = 0; i < parsed.Deadlines.Count; i++)
            if (CalendarId(parsed.Deadlines[i]) is { } id) Match(i, byCalendar.GetValueOrDefault(id));
        for (var i = 0; i < parsed.Deadlines.Count; i++)
        {
            var key = Fingerprint(parsed.Deadlines[i]);
            if (!string.IsNullOrEmpty(key.Item1) && incoming[key] == 1) Match(i, byTask.GetValueOrDefault(key));
        }
        var fresh = parsed.Deadlines.Select((d, i) =>
        {
            if (!matches.TryGetValue(i, out var index)) return d;
            var prior = previous[index];
            return d with { Completed = prior.Completed, ReminderId = prior.ReminderId,
                Id = source == DeadlineSource.File && prior.Source == DeadlineSource.Blackboard ? prior.Id : d.Id,
                Source = source == DeadlineSource.File && prior.Source == DeadlineSource.Blackboard ? prior.Source : d.Source };
        });
        return previous.Where((d, i) => !consumed.Contains(i) && (!removeMissing || d.Source != source
                || parsed.ProtectedPrefixes.Any(p => d.Id == p || d.Id.StartsWith(p + "|", StringComparison.Ordinal))))
            .Concat(fresh).OrderBy(d => d.DueDate).ToList();
    }
}
