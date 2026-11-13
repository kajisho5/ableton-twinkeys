using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using TwinKeys.App.Platform;
using TwinKeys.App.ViewModels;
using TwinKeys.Core;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Tray;

/// <summary>
/// The notification-area (tray) icon and its right-click menu (docs/design-windows.md 3.3,
/// docs/design/windows-tray-*.png): connection state, All Notes Off, Connect / Disconnect, Key
/// Capture, Open TwinKeys, Settings…, Start at Sign-in, Quit TwinKeys. Shell_NotifyIcon with a hidden
/// message-only window; the menu is a standard Win32 pop-up menu.
/// Icon: filled with a green dot when connected, outline when not, with "!" while reconnecting.
/// </summary>
internal sealed unsafe class TrayIcon : IDisposable
{
    private const uint CallbackMessage = WM_APP + 10;
    private const uint IconId = 1;
    private enum Cmd : uint { AllNotesOff = 10, Connect = 11, KeyCapture = 12, Open = 13, Settings = 14, StartAtSignIn = 15, Quit = 16 }

    private static TrayIcon? current;
    private readonly AppModel model;
    private readonly Action quit;
    private readonly nint hwnd;
    private readonly uint taskbarCreated;
    private readonly nint iconConnected, iconIdle, iconReconnecting;
    private readonly DispatcherQueueTimer timer;
    private nint shownIcon;
    private string shownTip = "";
    private bool added;

    public TrayIcon(AppModel model, Action quit)
    {
        this.model = model;
        this.quit = quit;
        current = this;
        iconConnected = LoadIcon("Tray-Connected.ico");
        iconIdle = LoadIcon("Tray-Idle.ico");
        iconReconnecting = LoadIcon("Tray-Reconnecting.ico");
        taskbarCreated = RegisterWindowMessageW("TaskbarCreated");
        fixed (char* cls = "TwinKeysTrayWindow")
        {
            var wc = new WNDCLASSEXW
            {
                cbSize = (uint)sizeof(WNDCLASSEXW),
                lpfnWndProc = &WndProc,
                hInstance = GetModuleHandleW(null),
                lpszClassName = cls,
            };
            RegisterClassExW(in wc);
        }
        hwnd = CreateWindowExW(0, "TwinKeysTrayWindow", "TwinKeys", 0, 0, 0, 0, 0, HWND_MESSAGE, 0, GetModuleHandleW(null), 0);
        Add();
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(500);
        timer.Tick += (_, _) => Update();
        timer.Start();
    }

    private static nint LoadIcon(string file) =>
        LoadImageW(0, WindowHelpers.AssetPath(file), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);

