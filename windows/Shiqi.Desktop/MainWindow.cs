using System.Diagnostics;
using System.Globalization;
using System.Text;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Shiqi.Core;

namespace Shiqi.Desktop;

internal sealed class MainWindow : Window
{
    private readonly DeadlineStore store;
    private readonly IClassicDesktopStyleApplicationLifetime desktop;
    private readonly string dataPath;
    private readonly Avalonia.Media.Imaging.Bitmap brandImage;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(15) };
    private readonly HashSet<string> sessionDelivered = [];
    private WindowsTray? tray;
    private string filter = "upcoming", search = "", message = "";
    private bool syncing, ticking, quitting;
    private DateTimeOffset lastAttempt = DateTimeOffset.MinValue, lastReminderCheck = DateTimeOffset.UtcNow.AddSeconds(-30);
    private StackPanel list = new();
    private TextBlock status = new();
    private Settings Settings => store.State.Settings;
    private string T(string zh, string en) => Settings.Text(zh, en);

    public MainWindow(DeadlineStore store, IClassicDesktopStyleApplicationLifetime desktop, string dataPath)
    {
        this.store = store; this.desktop = desktop; this.dataPath = dataPath;
        Width = 1120; Height = 780; MinWidth = 860; MinHeight = 620;
        Title = "拾期 · Shiqi"; Background = Brush.Parse("#F7F4F8");
        FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI, PingFang SC");
        using var icon = AssetLoader.Open(new Uri("avares://Shiqi/Assets/Shiqi.ico")); Icon = new WindowIcon(icon);
        using var brandStream = AssetLoader.Open(new Uri("avares://Shiqi/Assets/Shiqi.png"));
        brandImage = new Avalonia.Media.Imaging.Bitmap(brandStream);
        message = store.LoadError ?? "";
        store.Changed += () => Dispatcher.UIThread.Post(Render);
        Closing += (_, e) =>
        {
            if (tray is not null && !quitting) { e.Cancel = true; Hide(); }
            else if (!quitting) Quit();
        };
        Opened += async (_, _) =>
        {
            if (!Program.Demo && OperatingSystem.IsWindows())
            {
                try { tray = new WindowsTray(ShowMain, Quit); }
                catch { message = T("系统托盘启动失败。请保持窗口打开以接收提醒。", "The system tray could not start. Keep this window open for reminders."); Render(); }
                if (Environment.GetCommandLineArgs().Contains("--background") && tray is not null) Hide();
            }
            timer.Tick += async (_, _) => await Tick(); timer.Start();
            await Guard(async () => { if (Connected()) await Sync(); });
        };
        desktop.Exit += (_, _) => { timer.Stop(); tray?.Dispose(); };
        Render();
    }
    private bool Connected()
    {
        try { return !Program.Demo && store.IsConnected; }
        catch { message = T("无法读取保存的日历链接。请检查 Windows 凭据管理器。", "Could not read the saved calendar link. Check Windows Credential Manager."); return false; }
    }
    private void ShowMain() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Quit() { if (quitting) return; quitting = true; timer.Stop(); tray?.Dispose(); desktop.Shutdown(); }
    private async Task Guard(Func<Task> operation)
    {
        try { await operation(); }
        catch (Exception e) { message = e is IOException or FormatException or InvalidDataException ? e.Message
                : T("操作未完成，原有数据已保留。请稍后重试。", "The operation could not finish. Existing data is kept. Try again later."); }
        Render();
    }
    private async Task Tick()
    {
        if (ticking || quitting) return; ticking = true;
        try
        {
            var now = DateTimeOffset.UtcNow;
            if (!Program.Demo && store.CanPersist && tray is not null)
            {
                var due = ReminderPlanner.Due(store.State.Deadlines, Settings, store.State.DeliveredReminders, lastReminderCheck, now)
                    .Where(p => !sessionDelivered.Contains(p.Key)).ToList();
                var sent = new List<ReminderPlan>();
                // Native Windows notifications are serialised; do not replace several balloons in the same tick.
                if (due.FirstOrDefault() is { } plan)
                {
                    var body = string.Join("\n", new[] { Settings.Format(plan.Deadline) + " · " + Settings.ZoneLabel, plan.Deadline.Title, plan.Deadline.Course }.Where(s => s.Length > 0));
                    if (tray.Notify("拾期 · " + plan.Subtitle, body)) { sessionDelivered.Add(plan.Key); sent.Add(plan); }
                    else message = T("系统通知发送失败，请使用设置中的测试通知检查。", "Windows notification failed. Try the test notification in Settings.");
                }
                // Keep the five-minute catch-up window while a batch is still pending.
                if (due.Count == 0 || due.Count == 1 && sent.Count == 1) lastReminderCheck = now;
                if (sent.Count > 0) store.RecordDelivered(sent, now);
            }
            RefreshList();
            if (!Program.Demo && Connected() && !syncing && now - lastAttempt >= TimeSpan.FromMinutes(Settings.SyncMinutes)) await Sync();
        }
        catch (Exception e) { message = e is IOException ? e.Message : T("同步或提醒暂时失败，请查看设置。", "Sync or reminders could not finish. Check Settings."); Render(); }
        finally { ticking = false; }
    }
    private async Task Sync(string? link = null)
    {
        if (Program.Demo || syncing) return;
        syncing = true; lastAttempt = DateTimeOffset.UtcNow; Render();
        try
        {
            if (await store.SyncAsync(link)) message = T($"已同步 {store.State.Deadlines.Count(d => d.Source == DeadlineSource.Blackboard)} 个日历事项。", $"Synced {store.State.Deadlines.Count(d => d.Source == DeadlineSource.Blackboard)} calendar items.");
        }
        finally { syncing = false; Render(); }
    }

    private void Render()
    {
        var connected = Connected();
        var sidebar = new Grid { RowDefinitions = RowDefinitions.Parse("Auto,Auto,*,Auto"), Margin = new Thickness(22, 25) };
        var brand = Ui.Row("Auto,*", new Image { Source = brandImage, Width = 42, Height = 42 },
            Ui.Column(Ui.Text("拾期", 27, Ui.Purple, true), Ui.Text("SHIQI", 10, Ui.Muted, true)));
        sidebar.Children.Add(brand);
        var filters = new StackPanel { Spacing = 9, Margin = new Thickness(0, 34, 0, 0) };
        foreach (var item in new[] { ("upcoming", T("即将截止", "Upcoming")), ("week", T("未来 7 天", "Next 7 days")), ("overdue", T("已逾期", "Overdue")), ("completed", T("已完成", "Completed")) })
        {
            var key = item.Item1;
            var button = Ui.Button(item.Item2, () => { filter = key; Render(); });
            button.HorizontalAlignment = HorizontalAlignment.Stretch; button.HorizontalContentAlignment = HorizontalAlignment.Left;
            if (key == filter) { button.Background = Brush.Parse("#EEDCEF"); button.BorderBrush = Ui.Purple; button.BorderThickness = new Thickness(1); }
            filters.Children.Add(button);
        }
        Grid.SetRow(filters, 1); sidebar.Children.Add(filters);
        var foot = Ui.Column(Ui.Text(Program.Demo ? T("演示模式", "Demo mode") : connected ? T("日历已连接", "Calendar connected") : T("日历未连接", "Not connected"), 12, Ui.Muted),
            Ui.Button(T("管理连接", "Connection"), () => _ = Guard(Connect)),
            Ui.Button(T("设置", "Settings"), () => _ = Guard(OpenSettings)),
            Ui.Text("1.2.0 · MIT License", 10, Ui.Muted));
        Grid.SetRow(foot, 3); sidebar.Children.Add(foot);
        var sideBorder = new Border { Background = Brushes.White, BorderBrush = Brush.Parse("#E8E0EB"), BorderThickness = new Thickness(0, 0, 1, 0), Child = sidebar };

        var content = new Grid { RowDefinitions = RowDefinitions.Parse("Auto,Auto,Auto,Auto,*,Auto"), RowSpacing = 17, Margin = new Thickness(28, 25) };
        var hero = Ui.Column(Ui.Text(T("课程 DDL 与提醒", "Course deadlines and reminders"), 26, Ui.Purple, true),
            Ui.Text(T("给龙大学子的免费开源软件", "Free, open-source software for LGU students"), 13, Ui.Muted),
            Ui.Text(Settings.ZoneLabel + (Program.Demo ? T(" · 以下为示例任务，不是真实课程数据", " · Sample tasks, not real course data") : ""), 11, Ui.Muted));
        content.Children.Add(hero);
        var now = DateTimeOffset.UtcNow;
        Control Metric(string label, int value, IBrush color) => Ui.Card(Ui.Column(Ui.Text(value.ToString(CultureInfo.InvariantCulture), 25, color, true), Ui.Text(label, 12, Ui.Muted)), 14);
        var active = store.State.Deadlines.Where(d => !d.Completed).ToList();
        var metrics = Ui.Row("*,*,*", Metric(T("待办任务", "Pending"), active.Count, Ui.Purple),
            Metric(T("24 小时内", "Within 24 hours"), active.Count(d => d.HasTime && d.DueDate >= now && d.DueDate <= now.AddDays(1)), Brush.Parse("#865C00")),
            Metric(T("已逾期", "Overdue"), active.Count(d => d.IsOverdue(now, Settings.Zone)), Brush.Parse("#A33843")));
        Grid.SetRow(metrics, 1); content.Children.Add(metrics);
        var query = Ui.Input(search, T("搜索课程或任务", "Search courses or tasks"));
        AutomationProperties.SetAutomationId(query, "dashboard.search");
        query.TextChanged += (_, _) => { search = query.Text ?? ""; RefreshList(); };
        var add = Ui.Button(T("添加 DDL", "Add deadline"), () => _ = Guard(() => Edit(null)), true);
        var import = Ui.Button(T("导入 ICS", "Import ICS"), () => _ = Guard(Import));
        var sync = Ui.Button(syncing ? T("同步中…", "Syncing…") : T("同步", "Sync"), () => _ = Guard(() => connected ? Sync() : Connect()));
        sync.IsEnabled = !syncing && !Program.Demo;
        var toolbar = Ui.Row("*,Auto,Auto,Auto", query, add, import, sync);
        Grid.SetRow(toolbar, 2); content.Children.Add(toolbar);
        var names = new Dictionary<string, string> { ["upcoming"] = T("即将截止", "Upcoming"), ["week"] = T("未来 7 天", "Next 7 days"), ["overdue"] = T("已逾期", "Overdue"), ["completed"] = T("已完成", "Completed") };
        var heading = Ui.Text(names[filter], 16, Ui.Ink, true); Grid.SetRow(heading, 3); content.Children.Add(heading);
        list = new StackPanel { Spacing = 10 };
        var scroll = new ScrollViewer { Content = list, HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled };
        Grid.SetRow(scroll, 4); content.Children.Add(scroll);
        status = Ui.Text("", 11, Ui.Muted); Grid.SetRow(status, 5); content.Children.Add(status);
        Content = Ui.Row("210,*", sideBorder, content);
        RefreshList();
    }

    private void RefreshList()
    {
        var now = DateTimeOffset.UtcNow;
        var items = store.State.Deadlines.Where(d => filter switch
        {
            "completed" => d.Completed,
            "overdue" => !d.Completed && d.IsOverdue(now, Settings.Zone),
            "week" => !d.Completed && !d.IsOverdue(now, Settings.Zone) && d.DueDate <= now.AddDays(7),
            _ => !d.Completed && !d.IsOverdue(now, Settings.Zone)
        }).Where(d => string.IsNullOrWhiteSpace(search) || (d.Title + " " + d.Course + " " + d.Notes).Contains(search, StringComparison.CurrentCultureIgnoreCase));
        items = filter == "completed" ? items.OrderByDescending(d => d.DueDate) : items.OrderBy(d => d.DueDate);
        list.Children.Clear();
        DateTime? previousDay = null;
        foreach (var item in items)
        {
            var localDay = TimeZoneInfo.ConvertTime(item.DueDate, Settings.Zone).Date;
            if (previousDay != localDay)
            {
                var label = localDay.ToString(Settings.Language == "en" ? "ddd, MMM d · yyyy" : "yyyy 年 M 月 d 日 dddd",
                    CultureInfo.GetCultureInfo(Settings.Language == "en" ? "en-US" : "zh-CN"));
                list.Children.Add(Ui.Text(label, 12, Ui.Muted, true)); previousDay = localDay;
            }
            var toggle = new CheckBox { IsChecked = item.Completed, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 5, 2, 0) };
            AutomationProperties.SetName(toggle, T("切换完成状态：", "Toggle completion: ") + item.Title);
            toggle.IsEnabled = store.CanPersist;
            toggle.IsCheckedChanged += (_, _) => _ = Guard(() => { store.Toggle(item.Id); return Task.CompletedTask; });
            var title = Ui.Text(item.Title, 15, Ui.Ink, true); title.MaxLines = 2;
            var course = Ui.Text(string.IsNullOrEmpty(item.Course) ? T("手动任务 / 日历事项", "Manual task / calendar item") : item.Course, 12, Ui.Muted); course.MaxLines = 2;
            var date = Ui.Text(Settings.Format(item), 12, item.IsOverdue(now, Settings.Zone) && !item.Completed ? Brush.Parse("#A33843") : Ui.Purple, true);
            var details = Ui.Column(title, course, date); details.Spacing = 5;
            if (!item.Completed && item.HasTime && item.DueDate > now)
            {
                var remaining = item.DueDate - now;
                var countdown = remaining.TotalDays >= 1 ? T($"剩余 {(int)remaining.TotalDays} 天 {remaining.Hours} 小时", $"{(int)remaining.TotalDays}d {remaining.Hours}h left")
                    : remaining.TotalHours >= 1 ? T($"剩余 {(int)remaining.TotalHours} 小时 {remaining.Minutes} 分钟", $"{(int)remaining.TotalHours}h {remaining.Minutes}m left")
                    : T($"剩余 {Math.Max(1, (int)remaining.TotalMinutes)} 分钟", $"{Math.Max(1, (int)remaining.TotalMinutes)}m left");
                details.Children.Add(Ui.Text(countdown, 11, Ui.Muted));
            }
            var actions = Ui.Column(Ui.Button(T("详情", "Details"), () => _ = Guard(() => Details(item))),
                Ui.Button(T("删除", "Delete"), () => _ = Guard(async () =>
                {
                    if (await Ui.Confirm(this, T("删除任务？", "Delete deadline?"), item.Title, T("删除", "Delete"), T("取消", "Cancel"))) store.Delete(item.Id);
                })));
            actions.Spacing = 6;
            list.Children.Add(Ui.Card(Ui.Row("Auto,*,Auto", toggle, details, actions), 16));
        }
        if (list.Children.Count == 0) list.Children.Add(Ui.Card(Ui.Column(Ui.Text(T("这里还没有任务", "No tasks here"), 19, Ui.Purple, true),
            Ui.Text(T("连接 Blackboard、导入 ICS，或手动添加截止日期。", "Connect Blackboard, import ICS, or add a deadline manually."), 13, Ui.Muted)), 28));
        var lastSync = store.State.LastSync is { } dateValue ? TimeZoneInfo.ConvertTime(dateValue, Settings.Zone).ToString("MM-dd HH:mm") : T("尚未同步", "Not synced yet");
        var warning = store.State.Warnings.Count == 0 ? "" : T($" · {store.State.Warnings.Count} 个事项需要检查（见设置）", $" · {store.State.Warnings.Count} items need review (Settings)");
        status.Text = (!string.IsNullOrWhiteSpace(message) ? message + "\n" : "") + T("最后同步：", "Last sync: ") + lastSync + warning
            + "\n" + T("关闭窗口后继续在系统托盘运行；退出、关机或睡眠期间无法准时提醒。", "Closing keeps Shiqi in the system tray. Quit, shutdown or sleep can prevent timely reminders.");
    }

    private async Task Connect()
    {
        var dialog = Ui.Dialog(T("连接 Blackboard 日历", "Connect Blackboard calendar"));
        dialog.Height = 590;
        var link = Ui.Input("", T("粘贴完整 HTTPS / webcal 共享链接", "Paste the full HTTPS / webcal sharing link")); link.PasswordChar = '●';
        var error = Ui.Text("", 12, Brush.Parse("#A33843"));
        var connect = Ui.Button(T("连接并同步", "Connect & sync"), () => { }, true);
        connect.IsEnabled = !Program.Demo && store.CanPersist && !syncing;
        connect.Click += async (_, _) =>
        {
            connect.IsEnabled = false;
            try { await Sync(link.Text ?? ""); dialog.Close(); }
            catch (Exception e) { error.Text = e is IOException or FormatException ? e.Message : T("连接失败，请重试。", "Connection failed. Try again."); }
            finally { connect.IsEnabled = true; }
        };
        var disconnect = Ui.Button(T("断开连接", "Disconnect"), () => _ = Guard(async () =>
        {
            if (await Ui.Confirm(dialog, T("断开日历连接？", "Disconnect calendar?"), T("将移除订阅和 Blackboard 同步任务，保留手动与文件导入任务。", "Removes the subscription and synced Blackboard tasks. Keeps manual and file-imported tasks."), T("断开", "Disconnect"), T("取消", "Cancel")))
            { store.Disconnect(); dialog.Close(); }
        }));
        disconnect.IsEnabled = Connected() && !syncing;
        dialog.Content = new ScrollViewer { Content = new StackPanel { Margin = new Thickness(26), Spacing = 18, Children =
        {
            Ui.Text(T("连接 Blackboard 日历", "Connect Blackboard calendar"), 23, Ui.Purple, true),
            Ui.Text(T("1. 在浏览器登录学校 Blackboard，打开全局 Calendar。\n2. 选择 Get External Calendar Link / Share Calendar。\n3. 复制完整个人链接并粘贴到下方。", "1. Sign in to Blackboard in your browser and open Calendar.\n2. Choose Get External Calendar Link / Share Calendar.\n3. Copy your full personal sharing link and paste it below.")),
            Ui.Button(T("打开 Blackboard", "Open Blackboard"), () => OpenLink("https://bb.cuhk.edu.cn/")),
            link, error, connect, disconnect,
            Ui.Text(T("共享链接保存在当前 Windows 用户的凭据管理器中。拾期不读取学校密码，也不操作作业提交。请勿公开共享链接。", "The sharing link is stored in your Windows Credential Manager. Shiqi does not read your school password or submit work. Keep this link private."), 12, Ui.Muted)
        } } };
        await dialog.ShowDialog(this);
    }

    private async Task Import()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { Title = T("导入日历", "Import calendar"), AllowMultiple = false,
            FileTypeFilter = [new FilePickerFileType("iCalendar") { Patterns = ["*.ics"], MimeTypes = ["text/calendar"] }] });
        if (files.Count == 0) return;
        await using var stream = await files[0].OpenReadAsync();
        using var bytes = new MemoryStream(); var buffer = new byte[16384]; int count;
        while ((count = await stream.ReadAsync(buffer)) > 0)
        {
            if (bytes.Length + count > FeedClient.MaximumBytes) throw new IOException(T("日历超过 5 MB。", "The calendar exceeds 5 MB."));
            bytes.Write(buffer, 0, count);
        }
        store.Import(new UTF8Encoding(false, true).GetString(bytes.ToArray()));
        message = T("日历已导入。文件导入不会自动更新。", "Calendar imported. File imports do not update automatically.");
    }

    private async Task Details(Deadline item)
    {
        var dialog = Ui.Dialog(T("任务详情", "Deadline details"));
        var panel = new StackPanel { Margin = new Thickness(26), Spacing = 16 };
        panel.Children.Add(Ui.Text(item.Title, 24, Ui.Purple, true));
        panel.Children.Add(Ui.Text(item.Course, 16));
        panel.Children.Add(Ui.Card(Ui.Column(Ui.Text(Settings.Format(item), 20, Ui.Purple, true), Ui.Text(Settings.ZoneLabel, 12, Ui.Muted))));
        panel.Children.Add(Ui.Text(item.Notes, 14));
        panel.Children.Add(Ui.Text(T("标记完成仅影响拾期，不代表 Blackboard 已提交或评分。", "Completion only affects Shiqi. It does not mean submitted or graded in Blackboard."), 12, Ui.Muted));
        if (Uri.TryCreate(item.Link, UriKind.Absolute, out var uri) && uri.Scheme == "https")
            panel.Children.Add(Ui.Button(T("在浏览器查看原始页面", "View original in browser"), () => OpenLink(uri.AbsoluteUri)));
        if (item.Source == DeadlineSource.Manual)
            panel.Children.Add(Ui.Button(T("编辑任务", "Edit deadline"), () => _ = Guard(async () => { dialog.Close(); await Edit(item); }), true));
        panel.Children.Add(Ui.Button(T("关闭", "Close"), () => dialog.Close()));
        dialog.Content = new ScrollViewer { Content = panel }; await dialog.ShowDialog(this);
    }

    private async Task Edit(Deadline? item)
    {
        var dialog = Ui.Dialog(item is null ? T("添加 DDL", "Add deadline") : T("编辑任务", "Edit deadline"));
        var local = TimeZoneInfo.ConvertTime(item?.DueDate ?? DateTimeOffset.UtcNow.AddDays(1), Settings.Zone);
        var title = Ui.Input(item?.Title ?? ""); var course = Ui.Input(item?.Course ?? "");
        AutomationProperties.SetAutomationId(title, "editor.title");
        var date = Ui.Input(local.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
        var time = Ui.Input(local.ToString("HH:mm", CultureInfo.InvariantCulture));
        var hasTime = new CheckBox { Content = T("指定具体截止时间", "Specify an exact due time"), IsChecked = item?.HasTime ?? true };
        time.IsEnabled = hasTime.IsChecked == true; hasTime.IsCheckedChanged += (_, _) => time.IsEnabled = hasTime.IsChecked == true;
        var notes = Ui.Input(item?.Notes ?? ""); notes.AcceptsReturn = true; notes.TextWrapping = TextWrapping.Wrap; notes.MinHeight = 90;
        var error = Ui.Text("", 12, Brush.Parse("#A33843"));
        var save = Ui.Button(T("保存", "Save"), () =>
        {
            try
            {
                if (string.IsNullOrWhiteSpace(title.Text)) throw new FormatException(T("请输入任务名称。", "Enter a task title."));
                var raw = (date.Text ?? "") + " " + (hasTime.IsChecked == true ? time.Text : "00:00");
                if (!DateTime.TryParseExact(raw, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
                    throw new FormatException(T("请使用 yyyy-MM-dd 日期和 HH:mm 时间。", "Use yyyy-MM-dd for the date and HH:mm for the time."));
                store.Upsert((item ?? new Deadline()) with { Title = title.Text.Trim(), Course = (course.Text ?? "").Trim(), Notes = notes.Text ?? "",
                    DueDate = Zones.LocalInstant(parsed, Settings.Zone), HasTime = hasTime.IsChecked == true }); dialog.Close();
            }
            catch (Exception e) { error.Text = e is IOException or FormatException ? e.Message : T("无法保存任务。", "Could not save the deadline."); }
        }, true);
        dialog.Content = new ScrollViewer { Content = new StackPanel { Margin = new Thickness(26), Spacing = 16, Children =
        {
            Ui.Text(dialog.Title ?? "", 23, Ui.Purple, true), Ui.Field(T("任务名称", "Task title"), title), Ui.Field(T("课程（可选）", "Course (optional)"), course),
            Ui.Row("*,*", Ui.Field(T("日期", "Date"), date), Ui.Field(T("时间", "Time"), time)), hasTime, Ui.Text(Settings.ZoneLabel, 12, Ui.Muted),
            Ui.Field(T("备注", "Notes"), notes), error, Ui.Row("*,*", Ui.Button(T("取消", "Cancel"), () => dialog.Close()), save)
        } } };
        await dialog.ShowDialog(this);
    }

    private async Task OpenSettings()
    {
        var dialog = Ui.Dialog(T("设置", "Settings"), 650);
        var language = new ComboBox { ItemsSource = new[] { "简体中文", "English" }, SelectedIndex = Settings.Language == "en" ? 1 : 0, HorizontalAlignment = HorizontalAlignment.Stretch };
        var zones = new[] { "Asia/Shanghai", "Asia/Hong_Kong", TimeZoneInfo.Local.Id }.Distinct().ToArray();
        var zoneNames = zones.Select(z => z == "Asia/Shanghai" ? "深圳 / Shenzhen (UTC+8)" : z == "Asia/Hong_Kong" ? "香港 / Hong Kong (UTC+8)" : z).ToArray();
        var zone = new ComboBox { ItemsSource = zoneNames, SelectedIndex = Math.Max(0, Array.IndexOf(zones, Settings.TimeZoneId)), HorizontalAlignment = HorizontalAlignment.Stretch };
        var intervals = new[] { 5, 15, 30, 60 };
        var interval = new ComboBox { ItemsSource = intervals.Select(i => T($"每 {i} 分钟", $"Every {i} minutes")).ToArray(), SelectedIndex = Array.IndexOf(intervals, Settings.SyncMinutes), HorizontalAlignment = HorizontalAlignment.Stretch };
        var offsets = Ui.Input(string.Join(", ", Settings.ReminderMinutes));
        var notifications = new CheckBox { Content = T("发送 Windows 系统通知", "Send Windows notifications"), IsChecked = Settings.NotificationsEnabled };
        var startup = new CheckBox { Content = T("登录 Windows 时启动拾期", "Start Shiqi when I sign in to Windows"), IsChecked = !Program.Demo && Startup.Enabled, IsEnabled = !Program.Demo && OperatingSystem.IsWindows() };
        var error = Ui.Text("", 12, Brush.Parse("#A33843"));
        var test = Ui.Button(T("发送测试通知", "Send test notification"), () =>
        {
            if (tray?.Notify(T("拾期提醒测试", "Shiqi reminder test"), T("系统通知已发送，请检查屏幕右下角和通知设置。", "Test notification sent. Check the bottom-right corner and notification settings.")) == true)
                error.Text = T("已请求系统显示通知。若未收到，请检查专注/勿扰和系统通知设置。", "Windows was asked to show a notification. If missing, check Do Not Disturb and system notification settings.");
            else error.Text = T("当前环境不能发送 Windows 系统通知。", "This environment cannot send Windows notifications.");
        });
        test.IsEnabled = !Program.Demo && tray is not null;
        var save = Ui.Button(T("保存设置", "Save settings"), () =>
        {
            try
            {
                var parsed = (offsets.Text ?? "").Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).Select(int.Parse).Distinct().ToArray();
                var next = Settings with { Language = language.SelectedIndex == 1 ? "en" : "zh", TimeZoneId = zones[zone.SelectedIndex],
                    SyncMinutes = intervals[interval.SelectedIndex], NotificationsEnabled = notifications.IsChecked == true, ReminderMinutes = parsed };
                next.Validate(); var oldStartup = !Program.Demo && Startup.Enabled;
                var startupChanged = !Program.Demo && (startup.IsChecked == true) != oldStartup;
                if (startupChanged) Startup.Set(startup.IsChecked == true);
                try { store.UpdateSettings(next); }
                catch { if (startupChanged) Startup.Set(oldStartup); throw; }
                dialog.Close(); Render();
            }
            catch (Exception e) { error.Text = e is IOException ? e.Message : T("请使用 0–10080 的分钟数，以逗号分隔，最多 12 项。", "Enter comma-separated minutes from 0 to 10080, up to 12 values."); }
        }, true);
        var panel = new StackPanel { Margin = new Thickness(26), Spacing = 16, Children =
        {
            Ui.Text(T("提醒与偏好设置", "Reminders and preferences"), 23, Ui.Purple, true),
            Ui.Field("语言 / Language", language), Ui.Field(T("显示与默认解析时区", "Display & default parsing time zone"), zone),
            Ui.Field(T("自动同步", "Auto-sync"), interval), notifications,
            Ui.Field(T("提前提醒（分钟，0 表示截止时）", "Remind before due time (minutes; 0 means at due time)"), offsets), test, startup,
            Ui.Text(T("保持拾期在系统托盘运行以接收提醒。退出、关机或睡眠时无法准时提醒；恢复后仅补发最近 5 分钟内的提醒。仅日期事项在前一天及当天 09:00 提醒。", "Keep Shiqi running in the system tray for reminders. Quit, shutdown or sleep can prevent timely alerts; only the last 5 minutes are caught up on resume. Date-only items remind at 09:00 on the previous day and due day."), 12, Ui.Muted),
            Ui.Text(T("Windows 版不支持 Apple 提醒事项同步。", "Apple Reminders sync is unavailable on Windows."), 12, Ui.Muted),
            Ui.Text(T("LGU 是学生昵称「龙岗大学 / Longgang University」。个人独立开发，非学校或 Blackboard 官方产品。", "LGU means Longgang University, a student nickname. Independently developed; not an official university or Blackboard product."), 12, Ui.Muted),
            Ui.Text(Program.Demo ? T("演示模式：数据仅保存在内存。", "Demo mode: data stays in memory.") : T("本地数据：", "Local data: ") + dataPath, 11, Ui.Muted),
            error
        } };
        if (store.State.Warnings.Count > 0) panel.Children.Add(Ui.Card(Ui.Column(Ui.Text(T("导入提示", "Import warnings"), 15, Ui.Purple, true), Ui.Text(string.Join("\n", store.State.Warnings), 12)), 14));
        panel.Children.Add(Ui.Row("*,*", Ui.Button(T("取消", "Cancel"), () => dialog.Close()), save));
        dialog.Content = new ScrollViewer { Content = panel }; await dialog.ShowDialog(this);
    }
    private static void OpenLink(string value)
    {
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.UserInfo.Length == 0)
            Process.Start(new ProcessStartInfo { FileName = uri.AbsoluteUri, UseShellExecute = true });
    }
}
