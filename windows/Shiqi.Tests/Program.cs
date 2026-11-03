using System.Net;
using System.Text;
using System.Text.Json;
using Shiqi.Core;
using Shiqi.Desktop;

var tests = new List<(string Name, Func<Task> Run)>();
void Test(string name, Action run) => tests.Add((name, () => { run(); return Task.CompletedTask; }));
void AsyncTest(string name, Func<Task> run) => tests.Add((name, run));
void Check(bool value, string detail = "Assertion failed") { if (!value) throw new Exception(detail); }
void Equal<T>(T expected, T actual) => Check(EqualityComparer<T>.Default.Equals(expected, actual), $"Expected {expected}; got {actual}");
void Throws(Action run) { try { run(); } catch { return; } throw new Exception("Expected a failure"); }
async Task<string> Fails(Func<Task> run) { try { await run(); } catch (Exception e) { return e.Message; } throw new Exception("Expected a failure"); }
DateTimeOffset D(string value) => DateTimeOffset.Parse(value, System.Globalization.CultureInfo.InvariantCulture);
string Event(string body) => "BEGIN:VEVENT\r\n" + body + "\r\nEND:VEVENT";
string Calendar(string body) => "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + body + "\r\nEND:VCALENDAR";
var now = D("2026-10-01T00:00:00Z");
var settings = new Settings();
var parser = new CalendarParser(settings);
ParsedCalendar Parse(string body, DeadlineSource source = DeadlineSource.Blackboard) => parser.Parse(Calendar(body), source, now);
Deadline Item(string id = "blackboard:a", bool completed = false) => new() { Id = id, Title = "Homework", Course = "MAT1001", DueDate = D("2026-10-09T15:59:00Z"), Source = DeadlineSource.Blackboard, Completed = completed };

