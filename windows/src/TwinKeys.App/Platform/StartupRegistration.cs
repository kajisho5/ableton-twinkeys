using System.Runtime.InteropServices;
using Microsoft.Win32;
using Windows.ApplicationModel;

namespace TwinKeys.App.Platform;

/// <summary>
/// "Start at sign-in". The ZIP version (unpackaged) uses the per-user Run key (no administrator needed).
/// The Store version (MSIX) cannot: a packaged app's writes under HKCU are kept private to the package, so
/// Windows would never see them. It uses the package's startup task instead (desktop:StartupTask
/// "TwinKeysAtSignIn" in Package.appxmanifest), which Windows starts at sign-in and the person can also turn
/// off in Settings > Apps > Startup.
/// https://learn.microsoft.com/windows/msix/desktop/desktop-to-uwp-behind-the-scenes
/// https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptask
/// </summary>
internal static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TwinKeys";
    private const string TaskId = "TwinKeysAtSignIn";

    /// <summary>True when TwinKeys runs from its MSIX package (it has a package identity).</summary>
    public static bool IsPackaged { get; } = HasPackageIdentity();

    public static bool IsEnabled
    {
        get
        {
            if (IsPackaged)
            {
                var state = GetTask().State;
                return state is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
            }
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(ValueName) is string;
        }
    }

    public static void Set(bool on)
    {
        if (IsPackaged)
        {
            var task = GetTask();
            if (on)
            {
                // No dialog for a packaged desktop app. If the person turned it off in Task Manager or in
                // Settings, Windows keeps their choice and the state stays DisabledByUser.
                task.RequestEnableAsync().AsTask().GetAwaiter().GetResult();
            }
            else
            {
                task.Disable();
            }
            return;
        }
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

    /// <summary>
    /// Whether this start came from sign-in: "--background" (the Run key of the ZIP version) or the package's
    /// startup task (which cannot pass arguments).
    /// </summary>
    public static bool StartedAtSignIn(string[] commandLine)
    {
        if (commandLine.Contains("--background")) return true;
        if (!IsPackaged) return false;
        try
        {
            return Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs().Kind
                == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.StartupTask;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static StartupTask GetTask() => StartupTask.GetAsync(TaskId).AsTask().GetAwaiter().GetResult();

    // https://learn.microsoft.com/windows/win32/api/appmodel/nf-appmodel-getcurrentpackagefullname
    private const int APPMODEL_ERROR_NO_PACKAGE = 15700;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(ref uint packageFullNameLength, nint packageFullName);

    private static bool HasPackageIdentity()
    {
        uint length = 0;
        try { return GetCurrentPackageFullName(ref length, 0) != APPMODEL_ERROR_NO_PACKAGE; }
        catch (EntryPointNotFoundException) { return false; }
    }
}
