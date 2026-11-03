using System.Runtime.InteropServices;

namespace Shiqi.Desktop;

// Native notification-area icon and reminders. No PowerShell, external process, WebView, or admin privilege.
internal sealed class WindowsTray : IDisposable
{
    private const uint Callback = 0x8001;
    private readonly WindowProc procedure;
    private readonly Action show, quit;
    private readonly string className = "Shiqi.NotificationWindow." + Guid.NewGuid().ToString("N");
    private readonly uint taskbarCreated;
    private readonly IntPtr window, module, icon;
    private bool registered, disposed;
    public WindowsTray(Action show, Action quit)
    {
        this.show = show; this.quit = quit; procedure = HandleMessage;
        module = GetModuleHandle(null);
        var cls = new WindowClass { Size = (uint)Marshal.SizeOf<WindowClass>(), Procedure = procedure, Instance = module, ClassName = className };
        if (RegisterClassEx(ref cls) == 0) throw new IOException("Could not register Windows tray window.");
        window = CreateWindowEx(0, className, "Shiqi", 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, module, IntPtr.Zero);
        if (window == IntPtr.Zero) { UnregisterClass(className, module); throw new IOException("Could not create Windows tray window."); }
        icon = LoadImage(IntPtr.Zero, Path.Combine(AppContext.BaseDirectory, "Assets", "Shiqi.ico"), 1, 32, 32, 0x10);
        taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        AddIcon();
        if (!registered) { Dispose(); throw new IOException("Could not add Shiqi to the Windows notification area."); }
    }
    private NotifyData Data() => new() { Size = (uint)Marshal.SizeOf<NotifyData>(), Window = window, Id = 1,
        Flags = 1 | 2 | 4, CallbackMessage = Callback, Icon = icon, Tip = "拾期 · Shiqi", Info = "", InfoTitle = "" };
    private void AddIcon()
    {
        var data = Data(); registered = ShellNotifyIcon(0, ref data);
        if (registered) { data.Version = 4; ShellNotifyIcon(4, ref data); }
    }
    public bool Notify(string title, string body)
    {
        if (disposed) return false;
        if (!registered) AddIcon();
        if (!registered) return false;
        var data = Data(); data.Flags = 0x10; data.InfoTitle = Truncate(title, 63); data.Info = Truncate(body, 255);
        data.InfoFlags = 1 | 0x80; // Information; respect Windows quiet time.
        return ShellNotifyIcon(1, ref data);
    }
    private static string Truncate(string text, int length)
    {
        if (text.Length <= length) return text;
        if (char.IsHighSurrogate(text[length - 1])) length--;
        return text[..length];
    }
    private IntPtr HandleMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (taskbarCreated != 0 && message == taskbarCreated) { registered = false; AddIcon(); return IntPtr.Zero; }
        if (message == Callback)
        {
            var action = lParam.ToInt64() & 0xffff;
            if (action is 0x202 or 0x203 or 0x400 or 0x401 or 0x405) show();
            else if (action is 0x205 or 0x7b)
            {
                var menu = CreatePopupMenu();
                try
                {
                    AppendMenu(menu, 0, 1, "打开拾期 / Open Shiqi"); AppendMenu(menu, 0, 2, "退出 / Quit");
                    GetCursorPos(out var point); SetForegroundWindow(window);
                    var selected = TrackPopupMenu(menu, 0x100 | 0x2, point.X, point.Y, 0, window, IntPtr.Zero);
                    if (selected == 1) show(); else if (selected == 2) quit();
                    PostMessage(window, 0, IntPtr.Zero, IntPtr.Zero);
                }
                finally { DestroyMenu(menu); }
            }
            return IntPtr.Zero;
        }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        var data = Data(); if (registered) ShellNotifyIcon(2, ref data);
        if (window != IntPtr.Zero) DestroyWindow(window);
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        UnregisterClass(className, module);
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyData
    {
        public uint Size; public IntPtr Window; public uint Id, Flags, CallbackMessage; public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags; public Guid Guid; public IntPtr BalloonIcon;
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size, Style; public WindowProc Procedure; public int ClassExtra, WindowExtra; public IntPtr Instance, Icon, Cursor, Background;
        [MarshalAs(UnmanagedType.LPWStr)] public string? MenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ClassName;
        public IntPtr SmallIcon;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShellNotifyIcon(uint message, ref NotifyData data);
    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleW", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll", EntryPoint = "RegisterClassExW", CharSet = CharSet.Unicode)] private static extern ushort RegisterClassEx(ref WindowClass cls);
    [DllImport("user32.dll", EntryPoint = "CreateWindowExW", CharSet = CharSet.Unicode)] private static extern IntPtr CreateWindowEx(uint extended, string cls, string name, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll", EntryPoint = "DefWindowProcW")] private static extern IntPtr DefWindowProc(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode)] private static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int width, int height, uint flags);
    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string message);
    [DllImport("user32.dll", EntryPoint = "UnregisterClassW", CharSet = CharSet.Unicode)] private static extern bool UnregisterClass(string cls, IntPtr instance);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string text);
    [DllImport("user32.dll")] private static extern int TrackPopupMenu(IntPtr menu, uint flags, int x, int y, int reserved, IntPtr owner, IntPtr rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "PostMessageW")] private static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
}
