using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;
using TwinKeys.App.Platform;
using TwinKeys.Core;

namespace TwinKeys.App.ViewModels;

/// <summary>
/// Everything the windows and the tray menu show and do, around one Conductor (the Windows
/// counterpart of the Mac's AppModel). Platform parts: the keyboard hook, WinMM MIDI out, UDP,
/// mDNS, DPAPI; Live through TwinKeysBridge (phase 2). The windows read <see cref="Snapshot"/> a few
/// times a second.
/// </summary>
internal sealed class AppModel : ObservableObject, IDisposable
{
    public const int HotKeyCapture = 1, HotKeyAllNotesOff = 2;
    public static string Version => typeof(AppModel).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "0.1.0";
    public const string ReleasesPage = "https://github.com/kajisho5/ableton-twinkeys/releases";
    public const string HelpPageJa = "https://github.com/kajisho5/ableton-twinkeys/blob/main/docs/help/ja.md#windows-版試験版";
    public const string HelpPageEn = "https://github.com/kajisho5/ableton-twinkeys/blob/main/docs/help/en.md#windows-test-version";

    private readonly DispatcherQueue ui;
    private readonly SettingsStore store;
    private readonly FileLog log;
    private readonly PairingStore pairing;
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly KeyboardHook hook = new();
    private readonly DnsSdDiscovery discovery;
    private readonly Timer ticker;
    private readonly Timer liveTicker;
    private readonly MainLossWatch mainLoss = new();
    private Action<KeyInput>? learner;
    private bool userDisconnected;
    private bool disposed;

    public AppSettings Settings { get; }
    public Conductor Conductor { get; }
    public UdpTransport Net { get; } = new();
    public WinMmMidiOut Midi { get; }
    /// <summary>This PC's Live (TwinKeysBridge on 127.0.0.1).</summary>
    public BridgeClient Bridge { get; } = new();
    /// <summary>Live answered within the last 6 s (refreshed twice a second).</summary>
    public bool LiveConnected { get; private set; }
    /// <summary>Live still runs an older TwinKeysBridge than the one in this app.</summary>
    public bool BridgeNeedsRestart { get; private set; }
    public string DisplayName { get; } = Environment.MachineName;
    public string? PairingCode { get; private set; }
    /// <summary>A problem to show at the top of the window (null: none).</summary>
    public string? Problem { get; private set; }
    /// <summary>True while a text box or a dialog of TwinKeys has the keyboard (keys then go there, not to cues; as on the Mac).</summary>
    public volatile bool OwnInputHasFocus;
    /// <summary>The last test note reached the port without an error.</summary>
    public bool TestSendWorked { get; private set; }

    /// <summary>Peers, settings or the language changed (on the UI thread).</summary>
    public event Action? Changed;
    public event Action? LanguageChanged;
    public event Action? ShowMainRequested;
    public event Action? ShowSettingsRequested;

