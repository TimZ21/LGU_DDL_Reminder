using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Headless;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Shiqi.Core;
using Shiqi.Desktop;

// Tests run in a simulated windowing backend, never on the user's desktop or real app data.
Shiqi.Desktop.Program.Demo = true;
AppBuilder.Configure<App>().UseSkia().WithInterFont().UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }).SetupWithoutStarting();
var output = args.Length > 0 ? Path.GetFullPath(args[0]) : Path.Combine(Path.GetTempPath(), "shiqi-ui-preview");
Directory.CreateDirectory(output);
var count = 0;
Avalonia.Media.Imaging.WriteableBitmap Frame(Window window)
{
    for (var i = 0; i < 30; i++)
    {
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        if (window.CaptureRenderedFrame() is { } frame) return frame;
        Thread.Sleep(10);
    }
    throw new Exception("No frame rendered for " + window.Title);
}
foreach (var language in new[] { "en", "zh" })
{
    Shiqi.Desktop.Program.DemoLanguage = language;
    var lifetime = new ClassicDesktopStyleApplicationLifetime();
    var store = new DeadlineStore(new MemorySnapshot(), new MemoryCredential(), new FeedClient());
    var window = new MainWindow(store, lifetime, "demo-only");
    lifetime.MainWindow = window;
    window.Show(); Dispatcher.UIThread.RunJobs();
    foreach (var width in new[] { 1120, 860 })
    {
        window.Width = width; window.Height = width == 860 ? 620 : 780; Dispatcher.UIThread.RunJobs();
        using var frame = Frame(window);
        frame.Save(Path.Combine(output, $"dashboard-{language}-{width}.png"));
        var search = window.GetVisualDescendants().OfType<TextBox>().Single(c => AutomationProperties.GetAutomationId(c) == "dashboard.search");
        if (search.Bounds.Width < 90) throw new Exception("Search control is squeezed at " + width);
        var buttons = window.GetVisualDescendants().OfType<Button>().Where(b => b.IsEffectivelyVisible && b.Content is string).ToArray();
        foreach (var button in buttons)
        {
            if (button.Bounds.Width <= 0 || button.Bounds.Height <= 0) throw new Exception("A visible button has no usable bounds: " + button.Content);
            var point = button.TranslatePoint(new Point(0, 0), window);
            if (point is { } p && (p.X < -1 || p.X + button.Bounds.Width > window.ClientSize.Width + 1))
                throw new Exception("Button outside horizontal window bounds: " + button.Content);
        }
        count++; Console.WriteLine($"PASS: dashboard {language}, width {width}");
    }
    var query = window.GetVisualDescendants().OfType<TextBox>().Single(c => AutomationProperties.GetAutomationId(c) == "dashboard.search");
    query.Text = "MAT2040"; Dispatcher.UIThread.RunJobs();
    if (window.GetVisualDescendants().OfType<CheckBox>().Count() != 1) throw new Exception("Course search did not filter the task list");
    query.Text = ""; Dispatcher.UIThread.RunJobs(); count++; Console.WriteLine("PASS: course search " + language);
    var checkbox = window.GetVisualDescendants().OfType<CheckBox>().First();
    var before = store.State.Deadlines.Count(d => d.Completed);
    checkbox.IsChecked = true; Dispatcher.UIThread.RunJobs();
    if (store.State.Deadlines.Count(d => d.Completed) != before + 1) throw new Exception("Completion UI did not update stored state");
    count++; Console.WriteLine("PASS: completion control " + language);
    var add = window.GetVisualDescendants().OfType<Button>().Single(b => b.Content?.ToString() == (language == "en" ? "Add deadline" : "添加 DDL"));
    add.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Dispatcher.UIThread.RunJobs();
    var editor = window.OwnedWindows.Single();
    editor.GetVisualDescendants().OfType<TextBox>().Single(c => AutomationProperties.GetAutomationId(c) == "editor.title").Text = "UI verification task / 测试任务";
    using (var frame = Frame(editor)) frame.Save(Path.Combine(output, $"editor-{language}.png"));
    editor.GetVisualDescendants().OfType<Button>().Single(b => b.Content?.ToString() == (language == "en" ? "Save" : "保存")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Dispatcher.UIThread.RunJobs();
    if (!store.State.Deadlines.Any(d => d.Title == "UI verification task / 测试任务" && d.Source == DeadlineSource.Manual)) throw new Exception("Manual task editor did not save");
    count++; Console.WriteLine("PASS: manual task editor " + language);
    var settingsButton = window.GetVisualDescendants().OfType<Button>().Single(b => b.Content?.ToString() == (language == "en" ? "Settings" : "设置"));
    settingsButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Dispatcher.UIThread.RunJobs();
    var dialog = window.OwnedWindows.Single();
    using (var frame = Frame(dialog)) frame.Save(Path.Combine(output, $"settings-{language}.png"));
    if (!dialog.GetVisualDescendants().OfType<ComboBox>().Any()) throw new Exception("Missing language/timezone settings");
    dialog.GetVisualDescendants().OfType<ComboBox>().First().SelectedIndex = language == "en" ? 0 : 1;
    dialog.GetVisualDescendants().OfType<Button>().Single(b => b.Content?.ToString() == (language == "en" ? "Save settings" : "保存设置")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Dispatcher.UIThread.RunJobs();
    if (store.State.Settings.Language != (language == "en" ? "zh" : "en")) throw new Exception("Language setting did not save");
    count++; Console.WriteLine("PASS: settings dialog and language switch " + language);
    // Detach the preview's close handler from the lifetime by exiting after all checks below.
    window.Hide();
}
Console.WriteLine($"{count} UI checks passed. Headless renderings: {output}");
return 0;
