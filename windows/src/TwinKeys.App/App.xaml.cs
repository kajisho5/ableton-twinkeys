using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using TwinKeys.App.Platform;
using TwinKeys.App.Tray;
using TwinKeys.App.ViewModels;
using TwinKeys.App.Views;

namespace TwinKeys.App;

/// <summary>
/// One TwinKeys per Windows user. It keeps running in the notification area when the window is
/// closed (as on the Mac, docs/design-windows.md 3.3); "--background" (start at sign-in) opens no window.
/// </summary>
public partial class App : Application
{
    private const string MutexName = @"Local\TwinKeys-SingleInstance";
    private const string ShowEventName = @"Local\TwinKeys-Show";
    private Mutex? single;
    private EventWaitHandle? showEvent;
    private AppModel? model;
    private static readonly FileLog EarlyLog = new(Path.Combine(TwinKeys.Core.SettingsStore.DefaultDirectory, "Logs"));
    private MainWindow? main;
    private SettingsWindow? settings;
    private FirstRunWindow? firstRun;
    private TrayIcon? tray;

    public App()
    {
        InitializeComponent();
        try { EarlyLog.Write("Resources: " + ThemeResources.Ensure(this)); }
        catch (Exception e) { EarlyLog.Write("Resources could not be added: " + e); }
        // Keep running with no window open (notification area only, or started at sign-in).
        DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;
        UnhandledException += (_, e) => EarlyLog.Write("Unhandled: " + e.Message + " | " + e.Exception);
        // A XAML resource that cannot be found only shows in a debugger otherwise: write it to the log.
        DebugSettings.XamlResourceReferenceFailed += (_, e) => EarlyLog.Write("XAML resource reference failed: " + e.Message);
        DebugSettings.BindingFailed += (_, e) => EarlyLog.Write("XAML binding failed: " + e.Message);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        single = new Mutex(true, MutexName, out bool first);
        if (!first)
        {
            // Already running: bring that one to the front and stop.
            try { EventWaitHandle.OpenExisting(ShowEventName).Set(); } catch (WaitHandleCannotBeOpenedException) { }
            Exit();
            return;
        }
        var ui = DispatcherQueue.GetForCurrentThread();
        showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        new Thread(() =>
        {
            while (showEvent.WaitOne()) ui.TryEnqueue(ShowMain);
        }) { IsBackground = true, Name = "TwinKeys show request" }.Start();

        model = new AppModel(ui);
        model.ShowMainRequested += ShowMain;
        model.ShowSettingsRequested += () => ShowSettings(null);
        tray = new TrayIcon(model, Quit);

        var cmd = Environment.GetCommandLineArgs();
        if (cmd.Contains("--smoke-windows"))
        {
            // CI: open every window and settings page once, so a XAML error shows up in the log.
            XamlCheck.Run(EarlyLog.Write);
            ShowFirstRun();
            ShowMain();
            foreach (var page in new[] { "cues", "midi", "live", "pairing", "updates", "general" }) ShowSettings(page);
            EarlyLog.Write("Smoke: all windows opened");
            return;
        }
        bool background = cmd.Contains("--background");
        if (!model.Settings.FirstRunDone && !background) ShowFirstRun();
        else if (!background) ShowMain();
    }

    private void ShowMain()
    {
        if (model is null) return;
        try
        {
            main ??= new MainWindow(model, ShowSettings, ShowFirstRun, Quit);
            WindowHelpers.Show(main);
        }
        catch (Exception e)
        {
            EarlyLog.Write("Main window failed: " + e);
        }
    }

    private void ShowSettings(string? page)
    {
        if (model is null) return;
        try
        {
            if (settings is null)
            {
                settings = new SettingsWindow(model, ShowFirstRun);
                settings.Closed += (_, _) => settings = null;
            }
            if (page is not null) settings.SelectPage(page);
            WindowHelpers.Show(settings);
        }
        catch (Exception e)
        {
            EarlyLog.Write("Settings window failed: " + e);
            settings = null;
        }
    }

    private void ShowFirstRun()
    {
        if (model is null) return;
        try
        {
            if (firstRun is null)
            {
                firstRun = new FirstRunWindow(model);
                firstRun.Closed += (_, _) => { firstRun = null; ShowMain(); };
            }
            WindowHelpers.Show(firstRun);
        }
        catch (Exception e)
        {
            // Never leave the person without a window: the main window still works without this one.
            EarlyLog.Write("First-run window failed: " + e);
            firstRun = null;
            ShowMain();
        }
    }

    private void Quit()
    {
        tray?.Dispose();
        model?.Dispose();
        single?.ReleaseMutex();
        Exit();
    }
}
