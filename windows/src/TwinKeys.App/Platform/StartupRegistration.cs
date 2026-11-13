using Microsoft.Win32;

namespace TwinKeys.App.Platform;

/// <summary>"Start at sign-in": the per-user Run key (no administrator needed).</summary>
internal static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TwinKeys";

    public static bool IsEnabled
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(ValueName) is string;
        }
    }

    public static void Set(bool on)
    {
        using var k = Registry.CurrentUser.CreateSubKey(RunKey);
        if (on)
        {
            var exe = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "TwinKeys.exe");
            k.SetValue(ValueName, $"\"{exe}\" --background");
        }
        else
        {
            k.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
