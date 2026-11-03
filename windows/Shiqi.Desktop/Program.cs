using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;
using Avalonia.Styling;
using Shiqi.Core;

namespace Shiqi.Desktop;

internal static class Program
{
    internal static bool Demo;
    internal static string DemoLanguage = "zh";
    private static Mutex? instance;
    [STAThread]
    public static void Main(string[] args)
    {
        Demo = args.Contains("--demo");
        DemoLanguage = args.Contains("--english") ? "en" : "zh";
        // macOS runs are isolated previews, never another client of the Mac app's data/keychain.
        if (!OperatingSystem.IsWindows() && !Demo)
        {
            Console.Error.WriteLine("Windows app. Use --demo for an isolated UI preview on other platforms."); return;
        }
        if (!Demo)
        {
            instance = new Mutex(true, @"Local\Shiqi.Windows.Desktop", out var created);
            if (!created) return;
        }
        try { AppBuilder.Configure<App>().UsePlatformDetect().StartWithClassicDesktopLifetime(args, ShutdownMode.OnExplicitShutdown); }
        finally { instance?.Dispose(); }
    }
}

public sealed class App : Application
{
    public override void Initialize()
    {
        RequestedThemeVariant = ThemeVariant.Light;
        Styles.Add(new FluentTheme());
        Resources["SystemAccentColor"] = Avalonia.Media.Color.Parse("#750F6D");
    }
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var memory = new MemorySnapshot();
            var dataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Shiqi");
            var store = new DeadlineStore(Program.Demo ? memory : new LocalStorage(dataPath),
                Program.Demo ? new MemoryCredential() : new WindowsCredential(), new FeedClient());
            desktop.MainWindow = new MainWindow(store, desktop, dataPath);
        }
        base.OnFrameworkInitializationCompleted();
    }
}

internal sealed class MemorySnapshot : ISnapshotStorage
{
    private Snapshot value = new()
    {
        Settings = new() { Language = Program.DemoLanguage },
        Deadlines =
        [
            new() { Title = "Probability · Problem set 03", Course = "MAT2040 · Probability and Statistics", DueDate = DateTimeOffset.UtcNow.AddHours(3), Source = DeadlineSource.Blackboard },
            new() { Title = "Research proposal · Individual assignment", Course = "ENG2001 · Academic Writing", DueDate = DateTimeOffset.UtcNow.AddDays(2), Source = DeadlineSource.File, Notes = "Demo data. Check the course page for submission instructions." },
            new() { Title = "数据结构与算法：小组项目阶段报告", Course = "CSC3100 · Data Structures", DueDate = DateTimeOffset.UtcNow.AddDays(4), Source = DeadlineSource.Blackboard },
            new() { Title = "Presentation outline", Course = "ENG1002 · English", DueDate = DateTimeOffset.UtcNow.AddDays(5), HasTime = false },
            new() { Title = "Linear algebra worksheet", Course = "MAT1001", DueDate = DateTimeOffset.UtcNow.AddDays(-1), Source = DeadlineSource.Blackboard },
            new() { Title = "实验报告 / Lab report", Course = "PHY1001", DueDate = DateTimeOffset.UtcNow.AddDays(-2), Completed = true }
        ]
    };
    public Snapshot Load() => value;
    public void Save(Snapshot next) => value = next;
}
