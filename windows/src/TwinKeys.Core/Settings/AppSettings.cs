using System.Text.Json;
using System.Text.Json.Nodes;

namespace TwinKeys.Core;

/// <summary>How cues reach Live on this PC (docs/design-windows.md chapter 4).</summary>
public enum MidiOutputMode
{
    /// <summary>M1: send to the loopback MIDI port the user created (Windows MIDI Services or loopMIDI).</summary>
    Loopback,
    /// <summary>M2: a virtual device made by TwinKeys (Windows MIDI Services SDK). Not available yet.</summary>
    VirtualDevice,
    /// <summary>M3: no MIDI, cues become Live actions through TwinKeysBridge (phase 2).</summary>
    BridgeOnly,
}

/// <summary>
/// Settings of the Windows version. The keys match the Mac's settings.json (snake_case) where
/// they mean the same; Windows-only values live under "windows" (docs/design-windows.md 8.3).
/// The pairing code is never stored here (it is kept with DPAPI in a separate file).
/// </summary>
public sealed class AppSettings
{
    public int Version { get; set; } = 1;
    public Guid InstanceId { get; set; } = Guid.NewGuid();
    public bool SendKeys { get; set; } = true;
    public bool ReceiveNotes { get; set; } = true;
    public bool KeyCapture { get; set; } = true;
    public double AutoNoteOffSeconds { get; set; } = 10;
    /// <summary>1-16 as shown to people.</summary>
    public int MidiChannel { get; set; } = 1;
    public string? LastPeerId { get; set; }
    /// <summary>"system", "en" or "ja".</summary>
    public string Language { get; set; } = "system";
    public string? ManualAddress { get; set; }
    public List<CueKey> CueKeys { get; set; } = [.. CueKey.Defaults];
    /// <summary>Keep cue keys from other apps (the keyboard hook swallows them).</summary>
    public bool BlockCueKeys { get; set; } = true;
    public bool AutoUpdate { get; set; } = true;
    /// <summary>Closing the window keeps TwinKeys in the notification area (it always does; kept for the Mac's key).</summary>
    public bool TrayOnly { get; set; }

    /// <summary>iPhones / iPads allowed to control Live through this computer (TwinKeys Remote, phase 3).</summary>
    public List<ApprovedDevice> ApprovedDevices { get; set; } = [];
    /// <summary>Wait for TwinKeys Remote on the network. Off until the person turns it on (as on the Mac).</summary>
    public bool RemoteEnabled { get; set; }

    // Windows only.
    public MidiOutputMode MidiMode { get; set; } = MidiOutputMode.Loopback;
    public string MidiPortName { get; set; } = "TwinKeys";
    /// <summary>The first-run MIDI setup was finished or skipped.</summary>
    public bool FirstRunDone { get; set; }
    public string HotkeyKeyCapture { get; set; } = "Ctrl+Alt+K";
    public string HotkeyAllNotesOff { get; set; } = "Ctrl+Alt+P";
    /// <summary>Closing the window keeps TwinKeys running in the notification area (as on the Mac).</summary>
    public bool CloseToTray { get; set; } = true;
    /// <summary>Live's User Library chosen by the person (null: the default Documents\Ableton\User Library). Phase 2.</summary>
    public string? LiveUserLibrary { get; set; }

    /// <summary>Swift's Date reference (Codable dates are seconds since 2001-01-01 UTC).</summary>
    private static readonly DateTimeOffset Reference2001 = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public AppSettings Clone() => FromJson(ToJson())!;

    // MARK: JSON (by hand, so one bad value never loses the whole file, as on the Mac)

