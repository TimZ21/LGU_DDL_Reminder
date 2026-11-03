namespace Shiqi.Core;

public sealed class DeadlineStore
{
    private readonly ISnapshotStorage storage;
    private readonly IFeedCredential credential;
    private readonly FeedClient feed;
    private readonly SemaphoreSlim gate = new(1, 1);
    public Snapshot State { get; private set; }
    public bool CanPersist { get; }
    public string? LoadError { get; }
    public bool IsConnected => credential.Read() is not null;
    public event Action? Changed;

    public DeadlineStore(ISnapshotStorage storage, IFeedCredential credential, FeedClient feed)
    {
        this.storage = storage; this.credential = credential; this.feed = feed;
        try { State = storage.Load(); CanPersist = true; }
        catch { State = new(); CanPersist = false; LoadError = "Saved data could not be read. Saving is disabled to protect your files. / 本地数据无法读取，已停止保存以保护原文件。"; }
    }
    private Snapshot Copy(List<Deadline>? deadlines = null, Settings? settings = null) => new()
    {
        Deadlines = deadlines ?? State.Deadlines.ToList(), Settings = settings ?? State.Settings,
        LastSync = State.LastSync, Warnings = State.Warnings.ToList(), DeliveredReminders = new(State.DeliveredReminders)
    };
    private void Commit(Snapshot next)
    {
        if (!CanPersist) throw new IOException(LoadError);
        storage.Save(next); State = next; Changed?.Invoke();
    }
    public async Task<bool> SyncAsync(string? newLink = null, CancellationToken cancellation = default)
    {
        if (!await gate.WaitAsync(0, cancellation)) return false;
        try
        {
            if (!CanPersist) throw new IOException(LoadError);
            var old = credential.Read(); var value = newLink ?? old;
            if (value is null) return false;
            var address = FeedAddress.Validate(value);
            var text = await feed.FetchAsync(address, State.Settings, cancellation);
            var parsed = new CalendarParser(State.Settings).Parse(text);
            // Read the latest local completion state *after* awaiting the network request.
            var next = Copy(DeadlineMerger.Merge(State.Deadlines, parsed, DeadlineSource.Blackboard));
            next.Warnings = parsed.Warnings; next.LastSync = DateTimeOffset.UtcNow;
            if (newLink is not null) credential.Write(address.AbsoluteUri);
            try { Commit(next); }
            catch
            {
                if (newLink is not null) { if (old is null) credential.Delete(); else credential.Write(old); }
                throw;
            }
            return true;
        }
        finally { gate.Release(); }
    }
    public void Import(string text)
    {
        var parsed = new CalendarParser(State.Settings).Parse(text, DeadlineSource.File);
        var next = Copy(DeadlineMerger.Merge(State.Deadlines, parsed, DeadlineSource.File, false));
        next.Warnings = parsed.Warnings; Commit(next);
    }
    public void Upsert(Deadline item)
    {
        var items = State.Deadlines.ToList(); var index = items.FindIndex(d => d.Id == item.Id);
        if (index < 0) items.Add(item); else items[index] = item with { ReminderId = items[index].ReminderId };
        Commit(Copy(items));
    }
    public void Toggle(string id) => Commit(Copy(State.Deadlines.Select(d => d.Id == id ? d with { Completed = !d.Completed } : d).ToList()));
    public void Delete(string id) => Commit(Copy(State.Deadlines.Where(d => d.Id != id).ToList()));
    public void UpdateSettings(Settings settings) { settings.Validate(); Commit(Copy(settings: settings)); }
    public void Disconnect()
    {
        if (!gate.Wait(0)) throw new InvalidOperationException(State.Settings.Text("请等待同步完成。", "Wait for sync to finish."));
        try
        {
            var old = credential.Read();
            credential.Delete();
            var next = Copy(State.Deadlines.Where(d => d.Source != DeadlineSource.Blackboard).ToList()); next.LastSync = null; next.Warnings = [];
            try { Commit(next); }
            catch { if (old is not null) credential.Write(old); throw; }
        }
        finally { gate.Release(); }
    }
    public void RecordDelivered(IEnumerable<ReminderPlan> plans, DateTimeOffset now)
    {
        var next = Copy();
        next.DeliveredReminders = next.DeliveredReminders.Where(p => p.Value > now.AddDays(-32)).ToDictionary(p => p.Key, p => p.Value);
        foreach (var plan in plans) next.DeliveredReminders[plan.Key] = plan.FireDate;
        Commit(next);
    }
}