    private NOTIFYICONDATAW Data(uint flags) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATAW>(),
        hWnd = hwnd,
        uID = IconId,
        uFlags = flags,
        uCallbackMessage = CallbackMessage,
        hIcon = shownIcon,
        szTip = shownTip,
        szInfo = "",
        szInfoTitle = "",
        uVersion = NOTIFYICON_VERSION_4,
    };

    private void Add()
    {
        shownIcon = iconIdle;
        shownTip = "TwinKeys";
        var d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        added = Shell_NotifyIconW(NIM_ADD, ref d);
        Shell_NotifyIconW(NIM_SETVERSION, ref d);
        Update();
    }

    private (string Title, string Detail, nint Icon) State()
    {
        var S = Strings.Current;
        var s = model.Snapshot();
        string Name(string id) => s.PeerNames.GetValueOrDefault(id) ?? (id.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) ? id[PeerInfo.ManualPrefix.Length..] : S["AnotherComputer"]);
        return s.Link switch
        {
            LinkStateMachine.State.Connected c => (S.F("ConnectedTo", Name(c.Peer)),
                s.LatencyMs is double ms ? S.F("TrayLatency", $"{ms:0}") : S["Measuring"], iconConnected),
            LinkStateMachine.State.Connecting c => (S.F("ConnectingTo", Name(c.Peer)), S["WaitingForAnswer"], iconReconnecting),
            _ => (s.IsPaired ? S["NotConnected"] : S["NeedsPairing"], "", iconIdle),
        };
    }

    private void Update()
    {
        if (!added) return;
        var (title, _, icon) = State();
        var tip = ("TwinKeys — " + title);
        if (tip.Length > 120) tip = tip[..120];
        if (icon == shownIcon && tip == shownTip) return;
        shownIcon = icon;
        shownTip = tip;
        var d = Data(NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        Shell_NotifyIconW(NIM_MODIFY, ref d);
    }

    private void ShowMenu()
    {
        var S = Strings.Current;
        var s = model.Snapshot();
        var (title, detail, _) = State();
        nint menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 1, title);
        if (detail.Length > 0) AppendMenuW(menu, MF_STRING | MF_GRAYED, 2, detail);
        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        AppendMenuW(menu, MF_STRING, (nuint)Cmd.AllNotesOff, S["AllNotesOff"] + "\t" + model.Settings.HotkeyAllNotesOff);
        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        bool linked = s.Link is not LinkStateMachine.State.Idle;
        AppendMenuW(menu, MF_STRING, (nuint)Cmd.Connect, (linked ? S["Disconnect"] : S["Connect"]) + "\tCtrl+K");
        AppendMenuW(menu, MF_STRING | (s.KeyCapture ? MF_CHECKED : 0), (nuint)Cmd.KeyCapture, S["KeyCapture"] + "\t" + model.Settings.HotkeyKeyCapture);
        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        AppendMenuW(menu, MF_STRING, (nuint)Cmd.Open, S["OpenTwinKeys"]);
        AppendMenuW(menu, MF_STRING, (nuint)Cmd.Settings, S["SettingsMenu"] + "\tCtrl+,");
        AppendMenuW(menu, MF_STRING | (StartupRegistration.IsEnabled ? MF_CHECKED : 0), (nuint)Cmd.StartAtSignIn, S["StartAtSignIn"]);
        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        AppendMenuW(menu, MF_STRING, (nuint)Cmd.Quit, S["QuitTwinKeys"]);
        GetCursorPos(out var pt);
        // The window must be in front, or the menu does not close when clicking elsewhere.
        SetForegroundWindow(hwnd);
        int cmd = TrackPopupMenuEx(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY | TPM_BOTTOMALIGN, pt.X, pt.Y, hwnd, 0);
        DestroyMenu(menu);
        switch ((Cmd)cmd)
        {
            case Cmd.AllNotesOff: model.Panic(); break;
            case Cmd.Connect: model.ToggleConnect(); break;
            case Cmd.KeyCapture: model.SetKeyCapture(!model.Settings.KeyCapture); break;
            case Cmd.Open: model.RequestShowMain(); break;
            case Cmd.Settings: model.RequestShowSettings(); break;
            case Cmd.StartAtSignIn:
                try { StartupRegistration.Set(!StartupRegistration.IsEnabled); }
                catch (Exception e) { model.Log("Start at sign-in could not be changed: " + e.Message); }
                break;
            case Cmd.Quit: quit(); break;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static nint WndProc(nint hWnd, uint msg, nuint wParam, nint lParam)
    {
        var self = current;
        try
        {
            if (self is not null)
            {
                if (msg == CallbackMessage)
                {
                    // NOTIFYICON_VERSION_4: the event is in the low word of lParam.
                    int ev = (int)(lParam & 0xFFFF);
                    switch (ev)
                    {
                        case WM_CONTEXTMENU:
                        case WM_RBUTTONUP:
                            self.ShowMenu();
                            return 0;
                        case NIN_SELECT:
                        case NIN_KEYSELECT:
                        case WM_LBUTTONUP:
                        case WM_LBUTTONDBLCLK:
                            self.model.RequestShowMain();
                            return 0;
                    }
                }
                else if (msg == self.taskbarCreated && self.taskbarCreated != 0)
                {
                    self.Add();   // Explorer restarted: the icon must be added again
                    return 0;
                }
            }
        }
        catch
        {
            // Never let an exception cross into Windows.
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        timer.Stop();
        if (added)
        {
            var d = Data(0);
            Shell_NotifyIconW(NIM_DELETE, ref d);
            added = false;
        }
        DestroyWindow(hwnd);
        foreach (var i in new[] { iconConnected, iconIdle, iconReconnecting }) if (i != 0) DestroyIcon(i);
        if (current == this) current = null;
    }
}