    public string ToJson()
    {
        var o = new JsonObject
        {
            ["version"] = Version,
            ["instance_id"] = GuidBytes.ToSwiftString(InstanceId),
            ["send_keys"] = SendKeys,
            ["receive_notes"] = ReceiveNotes,
            ["key_capture"] = KeyCapture,
            ["auto_note_off_seconds"] = AutoNoteOffSeconds,
            ["midi_channel"] = MidiChannel,
            ["last_peer_id"] = LastPeerId,
            ["language"] = Language,
            ["manual_address"] = ManualAddress,
            ["cue_keys"] = new JsonArray(CueKeys.Select(k => (JsonNode)new JsonObject
            {
                ["key"] = KeyIds.ToSetting(k.KeyCode),
                ["label"] = k.Label,
                ["memo"] = k.Memo,
                ["note"] = (int)k.Note,
            }).ToArray()),
            ["block_cue_keys"] = BlockCueKeys,
            ["auto_update"] = AutoUpdate,
            ["tray_only"] = TrayOnly,
            // The Mac's keys and shape (Codable ApprovedDevice: Data as Base64, Date as seconds since 2001).
            ["approved_devices"] = new JsonArray(ApprovedDevices.Select(d => (JsonNode)new JsonObject
            {
                ["id"] = d.Id,
                ["name"] = d.Name,
                ["publicKey"] = Convert.ToBase64String(d.PublicKey),
                ["approvedAt"] = (d.ApprovedAt - Reference2001).TotalSeconds,
            }).ToArray()),
            ["remote_enabled"] = RemoteEnabled,
            ["windows"] = new JsonObject
            {
                ["midi_output"] = new JsonObject
                {
                    ["mode"] = MidiMode switch { MidiOutputMode.VirtualDevice => "virtual_device", MidiOutputMode.BridgeOnly => "bridge_only", _ => "loopback" },
                    ["port_name"] = MidiPortName,
                },
                ["first_run_done"] = FirstRunDone,
                ["close_to_tray"] = CloseToTray,
                ["live"] = new JsonObject { ["user_library"] = LiveUserLibrary },
                ["hotkeys"] = new JsonObject { ["key_capture"] = HotkeyKeyCapture, ["all_notes_off"] = HotkeyAllNotesOff },
            },
        };
        return o.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
    }

    /// <summary>Missing or bad values fall back to defaults. Null only if the text is not a JSON object at all.</summary>
    public static AppSettings? FromJson(string json)
    {
        JsonObject? o;
        try { o = JsonNode.Parse(json) as JsonObject; }
        catch (JsonException) { return null; }
        if (o is null) return null;
        var s = new AppSettings();
        s.Version = Int(o, "version") ?? s.Version;
        if (Str(o, "instance_id") is string id && Guid.TryParse(id, out var g)) s.InstanceId = g;
        s.SendKeys = Bool(o, "send_keys") ?? s.SendKeys;
        s.ReceiveNotes = Bool(o, "receive_notes") ?? s.ReceiveNotes;
        s.KeyCapture = Bool(o, "key_capture") ?? s.KeyCapture;
        s.AutoNoteOffSeconds = Math.Clamp(Dbl(o, "auto_note_off_seconds") ?? s.AutoNoteOffSeconds, 0, 3600);
        s.MidiChannel = Math.Clamp(Int(o, "midi_channel") ?? s.MidiChannel, 1, 16);
        s.LastPeerId = Str(o, "last_peer_id");
        var lang = Str(o, "language") ?? "system";
        s.Language = lang is "system" or "en" or "ja" ? lang : "system";
        s.ManualAddress = Str(o, "manual_address");
        if (o["cue_keys"] is JsonArray arr)
        {
            var keys = new List<CueKey>();
            foreach (var item in arr)
            {
                // One unreadable entry drops only that entry, not the whole list.
                if (item is not JsonObject k) continue;
                var code = KeyIds.FromSetting(Str(k, "key"));
                var note = Int(k, "note");
                if (code is not ushort c || note is not int n || n is < 0 or > 127) continue;
                keys.Add(new CueKey(c, Str(k, "label") ?? KeyIds.Label(c), Str(k, "memo") ?? "", (byte)n));
            }
            s.CueKeys = CueKey.Sanitized(keys);
        }
        s.BlockCueKeys = Bool(o, "block_cue_keys") ?? s.BlockCueKeys;
        s.AutoUpdate = Bool(o, "auto_update") ?? s.AutoUpdate;
        s.TrayOnly = Bool(o, "tray_only") ?? s.TrayOnly;
        if (o["approved_devices"] is JsonArray devices)
        {
            foreach (var item in devices)
            {
                // One unreadable entry drops only that entry.
                if (item is not JsonObject d || Str(d, "id") is not string did || did.Length == 0 || Str(d, "publicKey") is not string pk) continue;
                byte[] key;
                try { key = Convert.FromBase64String(pk); } catch (FormatException) { continue; }
                if (key.Length != 32) continue;
                s.ApprovedDevices.Add(new ApprovedDevice(did, Str(d, "name") ?? "iPhone", key, Reference2001.AddSeconds(Dbl(d, "approvedAt") ?? 0)));
            }
        }
        s.RemoteEnabled = Bool(o, "remote_enabled") ?? s.RemoteEnabled;
        if (o["windows"] is JsonObject w)
        {
            if (w["midi_output"] is JsonObject m)
            {
                s.MidiMode = Str(m, "mode") switch { "virtual_device" => MidiOutputMode.VirtualDevice, "bridge_only" => MidiOutputMode.BridgeOnly, _ => MidiOutputMode.Loopback };
                var port = Str(m, "port_name");
                if (!string.IsNullOrWhiteSpace(port)) s.MidiPortName = port;
            }
            s.FirstRunDone = Bool(w, "first_run_done") ?? false;
            s.CloseToTray = Bool(w, "close_to_tray") ?? true;
            if (w["live"] is JsonObject lv && Str(lv, "user_library") is string ul && !string.IsNullOrWhiteSpace(ul)) s.LiveUserLibrary = ul;
            if (w["hotkeys"] is JsonObject h)
            {
                s.HotkeyKeyCapture = Str(h, "key_capture") ?? s.HotkeyKeyCapture;
                s.HotkeyAllNotesOff = Str(h, "all_notes_off") ?? s.HotkeyAllNotesOff;
            }
        }
        return s;
    }