Test("UTC instant and Shenzhen display", () =>
{
    var item = Parse(Event("UID:a\r\nSUMMARY:Homework\r\nDTSTART:20261009T155900Z")).Deadlines.Single();
    Equal(D("2026-10-09T23:59:00+08:00"), item.DueDate); Check(settings.Format(item).Contains("23:59")); Equal("深圳 (UTC+8)", settings.ZoneLabel);
});
Test("TZID, Windows zone aliases, floating times", () =>
{
    foreach (var property in new[] { "DTSTART;TZID=Asia/Hong_Kong:20261009T235900", "DTSTART;TZID=China Standard Time:20261009T235900", "DTSTART:20261009T235900" })
        Equal(D("2026-10-09T15:59:00Z"), Parse(Event("UID:a\r\n" + property)).Deadlines.Single().DueDate);
});
Test("Calendar's declared time zone", () => Equal(D("2026-10-10T03:59:00Z"), Parse("X-WR-TIMEZONE:America/New_York\r\n" + Event("UID:a\r\nDTSTART:20261009T235900")).Deadlines.Single().DueDate));
Test("All-day is not an invented midnight deadline", () =>
{
    var item = Parse(Event("UID:all\r\nDTSTART;VALUE=DATE:20261009")).Deadlines.Single();
    Check(!item.HasTime); Check(!item.IsOverdue(D("2026-10-09T23:59:59+08:00"), settings.Zone)); Check(item.IsOverdue(D("2026-10-10T00:00:00+08:00"), settings.Zone));
    var plans = ReminderPlanner.Plans([item], settings, now);
    Equal(2, plans.Count); Equal(D("2026-10-08T09:00:00+08:00"), plans[0].FireDate); Equal(D("2026-10-09T09:00:00+08:00"), plans[1].FireDate);
});
Test("Folded Unicode, escaped notes, quoted TZID, nested alarms", () =>
{
    var item = Parse(Event("UID:a\r\nSUMMARY:作业\\,第三\r\n 次\\;概率论\r\nDESCRIPTION:一\\n二\\\\路径\r\nDTSTART;TZID=\"Asia/Shanghai\":20261009T235900\r\nBEGIN:VALARM\r\nDTSTART:20260101T000000Z\r\nEND:VALARM")).Deadlines.Single();
    Equal("作业,第三次;概率论", item.Title); Equal("一\n二\\路径", item.Notes); Equal(D("2026-10-09T15:59:00Z"), item.DueDate);
});
Test("VTODO uses DUE rather than DTSTART", () => Equal(D("2026-10-09T12:00:00Z"), Parse("BEGIN:VTODO\r\nUID:a\r\nDTSTART:20261001T120000Z\r\nDUE:20261009T120000Z\r\nEND:VTODO").Deadlines.Single().DueDate));
Test("Empty calendar and cancelled events are valid", () => { Equal(0, Parse("").Deadlines.Count); Equal(0, Parse(Event("UID:a\r\nDTSTART:20261009T120000Z\r\nSTATUS:CANCELLED")).Deadlines.Count); });
Test("HTML and truncated calendar do not erase existing data", () =>
{
    Throws(() => parser.Parse("<html>Sign in</html>")); Throws(() => parser.Parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR"));
    Throws(() => Parse("BEGIN:VEVENT\nUID:a\nEND:VTODO"));
});
Test("Unknown zones and invalid dates protect old entries", () =>
{
    var parsed = Parse(Event("UID:a\r\nDTSTART;TZID=Unknown/Zone:20261009T235900") + "\r\n" + Event("UID:b\r\nDTSTART:20260230T235900"));
    Equal(0, parsed.Deadlines.Count); Equal(2, parsed.Warnings.Count); Check(parsed.ProtectedPrefixes.SetEquals(["blackboard:a", "blackboard:b"]));
    Equal(2, DeadlineMerger.Merge([Item(), Item("blackboard:b")], parsed, DeadlineSource.Blackboard).Count);
});
Test("Daily and weekly recurrence with exclusion and moved override", () =>
{
    var parsed = Parse(Event("UID:repeat\r\nDTSTART;TZID=Asia/Shanghai:20261005T180000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4\r\nEXDATE;TZID=Asia/Shanghai:20261007T180000") + "\r\n"
        + Event("UID:repeat\r\nRECURRENCE-ID;TZID=Asia/Shanghai:20261012T180000\r\nDTSTART;TZID=Asia/Shanghai:20261013T190000"));
    Equal(3, parsed.Deadlines.Count); Equal(D("2026-10-13T19:00:00+08:00"), parsed.Deadlines[1].DueDate);
    Check(parsed.Deadlines[1].Id.EndsWith(D("2026-10-12T18:00:00+08:00").ToUnixTimeSeconds().ToString()));
});
Test("Cancellation removes only one recurrence", () =>
{
    var parsed = Parse(Event("UID:repeat\r\nDTSTART:20261005T180000Z\r\nRRULE:FREQ=DAILY;COUNT=3") + "\r\n" + Event("UID:repeat\r\nRECURRENCE-ID:20261006T180000Z\r\nSTATUS:CANCELLED"));
    Equal(2, parsed.Deadlines.Count); Check(parsed.Deadlines.All(d => d.DueDate != D("2026-10-06T18:00:00Z")));
});
Test("Recurrence retains local hour across daylight saving", () =>
{
    var parsed = parser.Parse(Calendar(Event("UID:dst\r\nDTSTART;TZID=America/New_York:20261031T180000\r\nRRULE:FREQ=DAILY;COUNT=3")), now: D("2026-10-30T00:00:00Z"));
    Equal(3, parsed.Deadlines.Count); Equal(D("2026-10-31T22:00:00Z"), parsed.Deadlines[0].DueDate); Equal(D("2026-11-01T23:00:00Z"), parsed.Deadlines[1].DueDate);
});
Test("RDATE, EXDATE, UNTIL and duplicate IDs", () =>
{
    var parsed = Parse(Event("UID:a\r\nDTSTART:20261001T180000Z\r\nRRULE:FREQ=DAILY;UNTIL=20261003T180000Z\r\nRDATE:20261005T180000Z\r\nEXDATE:20261002T180000Z"));
    Equal(3, parsed.Deadlines.Count); Equal(D("2026-10-05T18:00:00Z"), parsed.Deadlines[^1].DueDate);
    Equal(1, Parse(Event("UID:one\r\nDTSTART:20261009T180000Z") + "\r\n" + Event("UID:one\r\nDTSTART:20261009T180000Z")).Deadlines.Count);
});
Test("Unsupported recurrence is visible and preserves old tasks", () =>
{
    foreach (var rule in new[] { "FREQ=MONTHLY;BYSETPOS=-1", "FREQ=WEEKLY;BYDAY=1MO", "FREQ=DAILY;COUNT=0", "FREQ=DAILY;INTERVAL=0", "FREQ=DAILY;WKST=SU" })
    { var parsed = Parse(Event("UID:a\r\nDTSTART:20261001T180000Z\r\nRRULE:" + rule)); Equal(1, parsed.Warnings.Count); Check(parsed.ProtectedPrefixes.Contains("blackboard:a")); }
});
Test("Completion survives regeneration of calendar UIDs", () =>
{
    var previous = Item(completed: true);
    var fresh = previous with { Id = "blackboard:new-uid", Completed = false, Notes = "Changed metadata", ReminderId = "new" };
    var result = DeadlineMerger.Merge([previous], new([fresh], [], []), DeadlineSource.Blackboard).Single();
    Check(result.Completed); Equal(previous.ReminderId, result.ReminderId);
    Equal(0, ReminderPlanner.Plans([result], settings, now).Count);
});
Test("Identity wins over fingerprint; reschedule preserves completion", () =>
{
    var prior = Item(completed: true);
    var result = DeadlineMerger.Merge([prior], new([prior with { Completed = false, DueDate = prior.DueDate.AddDays(1) }], [], []), DeadlineSource.Blackboard).Single();
    Check(result.Completed); Equal(prior.DueDate.AddDays(1), result.DueDate);
});
Test("Ambiguous identical tasks cannot steal completion", () =>
{
    var a = Item(completed: true); var b = a with { Id = "blackboard:b", Completed = false };
    var result = DeadlineMerger.Merge([a, b], new([a with { Id = "blackboard:new", Completed = false }], [], []), DeadlineSource.Blackboard);
    Check(!result.Single().Completed);
});
Test("File import preserves Blackboard ownership and completion", () =>
{
    var a = Item(completed: true); var b = a with { Id = "file:a", Source = DeadlineSource.File, Completed = false };
    var result = DeadlineMerger.Merge([a], new([b], [], []), DeadlineSource.File, false).Single();
    Equal(a.Id, result.Id); Equal(DeadlineSource.Blackboard, result.Source); Check(result.Completed);
});
Test("File import is additive; subscription removes missing items", () =>
{
    var a = Item(); var manual = a with { Id = "manual", Source = DeadlineSource.Manual };
    Equal(2, DeadlineMerger.Merge([a, manual], new([], [], []), DeadlineSource.File, false).Count);
    Equal(1, DeadlineMerger.Merge([a, manual], new([], [], []), DeadlineSource.Blackboard).Count);
});
Test("Recurring instances retain separate completion", () =>
{
    var parsed = Parse(Event("UID:repeat\r\nDTSTART:20261005T180000Z\r\nRRULE:FREQ=DAILY;COUNT=3"));
    var prior = parsed.Deadlines.Select((d, i) => d with { Completed = i == 1 }).ToList();
    var result = DeadlineMerger.Merge(prior, parsed, DeadlineSource.Blackboard);
    Equal(1, result.Count(d => d.Completed)); Check(result[1].Completed);
});
Test("URL validation upgrades webcal and rejects unsafe addresses", () =>
{
    Equal("https", FeedAddress.Validate("webcal://bb.cuhk.edu.cn/a.ics").Scheme);
    foreach (var invalid in new[] { "https://bb.cuhk.edu.cn", "http://bb.cuhk.edu.cn/a.ics", "file:///tmp/a.ics", "https://name:password@bb.cuhk.edu.cn/a.ics", "https://bb.cuhk.edu.cn/a.ics#token" }) Throws(() => FeedAddress.Validate(invalid));
});
Test("Calendar links only permit HTTPS without embedded credentials", () =>
{
    foreach (var value in new[] { "javascript:alert(1)", "file:///etc/passwd", "https://name:password@example.test/" })
        Check(Parse(Event("UID:a\r\nDTSTART:20261009T180000Z\r\nURL:" + value)).Deadlines.Single().Link is null);
});
Test("Reminder offsets deduplicate, completed/off tasks do not notify", () =>
{
    var item = Item(); var options = settings with { ReminderMinutes = [30, 30, 0] };
    Equal(2, ReminderPlanner.Plans([item], options, now).Count); Equal(0, ReminderPlanner.Plans([item with { Completed = true }], options, now).Count);
    Equal(0, ReminderPlanner.Plans([item], options with { NotificationsEnabled = false }, now).Count);
});
Test("Reminder ledger survives changed UID and catches up only five minutes", () =>
{
    var item = Item(); var options = settings with { ReminderMinutes = [0] }; var at = item.DueDate;
    var due = ReminderPlanner.Due([item], options, new Dictionary<string, DateTimeOffset>(), at.AddMinutes(-10), at.AddMinutes(1)); Equal(1, due.Count);
    Equal(0, ReminderPlanner.Due([item], options, new Dictionary<string, DateTimeOffset>(), at.AddDays(-1), at.AddMinutes(6)).Count);
    Equal(0, ReminderPlanner.Due([item with { Id = "blackboard:new" }], options, new Dictionary<string, DateTimeOffset> { [due[0].Key] = due[0].FireDate }, at.AddMinutes(-1), at.AddMinutes(1)).Count);
});
Test("Changing language preserves reminder instants and local task strings", () =>
{
    var item = Item(); var zh = ReminderPlanner.Plans([item], settings, now); var en = ReminderPlanner.Plans([item], settings with { Language = "en" }, now);
    Equal(string.Join(',', zh.Select(p => p.FireDate)), string.Join(',', en.Select(p => p.FireDate))); Equal("Shenzhen (UTC+8)", (settings with { Language = "en" }).ZoneLabel);
});
Test("Settings reject invalid zones and reminder ranges", () =>
{
    Throws(() => (settings with { TimeZoneId = "Missing/Zone" }).Validate()); Throws(() => (settings with { ReminderMinutes = [-1] }).Validate());
    Throws(() => (settings with { ReminderMinutes = [10081] }).Validate()); Throws(() => (settings with { SyncMinutes = 0 }).Validate());
});
Test("Atomic storage, backup and completion roundtrip", () =>
{
    var path = Path.Combine(Path.GetTempPath(), "shiqi-tests-" + Guid.NewGuid().ToString("N"));
    try
    {
        var storage = new LocalStorage(path); var state = new Snapshot { Deadlines = [Item(completed: true)] };
        storage.Save(state); state.Deadlines.Add(Item("blackboard:b")); storage.Save(state);
        Equal(2, storage.Load().Deadlines.Count); Check(storage.Load().Deadlines[0].Completed); Check(File.Exists(Path.Combine(path, "deadlines.backup.json")));
        Check(!File.ReadAllText(Path.Combine(path, "deadlines.json")).Contains("blackboard-calendar"));
        File.WriteAllText(Path.Combine(path, "deadlines.json"), "corrupt"); Throws(() => storage.Save(state)); Equal("corrupt", File.ReadAllText(Path.Combine(path, "deadlines.json")));
    }
    finally { if (Directory.Exists(path)) Directory.Delete(path, true); }
});
Test("Corrupt data disables persistence rather than replacing it", () =>
{
    var storage = new MemoryStorage { LoadFailure = true }; var store = new DeadlineStore(storage, new MemoryCredential(), new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK))));
    Check(!store.CanPersist); Throws(() => store.Upsert(Item())); Equal(0, storage.Saves);
});
Test("Failed saves preserve in-memory state", () =>
{
    var storage = new MemoryStorage(); var store = new DeadlineStore(storage, new MemoryCredential(), new FeedClient());
    store.Upsert(Item()); storage.SaveFailure = true; Throws(() => store.Toggle("blackboard:a")); Check(!store.State.Deadlines[0].Completed);
});
Test("JSON schema roundtrip ignores computed zone objects", () =>
{
    var state = new Snapshot { Deadlines = [Item(completed: true)] };
    var json = JsonSerializer.Serialize(state, LocalStorage.JsonOptions); Check(!json.Contains("baseUtcOffset"));
    var copy = JsonSerializer.Deserialize<Snapshot>(json, LocalStorage.JsonOptions)!; copy.Validate(); Check(copy.Deadlines[0].Completed);
    Throws(() => new Snapshot { SchemaVersion = 99 }.Validate());
});
Test("Incomplete JSON cannot silently reset task completion or erase the list", () =>
{
    Throws(() => JsonSerializer.Deserialize<Snapshot>("{}", LocalStorage.JsonOptions));
    var json = JsonSerializer.Serialize(new Snapshot { Deadlines = [Item(completed: true)] }, LocalStorage.JsonOptions);
    var document = System.Text.Json.Nodes.JsonNode.Parse(json)!;
    document["deadlines"]![0]!.AsObject().Remove("completed");
    Throws(() => JsonSerializer.Deserialize<Snapshot>(document.ToJsonString(), LocalStorage.JsonOptions));
});
AsyncTest("HTTP redirects keep private link on original HTTPS origin", async () =>
{
    foreach (var location in new[] { "https://other.test/a.ics", "http://bb.cuhk.edu.cn/a.ics", "https://bb.cuhk.edu.cn:8443/a.ics" })
    {
        var calls = 0; using var client = new FeedClient(new FakeHandler(_ => { calls++; return new(HttpStatusCode.Redirect) { Headers = { Location = new Uri(location) } }; }));
        await Fails(async () => await client.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics?fake-private-token"), settings)); Equal(1, calls);
    }
});
AsyncTest("Same-origin redirects and streamed calendar retrieval", async () =>
{
    var calls = 0; using var client = new FeedClient(new FakeHandler(_ => ++calls == 1
        ? new(HttpStatusCode.Redirect) { Headers = { Location = new Uri("/next.ics", UriKind.Relative) } }
        : new(HttpStatusCode.OK) { Content = new StringContent(Calendar("")) }));
    Equal(Calendar(""), await client.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics"), settings)); Equal(2, calls);
});
AsyncTest("HTTP errors never expose the subscription token", async () =>
{
    using var client = new FeedClient(new FakeHandler(_ => throw new HttpRequestException("https://bb.cuhk.edu.cn/a.ics?SECRET")));
    var error = await Fails(async () => await client.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics?SECRET"), settings)); Check(!error.Contains("SECRET"));
});
AsyncTest("Oversized and invalid UTF-8 responses are rejected", async () =>
{
    using var large = new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent(new byte[FeedClient.MaximumBytes + 1]) }));
    await Fails(async () => await large.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics"), settings));
    using var invalid = new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent([0xff, 0xfe]) }));
    await Fails(async () => await invalid.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics"), settings));
});
AsyncTest("Streaming size limit also covers responses without Content-Length", async () =>
{
    using var client = new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new StreamContent(new NonSeekMemory(new byte[FeedClient.MaximumBytes + 1])) }));
    await Fails(async () => await client.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics"), settings));
});
AsyncTest("Resource timeout covers a stalled response body after headers", async () =>
{
    using var client = new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new StreamContent(new BlockingStream()) }), TimeSpan.FromMilliseconds(100));
    var started = DateTimeOffset.UtcNow;
    await Fails(async () => await client.FetchAsync(new Uri("https://bb.cuhk.edu.cn/a.ics?SYNTHETIC"), settings));
    Check(DateTimeOffset.UtcNow - started < TimeSpan.FromSeconds(3));
});
AsyncTest("Sync failure retains tasks and previously saved credential", async () =>
{
    var credential = new MemoryCredential(); credential.Write("https://bb.cuhk.edu.cn/old.ics");
    var storage = new MemoryStorage { Value = new() { Deadlines = [Item(completed: true)] } };
    var store = new DeadlineStore(storage, credential, new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent("<html>Login</html>") })));
    await Fails(async () => await store.SyncAsync("https://bb.cuhk.edu.cn/new.ics")); Check(store.State.Deadlines.Single().Completed); Equal("https://bb.cuhk.edu.cn/old.ics", credential.Read());
});
AsyncTest("Save failure rolls back a newly connected credential", async () =>
{
    var credential = new MemoryCredential(); credential.Write("https://bb.cuhk.edu.cn/old.ics");
    var store = new DeadlineStore(new MemoryStorage { SaveFailure = true }, credential, new FeedClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent(Calendar("")) })));
    await Fails(async () => await store.SyncAsync("https://bb.cuhk.edu.cn/new.ics")); Equal("https://bb.cuhk.edu.cn/old.ics", credential.Read());
});
AsyncTest("Completion changed during network sync is preserved", async () =>
{
    var ready = new TaskCompletionSource<HttpResponseMessage>();
    var store = new DeadlineStore(new MemoryStorage { Value = new() { Deadlines = [Item()] } }, new MemoryCredential(), new FeedClient(new DelayedHandler(ready.Task)));
    var sync = store.SyncAsync("https://bb.cuhk.edu.cn/a.ics"); store.Toggle("blackboard:a");
    ready.SetResult(new(HttpStatusCode.OK) { Content = new StringContent(Calendar(Event("UID:a\r\nSUMMARY:Homework\r\nCATEGORIES:MAT1001\r\nDTSTART:20261009T155900Z"))) });
    await sync; Check(store.State.Deadlines.Single().Completed);
});
Test("Disconnect keeps manual and imported tasks", () =>
{
    var credential = new MemoryCredential(); credential.Write("https://bb.cuhk.edu.cn/a.ics");
    var store = new DeadlineStore(new MemoryStorage { Value = new() { Deadlines = [Item(), Item("manual") with { Source = DeadlineSource.Manual }, Item("file:b") with { Source = DeadlineSource.File }] } }, credential, new FeedClient());
    store.Disconnect(); Equal(2, store.State.Deadlines.Count); Check(credential.Read() is null);
});
Test(OperatingSystem.IsWindows() ? "Windows credential roundtrip uses only a disposable test entry" : "Credential adapter rejects non-Windows access", () =>
{
    var credential = new WindowsCredential("Shiqi.Tests." + Guid.NewGuid().ToString("N"));
    if (!OperatingSystem.IsWindows()) { Throws(() => credential.Read()); return; }
    try { Check(credential.Read() is null); credential.Write("https://example.test/calendar.ics?synthetic-only"); Equal("https://example.test/calendar.ics?synthetic-only", credential.Read()); credential.Delete(); Check(credential.Read() is null); }
    finally { credential.Delete(); }
});

var failures = 0;
foreach (var (name, run) in tests)
{
    try { await run(); Console.WriteLine("PASS: " + name); }
    catch (Exception e) { failures++; Console.Error.WriteLine("FAIL: " + name + " — " + e.Message); }
}
Console.WriteLine($"{tests.Count} tests, {failures} failures ({System.Runtime.InteropServices.RuntimeInformation.OSDescription})");
return failures == 0 ? 0 : 1;

sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) => Task.FromResult(response(request));
}
sealed class DelayedHandler(Task<HttpResponseMessage> response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) => response;
}
sealed class MemoryStorage : ISnapshotStorage
{
    public Snapshot Value = new(); public bool LoadFailure, SaveFailure; public int Saves;
    public Snapshot Load() => LoadFailure ? throw new IOException("synthetic failure") : Value;
    public void Save(Snapshot next) { if (SaveFailure) throw new IOException("synthetic failure"); Value = next; Saves++; }
}
sealed class NonSeekMemory(byte[] data) : MemoryStream(data)
{
    public override bool CanSeek => false;
}
sealed class BlockingStream : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    { await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken); return 0; }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