    public AppModel(DispatcherQueue ui)
    {
        this.ui = ui;
        store = new SettingsStore(SettingsStore.DefaultDirectory);
        var (settings, broken) = store.Load();
        Settings = settings;
        log = new FileLog(store.LogsDirectory);
        log.Write($"TwinKeys for Windows {Version} starting ({System.Runtime.InteropServices.RuntimeInformation.OSDescription}, {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture})");
        Strings.Use(Settings.Language);
        if (broken is not null) Problem = Strings.Current.F("ProblemSettingsBroken", broken);
        if (!SecureChannel.IsSupported) Problem = Strings.Current["ProblemNoChaCha"];

        Midi = new WinMmMidiOut(Settings.MidiPortName) { Log = log.Write };
        if (Settings.MidiMode != MidiOutputMode.Loopback) Midi.SetPort(Settings.MidiPortName, false);

        Conductor = new Conductor(Settings.InstanceId, DisplayName, Settings, Midi, Net,
            () => clock.Elapsed.TotalSeconds, () => (ulong)clock.Elapsed.Ticks * 100);
        Conductor.Log = log.Write;
        Conductor.OnRoleChange = isMain => ui.TryEnqueue(() => RoleChanged(isMain));
        // Backup: Live commands forwarded by the main run on this PC's Live, and the main is told what Live did.
        Conductor.OnLiveCommandRun = (cmd, answer) =>
            Bridge.Run(cmd, done: (ok, err) => answer(ok ? Conductor.LiveRun.Ran : err == "no_answer" ? Conductor.LiveRun.NoAnswer : Conductor.LiveRun.Refused));
        Net.OnDatagram = (bytes, known) => Conductor.Receive(bytes, known);
        Net.OnNewRoute = Conductor.NewRoute;
        Net.Log = log.Write;

        pairing = new PairingStore(store.Directory);
        var code = pairing.Load();
        if (code is not null && PairingSecret.FromCode(code) is PairingSecret secret)
        {
            PairingCode = Pairing.Formatted(Pairing.Normalize(code)!);
            Conductor.SetPairing(secret);
        }

        try { Net.Start(); }
        catch (SocketException e)
        {
            Problem = Strings.Current["ProblemListen"];
            log.Write("UDP listen failed: " + e.Message);
        }

        discovery = new DnsSdDiscovery(GuidBytes.ToSwiftString(Settings.InstanceId))
        {
            Log = log.Write,
            EndPointChanged = (id, ep) => Net.SetDiscovered(id, ep),
            PeersChanged = _ => ui.TryEnqueue(PeersChanged),
            DuplicateId = () => ui.TryEnqueue(() => { Problem = Strings.Current["ProblemDuplicateId"]; Changed?.Invoke(); }),
        };
        Conductor.IsKnownPeer = discovery.IsVisible;
        try
        {
            discovery.Start();
            Advertise();
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException)
        {
            log.Write("mDNS is not available: " + e.Message);
        }

        hook.OnKey = OnKey;
        hook.OnHotKey = OnHotKey;
        hook.Log = log.Write;
        hook.Start();
        RegisterHotKeys();
        if (!hook.IsInstalled) Problem = Strings.Current["ProblemHook"];

        ticker = new Timer(_ => { try { Conductor.Tick(); } catch (Exception e) { log.Write("Tick failed: " + e); } }, null, 0, 50);

        // Live (phase 2): an older TwinKeysBridge from a previous TwinKeys is replaced with the one in this app.
        Bridge.Log = log.Write;
        var installer = Installer;
        if (installer.UpdateIfOutdated()) log.Write($"Live Bridge: installed copy updated to version {installer.BundledVersion}");
        Bridge.Start();
        liveTicker = new Timer(_ => { try { RefreshLive(); } catch (Exception e) { log.Write("Live refresh failed: " + e); } }, null, 500, 500);

        // Connect again to the computer used last time (by IP address now; by name when mDNS sees it).
        if (Settings.LastPeerId?.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) == true && Settings.ManualAddress is string addr)
            _ = ConnectByAddressAsync(addr);
    }

    public ConductorSnapshot Snapshot() => Conductor.Snapshot();

    // MARK: Live (phase 2)

    /// <summary>The Bridge files inside this app (copied next to TwinKeys.exe by the build).</summary>
    public static string BundledBridge => Path.Combine(AppContext.BaseDirectory, BridgeInstaller.FolderName);
    public static string DefaultUserLibrary => BridgeInstaller.DefaultUserLibrary(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
    public BridgeInstaller Installer => new(BundledBridge, Settings.LiveUserLibrary ?? DefaultUserLibrary);

    private void RefreshLive()
    {
        bool on = Bridge.IsConnected;
        LiveConnected = on;
        Conductor.SetLiveConnected(on);
        // One copy per refresh (it copies the whole Live state).
        var live = on ? Bridge.Snapshot() : null;
        Conductor.SetLocalSet(live is null ? null : SetSummary.Of(live));
        BridgeNeedsRestart = live is not null && (live.Song.BridgeVersion ?? 0) < Installer.BundledVersion;
    }

    /// <summary>Installs or updates TwinKeysBridge in Live's User Library. Returns an error, or null.</summary>
    public string? InstallBridge()
    {
        var i = Installer;
        var err = i.Install();
        log.Write(err is null ? $"Live Bridge installed into {i.Installed}" : $"Live Bridge install failed: {err}");
        Changed?.Invoke();
        return err;
    }

    /// <summary>The User Library Live uses, when it is not the default (null: back to the default).</summary>
    public void SetUserLibrary(string? folder)
    {
        Settings.LiveUserLibrary = string.IsNullOrWhiteSpace(folder) ? null : folder;
        Save();
        Changed?.Invoke();
    }

    /// <summary>"When the main computer has stopped": the other computer was linked and has stopped answering, and this PC only receives.</summary>
    public bool MainLost(ConductorSnapshot s)
    {
        double now = clock.Elapsed.TotalSeconds;
        lock (mainLoss)
        {
            mainLoss.Update(s.Link, now);
            return !s.SendKeys && !s.ClaimsMain && mainLoss.IsLost(now);
        }
    }

    /// <summary>"Make this PC the main" (the Mac's 2.3 switch to the backup).</summary>
    public void BecomeMain() => Conductor.ClaimMain();

    /// <summary>"Return to Main": only while linked.</summary>
    public bool ReturnToMain() => Conductor.HandOverMain();
    public IReadOnlyList<PeerInfo> Peers => discovery.Peers;
    public bool HookInstalled => hook.IsInstalled;

    private void Advertise()
    {
        if (Net.ListenPort is ushort port) discovery.Advertise(DisplayName, port, Settings.SendKeys, Settings.ReceiveNotes);
    }

    private void Save()
    {
        if (!store.TrySave(Settings)) log.Write("settings.json could not be saved");
    }

    private void PeersChanged()
    {
        var peers = discovery.Peers;
        Conductor.Prune(peers.Select(p => p.Id).ToHashSet());
        // The computer used last time is back on the network: connect to it again (unless the person disconnected).
        var s = Conductor.Snapshot();
        if (s.Link is LinkStateMachine.State.Idle && !userDisconnected && s.IsPaired
            && Settings.LastPeerId is string last && peers.Any(p => p.Id == last && p.IsCompatible))
            Conductor.Connect(last);
        Changed?.Invoke();
    }

    private void RoleChanged(bool isMain)
    {
        Settings.SendKeys = isMain;
        Settings.ReceiveNotes = !isMain;
        log.Write(isMain ? "Role: this PC is the main" : "Role: the other computer is the main; this PC only receives");
        Save();
        Advertise();
        Changed?.Invoke();
    }

    // MARK: Keys

    private bool OnKey(KeyInput k)
    {
        if (learner is Action<KeyInput> learn)
        {
            if (!k.IsDown || KeyIds.IsModifier(k.KeyCode)) return false;
            if (!k.IsRepeat) ui.TryEnqueue(() => learn(k));
            return true;
        }
        // TwinKeys' own text boxes and dialogs get the keys (the arrows move the cursor there).
        if (k.IsDown && OwnInputHasFocus && ForegroundIsTwinKeys()) return false;
        return Conductor.HandleKey(k);
    }

    private static bool ForegroundIsTwinKeys()
    {
        NativeMethods.GetWindowThreadProcessId(NativeMethods.GetForegroundWindow(), out var pid);
        return pid == (uint)Environment.ProcessId;
    }

    private void OnHotKey(int id)
    {
        switch (id)
        {
            case HotKeyAllNotesOff: Conductor.Panic(); break;
            case HotKeyCapture: ui.TryEnqueue(() => SetKeyCapture(!Settings.KeyCapture)); break;
        }
    }

    private void RegisterHotKeys()
    {
        var list = new List<(int, uint, uint)>();
        if (Hotkey.Parse(Settings.HotkeyKeyCapture) is (uint m1, uint k1)) list.Add((HotKeyCapture, m1, k1));
        if (Hotkey.Parse(Settings.HotkeyAllNotesOff) is (uint m2, uint k2)) list.Add((HotKeyAllNotesOff, m2, k2));
        hook.SetHotKeys(list);
    }

    /// <summary>"Add Key…": the next key presses go to <paramref name="onKey"/> instead of the cues.</summary>
    public void StartLearning(Action<KeyInput> onKey) => learner = onKey;
    public void StopLearning() => learner = null;

    // MARK: Connection

    public void Connect(PeerInfo p)
    {
        userDisconnected = false;
        Settings.LastPeerId = p.Id;
        Save();
        Conductor.Connect(p.Id);
    }

    public void Disconnect()
    {
        userDisconnected = true;
        Conductor.Disconnect();
    }

    /// <summary>Ctrl+K: disconnect, or connect to the computer used last (or the only one found).</summary>
    public void ToggleConnect()
    {
        var s = Conductor.Snapshot();
        if (s.Link is not LinkStateMachine.State.Idle) { Disconnect(); return; }
        var peers = discovery.Peers.Where(p => p.IsCompatible).ToList();
        var target = peers.FirstOrDefault(p => p.Id == Settings.LastPeerId) ?? (peers.Count == 1 ? peers[0] : null);
        if (target is not null) Connect(target);
        else if (Settings.ManualAddress is string a && Settings.LastPeerId?.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) == true) _ = ConnectByAddressAsync(a);
    }

    /// <summary>Returns false when the address cannot be used.</summary>
    public async Task<bool> ConnectByAddressAsync(string text)
    {
        if (ManualAddress.Parse(text) is not (string host, ushort port)) return false;
        IPAddress? addr;
        if (!IPAddress.TryParse(host, out addr))
        {
            try { addr = (await Dns.GetHostAddressesAsync(host)).OrderBy(a => a.AddressFamily == AddressFamily.InterNetwork ? 0 : 1).FirstOrDefault(); }
            catch (SocketException) { addr = null; }
        }
        if (addr is null) return false;
        var placeholder = PeerInfo.ManualPrefix + text.Trim();
        Net.SetManual(placeholder, new IPEndPoint(addr, port));
        userDisconnected = false;
        Settings.ManualAddress = text.Trim();
        Settings.LastPeerId = placeholder;
        Save();
        Conductor.Connect(placeholder);
        return true;
    }

    public void Panic() => Conductor.Panic();

    // MARK: Modes

    public void SetSendKeys(bool on)
    {
        Conductor.SetSendKeys(on);
        Settings.SendKeys = on;
        Save();
        Advertise();
    }

    public void SetReceiveNotes(bool on)
    {
        Conductor.SetReceiveNotes(on);
        Settings.ReceiveNotes = on;
        Save();
        Advertise();
    }

    public void SetKeyCapture(bool on)
    {
        Conductor.SetKeyCapture(on);
        if (on) hook.ForgetDownKeys();
        Settings.KeyCapture = on;
        Save();
        Changed?.Invoke();
    }

    public void SetCueKeys(List<CueKey> keys)
    {
        var clean = CueKey.Sanitized(keys);
        Conductor.SetCueKeys(clean);
        Settings.CueKeys = clean;
        Save();
        Changed?.Invoke();
    }

    public void SetBlockCueKeys(bool on)
    {
        Conductor.SetBlockCueKeys(on);
        Settings.BlockCueKeys = on;
        Save();
    }

    public void SetAutoNoteOff(double seconds)
    {
        Conductor.SetAutoNoteOff(seconds);
        Settings.AutoNoteOffSeconds = seconds;
        Save();
    }

    // MARK: MIDI output

    public void SetMidiOutput(MidiOutputMode mode, string portName)
    {
        Settings.MidiMode = mode;
        Settings.MidiPortName = string.IsNullOrWhiteSpace(portName) ? "TwinKeys" : portName.Trim();
        Midi.SetPort(Settings.MidiPortName, mode == MidiOutputMode.Loopback);
        TestSendWorked = false;
        Save();
        Changed?.Invoke();
    }

    public void FinishFirstRun()
    {
        Settings.FirstRunDone = true;
        Save();
    }

    /// <summary>"Send a test": C1 (note 36) on/off to this PC's port only (not to the other computer).</summary>
    public async Task<bool> TestSendAsync()
    {
        Midi.Rescan();
        await Task.Delay(150);
        if (Midi.Current is not WinMmMidiOut.Status.Ready) { TestSendWorked = false; return false; }
        byte ch = (byte)(Math.Clamp(Settings.MidiChannel, 1, 16) - 1);
        Midi.Send(MidiMessage.NoteOn(ch, CueKey.FirstNote, CueKey.Velocity).Bytes);
        await Task.Delay(200);
        Midi.Send(MidiMessage.NoteOff(ch, CueKey.FirstNote).Bytes);
        await Task.Delay(100);
        TestSendWorked = Midi.Current is WinMmMidiOut.Status.Ready;
        Changed?.Invoke();
        return TestSendWorked;
    }

    // MARK: Pairing code

    public bool SetPairingCode(string? code)
    {
        if (code is null)
        {
            pairing.Save(null);
            PairingCode = null;
            Conductor.SetPairing(null);
            Changed?.Invoke();
            return true;
        }
        if (Pairing.Normalize(code) is not string n || PairingSecret.FromCode(n) is not PairingSecret secret) return false;
        PairingCode = Pairing.Formatted(n);
        if (!pairing.Save(PairingCode)) log.Write("The pairing code could not be saved");
        Conductor.SetPairing(secret);
        Changed?.Invoke();
        return true;
    }

    public string MakeNewPairingCode()
    {
        var c = Pairing.Generate();
        SetPairingCode(c);
        return c;
    }

    public static List<string> LocalAddresses()
    {
        var list = new List<string>();
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var a in ni.GetIPProperties().UnicastAddresses)
                    if (a.Address.AddressFamily == AddressFamily.InterNetwork) list.Add(a.Address.ToString());
            }
        }
        catch (NetworkInformationException) { }
        return list.Distinct().ToList();
    }

    // MARK: General

    public void SetLanguage(string lang)
    {
        Settings.Language = lang;
        Strings.Use(lang);
        Save();
        LanguageChanged?.Invoke();
        Changed?.Invoke();
    }

    public void SetCloseToTray(bool on)
    {
        Settings.CloseToTray = on;
        Save();
    }

    public void RequestShowMain() => ShowMainRequested?.Invoke();
    public void RequestShowSettings() => ShowSettingsRequested?.Invoke();
    public string LogDirectory => log.Directory;
    public void Log(string s) => log.Write(s);

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    /// <summary>Quit: notes off here and on the other computer, say goodbye, then stop.</summary>
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        log.Write("Quitting");
        Conductor.PrepareForQuit();
        Net.Flush(TimeSpan.FromSeconds(1));
        ticker.Dispose();
        liveTicker.Dispose();
        Bridge.Dispose();
        hook.Dispose();
        discovery.Dispose();
        Midi.Dispose();
        Net.Dispose();
    }
}