    private static T? Get<T>(JsonObject o, string key) where T : struct
    {
        try { return o[key] is JsonValue v && v.TryGetValue<T>(out var x) ? x : null; }
        catch (InvalidOperationException) { return null; }
    }

    private static int? Int(JsonObject o, string key) => Get<int>(o, key) ?? (Get<double>(o, key) is double d && d == Math.Floor(d) && Math.Abs(d) < int.MaxValue ? (int)d : null);
    private static double? Dbl(JsonObject o, string key) => Get<double>(o, key);
    private static bool? Bool(JsonObject o, string key) => Get<bool>(o, key);
    private static string? Str(JsonObject o, string key)
    {
        try { return o[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null; }
        catch (InvalidOperationException) { return null; }
    }
}

/// <summary>
/// Loads and saves settings.json (per user: %LOCALAPPDATA%\TwinKeys on Windows). A file that cannot
/// be read is kept as settings.broken-&lt;time&gt;.json and defaults are used, as on the Mac.
/// </summary>
public sealed class SettingsStore(string directory)
{
    public string Directory { get; } = directory;
    public string SettingsFile => Path.Combine(Directory, "settings.json");
    public string LogsDirectory => Path.Combine(Directory, "Logs");

    public static string DefaultDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TwinKeys");

    /// <summary>Returns the settings and, when the file was broken, the name of the kept copy.</summary>
    public (AppSettings Settings, string? BrokenCopy) Load()
    {
        if (File.Exists(SettingsFile))
        {
            string? text = null;
            try { text = File.ReadAllText(SettingsFile); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            if (text is not null && AppSettings.FromJson(text) is AppSettings s) return (s, null);
            var backup = Path.Combine(Directory, $"settings.broken-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.json");
            try { File.Move(SettingsFile, backup, overwrite: false); } catch (IOException) { }
            var d = new AppSettings();
            TrySave(d);
            return (d, Path.GetFileName(backup));
        }
        var fresh = new AppSettings();
        TrySave(fresh);
        return (fresh, null);
    }

    public void Save(AppSettings s)
    {
        System.IO.Directory.CreateDirectory(Directory);
        var tmp = SettingsFile + ".tmp";
        File.WriteAllText(tmp, s.ToJson());
        File.Move(tmp, SettingsFile, overwrite: true);
    }

    public bool TrySave(AppSettings s)
    {
        try { Save(s); return true; }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }
}
