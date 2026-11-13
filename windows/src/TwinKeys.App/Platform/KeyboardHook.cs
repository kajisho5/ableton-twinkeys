using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using TwinKeys.Core;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

/// <summary>
/// Reads every key press with a low-level keyboard hook (WH_KEYBOARD_LL) on its own thread with its
/// own message loop (docs/design-windows.md 5.2), and registers the system-wide shortcuts
/// (RegisterHotKey) on the same thread.
///
/// Keys are identified by scan code + extended flag (<see cref="KeyIds"/>), i.e. by position, so a
/// JIS and a US keyboard give the same cue for the same key. The callback must answer quickly
/// (Windows silently removes a hook that takes longer than LowLevelHooksTimeout): it only asks the
/// Conductor, which decides and queues the MIDI and UDP output for other threads.
/// The hook is installed again every 15 s (new one first, then the old one removed), so a hook that
/// Windows removed silently comes back by itself.
/// </summary>
internal sealed unsafe class KeyboardHook : IDisposable
{
    /// <summary>Return true to keep the key from other apps.</summary>
    public Func<KeyInput, bool>? OnKey { get; set; }
    /// <summary>A registered hot key fired (its id).</summary>
    public Action<int>? OnHotKey { get; set; }
    public Action<string>? Log { get; set; }
    /// <summary>False when the hook could not be installed.</summary>
    public bool IsInstalled { get; private set; }
    /// <summary>When the hook last saw a key (Environment.TickCount64).</summary>
    public long LastKeyAt { get; private set; }

    private static KeyboardHook? current;
    private Thread? thread;
    private uint threadId;
    private nint hook;
    private readonly HashSet<ushort> down = [];
    private readonly List<(int Id, uint Modifiers, uint Vk)> hotKeys = [];
    private readonly ManualResetEventSlim started = new();
    private const uint WM_REGISTER_HOTKEYS = WM_APP + 1;
    private const uint WM_FORGET_DOWN = WM_APP + 2;
    private const nuint ReinstallTimer = 1;

    public void Start()
    {
        current = this;
        thread = new Thread(Run) { IsBackground = true, Name = "TwinKeys keyboard hook", Priority = ThreadPriority.Highest };
        thread.Start();
        started.Wait(TimeSpan.FromSeconds(5));
    }

    /// <summary>Sets the system-wide shortcuts (id, MOD_* flags, virtual key). Replaces the earlier ones.</summary>
    public void SetHotKeys(IEnumerable<(int Id, uint Modifiers, uint Vk)> keys)
    {
        lock (hotKeys) { hotKeys.Clear(); hotKeys.AddRange(keys); }
        if (threadId != 0) PostThreadMessageW(threadId, WM_REGISTER_HOTKEYS, 0, 0);
    }

    private void Run()
    {
        threadId = GetCurrentThreadId();
        Install();
        RegisterHotKeys();
        SetTimer(0, ReinstallTimer, 15_000, 0);
        started.Set();
        while (GetMessageW(out var msg, 0, 0, 0) > 0)
        {
            switch (msg.message)
            {
                case WM_HOTKEY:
                    try { OnHotKey?.Invoke((int)msg.wParam); } catch (Exception e) { Log?.Invoke("Hot key handler failed: " + e.Message); }
                    break;
                case WM_REGISTER_HOTKEYS:
                    RegisterHotKeys();
                    break;
                case WM_FORGET_DOWN:
                    down.Clear();
                    break;
                case WM_TIMER when msg.wParam == ReinstallTimer:
                    Install();
                    break;
                default:
                    TranslateMessage(in msg);
                    DispatchMessageW(in msg);
                    break;
            }
        }
        if (hook != 0) UnhookWindowsHookEx(hook);
        lock (hotKeys) foreach (var h in hotKeys) UnregisterHotKey(0, h.Id);
    }

    /// <summary>Installs a new hook, then removes the old one (no gap: both calls run on this thread between messages).</summary>
    private void Install()
    {
        var fresh = SetWindowsHookExW(WH_KEYBOARD_LL, &HookProc, GetModuleHandleW(null), 0);
        if (fresh == 0)
        {
            int err = Marshal.GetLastPInvokeError();
            if (IsInstalled || hook == 0) Log?.Invoke($"Keyboard hook could not be installed (error {err})");
            IsInstalled = hook != 0;
            return;
        }
        if (hook != 0) UnhookWindowsHookEx(hook);
        hook = fresh;
        IsInstalled = true;
    }

    private void RegisterHotKeys()
    {
        lock (hotKeys)
        {
            for (int id = 1; id <= 16; id++) UnregisterHotKey(0, id);
            foreach (var h in hotKeys)
                if (!RegisterHotKey(0, h.Id, h.Modifiers | MOD_NOREPEAT, h.Vk))
                    Log?.Invoke($"Shortcut {h.Id} could not be registered (another app uses it?), error {Marshal.GetLastPInvokeError()}");
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static nint HookProc(int nCode, nuint wParam, nint lParam)
    {
        var self = current;
        if (nCode >= 0 && self is not null)
        {
            try
            {
                if (self.Handle((int)wParam, (KBDLLHOOKSTRUCT*)lParam)) return 1;
            }
            catch
            {
                // Never let an exception cross into Windows; the key goes on as usual.
            }
        }
        return CallNextHookEx(0, nCode, wParam, lParam);
    }

    private bool Handle(int message, KBDLLHOOKSTRUCT* k)
    {
        if ((k->flags & LLKHF_INJECTED) != 0) return false;   // typed by software, not by a person
        if (k->scanCode == 0 || k->scanCode > 0xFF) return false;
        LastKeyAt = Environment.TickCount64;
        bool isDown = message is WM_KEYDOWN or WM_SYSKEYDOWN;
        var id = KeyIds.Make(k->scanCode, (k->flags & LLKHF_EXTENDED) != 0);
        bool repeat = false;
        if (isDown) repeat = !down.Add(id);
        else down.Remove(id);
        var mods = Modifiers.None;
        if (isDown)
        {
            if (GetAsyncKeyState(VK_SHIFT) < 0) mods |= Modifiers.Shift;
            if (GetAsyncKeyState(VK_CONTROL) < 0) mods |= Modifiers.Control;
            if (GetAsyncKeyState(VK_MENU) < 0) mods |= Modifiers.Alt;
            if (GetAsyncKeyState(VK_LWIN) < 0 || GetAsyncKeyState(VK_RWIN) < 0) mods |= Modifiers.Command;
        }
        return OnKey?.Invoke(new KeyInput(id, isDown, repeat, mods)) ?? false;
    }

    /// <summary>Keys this hook thinks are down (cleared when key-ups may have been missed).</summary>
    public void ForgetDownKeys() => PostThreadMessageW(threadId, WM_FORGET_DOWN, 0, 0);

    public void Dispose()
    {
        if (threadId != 0) PostThreadMessageW(threadId, WM_QUIT, 0, 0);
        thread?.Join(TimeSpan.FromSeconds(2));
        if (current == this) current = null;
    }
}
