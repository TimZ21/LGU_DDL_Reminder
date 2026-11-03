using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32;
using Shiqi.Core;

namespace Shiqi.Desktop;

internal sealed class WindowsCredential(string target = "Shiqi.Blackboard.Calendar") : IFeedCredential
{
    public string? Read()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        if (!CredRead(target, 1, 0, out var pointer))
        {
            if (Marshal.GetLastWin32Error() == 1168) return null;
            throw new IOException("Could not read Windows Credential Manager / 无法读取 Windows 凭据管理器");
        }
        try
        {
            var value = Marshal.PtrToStructure<Credential>(pointer);
            var bytes = new byte[value.BlobSize]; Marshal.Copy(value.Blob, bytes, 0, bytes.Length);
            try { return Encoding.Unicode.GetString(bytes); } finally { Array.Clear(bytes); }
        }
        finally { CredFree(pointer); }
    }
    public void Write(string text)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var bytes = Encoding.Unicode.GetBytes(text);
        if (bytes.Length > 2560) throw new IOException("Calendar link is too long for Credential Manager / 日历链接超过凭据管理器长度限制");
        var pointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            var credential = new Credential { Type = 1, TargetName = target, BlobSize = (uint)bytes.Length,
                Blob = pointer, Persist = 2, UserName = "Shiqi calendar subscription" };
            if (!CredWrite(ref credential, 0)) throw new IOException("Could not save the calendar link in Credential Manager / 无法保存日历链接到凭据管理器");
        }
        finally { Array.Clear(bytes); for (var i = 0; i < bytes.Length; i++) Marshal.WriteByte(pointer, i, 0); Marshal.FreeHGlobal(pointer); }
    }
    public void Delete()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        if (!CredDelete(target, 1, 0) && Marshal.GetLastWin32Error() != 1168)
            throw new IOException("Could not remove the saved calendar link / 无法移除已保存的日历链接");
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags, Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        [MarshalAs(UnmanagedType.LPWStr)] public string? Comment;
        public long LastWritten;
        public uint BlobSize;
        public IntPtr Blob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)] public string? TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string? UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr pointer);
}

internal static class Startup
{
    public static bool Enabled
    {
        get
        {
            if (!OperatingSystem.IsWindows()) return false;
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            return key?.GetValue("Shiqi") is string;
        }
    }
    public static void Set(bool enabled)
    {
        if (!OperatingSystem.IsWindows()) return;
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
        {
            var executable = Environment.ProcessPath ?? throw new IOException("Could not locate Shiqi.exe");
            key.SetValue("Shiqi", "\"" + executable + "\" --background");
        }
        else key.DeleteValue("Shiqi", false);
    }
}
