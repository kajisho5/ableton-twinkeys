using System.Text.Json.Nodes;

namespace TwinKeys.Core;

// Port of the message types in Sources/TwinKeysCore/RemoteChannel.swift and LiveModel.swift for
// TwinKeys Remote (phase 3). The iPhone app decodes what the Mac's JSONEncoder writes with Swift's
// synthesized Codable, so this file writes and reads exactly that shape (docs/design-windows.md 6.5):
//  - an enum case is {"caseName": {labels...}}; unlabeled values are "_0", "_1"; a case without
//    values is {"caseName": {}};
//  - nil optionals are left out; Data is Base64; [Int: X] is an object with the numbers as keys;
//  - struct keys are the Swift property names (camelCase).
// shared/test-vectors/remote.json holds what the Swift code writes; the C# tests compare with it.

/// Helpers for Swift's Codable JSON.
public static class SwiftJson
{
    public static JsonNode Num(double v) => JsonValue.Create(double.IsFinite(v) ? v : 0)!;
    public static JsonNode Num(int v) => JsonValue.Create(v)!;
    public static JsonObject Case(string name, JsonObject? payload = null) => new() { [name] = payload ?? new JsonObject() };

    public static (string Name, JsonObject Payload)? OneCase(JsonNode? n)
    {
        if (n is not JsonObject o || o.Count != 1) return null;
        var (k, v) = o.First();
        return v is JsonObject p ? (k, p) : null;
    }

    public static int? Int(JsonObject o, string k)
    {
        if (o[k] is not JsonValue v) return null;
        if (v.TryGetValue(out int i)) return i;
        if (v.TryGetValue(out long l) && l is >= int.MinValue and <= int.MaxValue) return (int)l;
        // Swift's Int decoding refuses 1.5 but accepts 2.0.
        if (v.TryGetValue(out double d) && d == Math.Floor(d) && d is >= int.MinValue and <= int.MaxValue) return (int)d;
        return null;
    }
    public static double? Dbl(JsonObject o, string k) => o[k] is JsonValue v && v.TryGetValue(out double d) ? d : null;
    public static bool? Bool(JsonObject o, string k) => o[k] is JsonValue v && v.TryGetValue(out bool b) ? b : null;
    public static string? Str(JsonObject o, string k) => o[k] is JsonValue v && v.TryGetValue(out string? s) ? s : null;
    public static byte[]? Data(JsonObject o, string k)
    {
        if (Str(o, k) is not string s) return null;
        try { return Convert.FromBase64String(s); }
        catch (FormatException) { return null; }
    }
    public static JsonArray Doubles(IEnumerable<double> v) => new(v.Select(x => (JsonNode?)Num(x)).ToArray());
}

// MARK: LiveCommand and the Live state in Codable form

public static class LiveCodable
{
    public static JsonObject Encode(LiveCommand c)
    {
        static JsonObject P(params (string K, JsonNode V)[] kv) { var o = new JsonObject(); foreach (var (k, v) in kv) o[k] = v; return o; }
        return c switch
        {
            LiveCommand.FireScene s => SwiftJson.Case("fireScene", P(("_0", SwiftJson.Num(s.Scene)))),
            LiveCommand.FireClip f => SwiftJson.Case("fireClip", P(("track", SwiftJson.Num(f.Track)), ("scene", SwiftJson.Num(f.Scene)))),
            LiveCommand.StopTrack t => SwiftJson.Case("stopTrack", P(("_0", SwiftJson.Num(t.Track)))),
            LiveCommand.StopAll => SwiftJson.Case("stopAll"),
            LiveCommand.Play => SwiftJson.Case("play"),
            LiveCommand.Stop => SwiftJson.Case("stop"),
            LiveCommand.ContinuePlaying => SwiftJson.Case("continuePlaying"),
            LiveCommand.SetTempo t => SwiftJson.Case("setTempo", P(("_0", SwiftJson.Num(t.Bpm)))),
            LiveCommand.SetVolume v => SwiftJson.Case("setVolume", P(("track", SwiftJson.Num(v.Track)), ("value", SwiftJson.Num(v.Value)))),
            LiveCommand.SetPan p => SwiftJson.Case("setPan", P(("track", SwiftJson.Num(p.Track)), ("value", SwiftJson.Num(p.Value)))),
            LiveCommand.SetSend s => SwiftJson.Case("setSend", P(("track", SwiftJson.Num(s.Track)), ("send", SwiftJson.Num(s.Send)), ("value", SwiftJson.Num(s.Value)))),
            LiveCommand.SetMute m => SwiftJson.Case("setMute", P(("track", SwiftJson.Num(m.Track)), ("on", JsonValue.Create(m.On)))),
            LiveCommand.SetSolo m => SwiftJson.Case("setSolo", P(("track", SwiftJson.Num(m.Track)), ("on", JsonValue.Create(m.On)))),
            LiveCommand.SelectScene s => SwiftJson.Case("selectScene", P(("_0", SwiftJson.Num(s.Scene)))),
            _ => throw new InvalidOperationException("unknown command"),
        };
    }

    /// <summary>null when it is not a command this version knows, or a value is missing.</summary>
    public static LiveCommand? Decode(JsonNode? n)
    {
        if (SwiftJson.OneCase(n) is not (string name, JsonObject p)) return null;
        int? I(string k) => SwiftJson.Int(p, k);
        double? D(string k) => SwiftJson.Dbl(p, k);
        bool? B(string k) => SwiftJson.Bool(p, k);
        return name switch
        {
            "fireScene" => I("_0") is int s ? new LiveCommand.FireScene(s) : null,
            "fireClip" => I("track") is int t && I("scene") is int s ? new LiveCommand.FireClip(t, s) : null,
            "stopTrack" => I("_0") is int t ? new LiveCommand.StopTrack(t) : null,
            "stopAll" => new LiveCommand.StopAll(),
            "play" => new LiveCommand.Play(),
            "stop" => new LiveCommand.Stop(),
            "continuePlaying" => new LiveCommand.ContinuePlaying(),
            "setTempo" => D("_0") is double b ? new LiveCommand.SetTempo(b) : null,
            "setVolume" => I("track") is int t && D("value") is double v ? new LiveCommand.SetVolume(t, v) : null,
            "setPan" => I("track") is int t && D("value") is double v ? new LiveCommand.SetPan(t, v) : null,
            "setSend" => I("track") is int t && I("send") is int k && D("value") is double v ? new LiveCommand.SetSend(t, k, v) : null,
            "setMute" => I("track") is int t && B("on") is bool on ? new LiveCommand.SetMute(t, on) : null,
            "setSolo" => I("track") is int t && B("on") is bool on ? new LiveCommand.SetSolo(t, on) : null,
            "selectScene" => I("_0") is int s ? new LiveCommand.SelectScene(s) : null,
            _ => null,
        };
    }

    public static JsonObject Encode(LiveSong s)
    {
        var o = new JsonObject
        {
            ["tempo"] = SwiftJson.Num(s.Tempo), ["playing"] = s.Playing, ["beat"] = s.Beat,
            ["selectedTrack"] = s.SelectedTrack, ["selectedScene"] = s.SelectedScene, ["setName"] = s.SetName,
        };
        if (s.TrackCount is int tc) o["trackCount"] = tc;
        if (s.SceneCount is int sc) o["sceneCount"] = sc;
        if (s.Structure is int st) o["structure"] = st;
        if (s.BridgeVersion is int bv) o["bridgeVersion"] = bv;
        return o;
    }

    public static JsonObject Encode(LiveScene s) => new()
    {
        ["index"] = s.Index, ["name"] = s.Name, ["color"] = s.Color, ["triggered"] = s.Triggered, ["playing"] = s.Playing,
    };

    public static JsonObject Encode(LiveTrack t) => new()
    {
        ["index"] = t.Index, ["name"] = t.Name, ["color"] = t.Color, ["volume"] = SwiftJson.Num(t.Volume), ["pan"] = SwiftJson.Num(t.Pan),
        ["mute"] = t.Mute, ["solo"] = t.Solo, ["playingSlot"] = t.PlayingSlot, ["firedSlot"] = t.FiredSlot, ["sends"] = SwiftJson.Doubles(t.SendList),
    };

    public static JsonObject Encode(LiveClip c) => new()
    {
        ["scene"] = c.Scene, ["hasClip"] = c.HasClip, ["name"] = c.Name, ["color"] = c.Color,
        ["isPlaying"] = c.IsPlaying, ["isTriggered"] = c.IsTriggered, ["lengthBeats"] = SwiftJson.Num(c.LengthBeats),
    };

    public static JsonObject Encode(MasterStrip m) => new() { ["volume"] = SwiftJson.Num(m.Volume), ["pan"] = SwiftJson.Num(m.Pan) };

    /// <summary>[Int: [Double]]: Swift writes an object whose keys are the numbers.</summary>
    public static JsonObject Encode(IReadOnlyDictionary<int, double[]> d)
    {
        var o = new JsonObject();
        foreach (var (k, v) in d.OrderBy(kv => kv.Key)) o[k.ToString(System.Globalization.CultureInfo.InvariantCulture)] = SwiftJson.Doubles(v);
        return o;
    }

    public static JsonObject Encode(LiveState s) => new()
    {
        ["song"] = Encode(s.Song),
        ["scenes"] = new JsonArray(s.Scenes.Select(x => (JsonNode?)Encode(x)).ToArray()),
        ["tracks"] = new JsonArray(s.Tracks.Select(x => (JsonNode?)Encode(x)).ToArray()),
        ["master"] = Encode(s.Master),
        ["clips"] = new JsonArray(s.Clips.Select(col => (JsonNode?)new JsonArray(col.Select(c => (JsonNode?)Encode(c)).ToArray())).ToArray()),
        ["meters"] = Encode(s.Meters),
        ["masterMeter"] = SwiftJson.Doubles(s.MasterMeter),
        ["progress"] = Encode(s.Progress),
    };

    public static JsonObject Encode(LiveUpdate u) => u switch
    {
        LiveUpdate.Full f => SwiftJson.Case("full", new JsonObject { ["_0"] = Encode(f.State) }),
        LiveUpdate.Song s => SwiftJson.Case("song", new JsonObject { ["_0"] = Encode(s.Value) }),
        LiveUpdate.Scenes s => SwiftJson.Case("scenes", new JsonObject { ["_0"] = new JsonArray(s.Items.Select(x => (JsonNode?)Encode(x)).ToArray()) }),
        LiveUpdate.Tracks t => SwiftJson.Case("tracks", new JsonObject
        {
            ["_0"] = new JsonArray(t.Items.Select(x => (JsonNode?)Encode(x)).ToArray()),
            ["_1"] = Encode(t.Master),
        }),
        LiveUpdate.Clips c => SwiftJson.Case("clips", new JsonObject
        {
            ["track"] = c.Track,
            ["_1"] = new JsonArray(c.Items.Select(x => (JsonNode?)Encode(x)).ToArray()),
        }),
        LiveUpdate.Meters m => SwiftJson.Case("meters", new JsonObject { ["_0"] = Encode(m.Items), ["_1"] = SwiftJson.Doubles(m.Master) }),
        LiveUpdate.Progress p => SwiftJson.Case("progress", new JsonObject { ["_0"] = Encode(p.Items) }),
        _ => throw new InvalidOperationException("unknown update"),
    };

    public static JsonObject Encode(SetDiff d) => new()
    {
        ["mainTracks"] = d.MainTracks, ["backupTracks"] = d.BackupTracks, ["mainScenes"] = d.MainScenes, ["backupScenes"] = d.BackupScenes,
        ["differences"] = d.Differences,
        ["rows"] = new JsonArray(d.Rows.Select(r =>
        {
            var o = new JsonObject { ["kind"] = r.Kind, ["index"] = r.Index };
            if (r.Main is not null) o["main"] = r.Main;
            if (r.Backup is not null) o["backup"] = r.Backup;
            return (JsonNode?)o;
        }).ToArray()),
        ["complete"] = d.Complete,
    };
}

// MARK: Hellos, status, the watch

public sealed record RemoteClientHello(int Version, string DeviceId, string DeviceName, byte[] DevicePublicKey, byte[] Nonce)
{
    public const int MaxNameLength = 64;

    public JsonObject ToJson() => new()
    {
        ["version"] = Version, ["deviceID"] = DeviceId, ["deviceName"] = DeviceName,
        ["devicePublicKey"] = Convert.ToBase64String(DevicePublicKey), ["nonce"] = Convert.ToBase64String(Nonce),
    };

    public static RemoteClientHello? FromJson(JsonNode? n)
    {
        if (n is not JsonObject o) return null;
        if (SwiftJson.Int(o, "version") is not int v || SwiftJson.Str(o, "deviceID") is not string id || SwiftJson.Str(o, "deviceName") is not string name
            || SwiftJson.Data(o, "devicePublicKey") is not byte[] key || SwiftJson.Data(o, "nonce") is not byte[] nonce) return null;
        return new RemoteClientHello(v, id, name, key, nonce);
    }

    /// <summary>
    /// A device name that is safe to show in a dialog or a log (port of sanitizedName): no control
    /// or invisible formatting characters (the zero-width joiner stays), trimmed, at most 64 characters.
    /// </summary>
    public static string SanitizedName(string name)
    {
        var sb = new System.Text.StringBuilder();
        foreach (var r in name.EnumerateRunes())
        {
            var cat = System.Text.Rune.GetUnicodeCategory(r);
            bool drop = cat is System.Globalization.UnicodeCategory.Control or System.Globalization.UnicodeCategory.Format
                or System.Globalization.UnicodeCategory.LineSeparator or System.Globalization.UnicodeCategory.ParagraphSeparator
                or System.Globalization.UnicodeCategory.Surrogate or System.Globalization.UnicodeCategory.OtherNotAssigned
                or System.Globalization.UnicodeCategory.PrivateUse;
            if (!drop || r.Value == 0x200D) sb.Append(r.ToString());
        }
        var s = sb.ToString().Trim(' ', '\t');
        var info = new System.Globalization.StringInfo(s);
        if (info.LengthInTextElements > MaxNameLength) s = info.SubstringByTextElements(0, MaxNameLength).Trim(' ', '\t');
        return s.Length == 0 ? "iPhone" : s;
    }
}

public sealed record RemoteServerHello(int Version, string ServerId, string ServerName, byte[] EphemeralPublicKey, byte[] Nonce)
{
    public JsonObject ToJson() => new()
    {
        ["version"] = Version, ["serverID"] = ServerId, ["serverName"] = ServerName,
        ["ephemeralPublicKey"] = Convert.ToBase64String(EphemeralPublicKey), ["nonce"] = Convert.ToBase64String(Nonce),
    };

    public static RemoteServerHello? FromJson(JsonNode? n)
    {
        if (n is not JsonObject o) return null;
        if (SwiftJson.Int(o, "version") is not int v || SwiftJson.Str(o, "serverID") is not string id || SwiftJson.Str(o, "serverName") is not string name
            || SwiftJson.Data(o, "ephemeralPublicKey") is not byte[] key || SwiftJson.Data(o, "nonce") is not byte[] nonce) return null;
        return new RemoteServerHello(v, id, name, key, nonce);
    }
}

/// <summary>The iPhone's Apple Watch as the iPhone reports it with each ping.</summary>
public sealed record RemoteWatchState(bool Paired, bool AppInstalled, bool Reachable)
{
    public WatchLevel Level => !Paired || !AppInstalled ? WatchLevel.Absent : Reachable ? WatchLevel.Reachable : WatchLevel.NotReachable;

    public JsonObject ToJson() => new() { ["paired"] = Paired, ["appInstalled"] = AppInstalled, ["reachable"] = Reachable };

    public static RemoteWatchState? FromJson(JsonNode? n) =>
        n is JsonObject o && SwiftJson.Bool(o, "paired") is bool p && SwiftJson.Bool(o, "appInstalled") is bool a && SwiftJson.Bool(o, "reachable") is bool r
            ? new RemoteWatchState(p, a, r) : null;
}

public enum WatchLevel : byte { Absent = 0, NotReachable = 1, Reachable = 2 }

/// <summary>Shown on the iPhone: the state of both computers.</summary>
public sealed record RemoteStatus(string MainName, bool MainLiveConnected, string? BackupName, bool BackupLinked, bool BackupLiveConnected,
    double? LatencyMs, RemoteStatus.CueSummary? LastCue, IReadOnlyList<RemoteStatus.CueKeySummary> CueKeys, SetDiff? SetDiff = null)
{
    /// <summary><paramref name="Delivery"/>: "delivered", "waiting", "missing", "unconfirmed", "notConnected", "received".</summary>
    public sealed record CueSummary(string Label, string Memo, int Count, string Delivery);
    public sealed record CueKeySummary(ushort Keycode, string Label, string Memo);

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["mainName"] = MainName, ["mainLiveConnected"] = MainLiveConnected };
        if (BackupName is not null) o["backupName"] = BackupName;
        o["backupLinked"] = BackupLinked;
        o["backupLiveConnected"] = BackupLiveConnected;
        if (LatencyMs is double ms) o["latencyMs"] = SwiftJson.Num(ms);
        if (LastCue is { } c) o["lastCue"] = new JsonObject { ["label"] = c.Label, ["memo"] = c.Memo, ["count"] = c.Count, ["delivery"] = c.Delivery };
        o["cueKeys"] = new JsonArray(CueKeys.Select(k => (JsonNode?)new JsonObject { ["keycode"] = (int)k.Keycode, ["label"] = k.Label, ["memo"] = k.Memo }).ToArray());
        if (SetDiff is not null) o["setDiff"] = LiveCodable.Encode(SetDiff);
        return o;
    }

    /// <summary>Same content (the records hold lists, which compare by reference).</summary>
    public bool SameAs(RemoteStatus? o) => o is not null && ToJson().ToJsonString() == o.ToJson().ToJsonString();
}

/// <summary>The approved iPhones connected to this computer and their watch (told to the other computer, packet remoteSummary).</summary>
public sealed record RemoteSummary(int Phones, WatchLevel Watch);

/// <summary>Message kinds a Mac may or may not understand (sent in welcome; RemoteFeature in Swift).</summary>
public static class RemoteFeature
{
    public const string CommandAt = "commandAt", Go = "go", LockScope = "lockScope", BecomeMain = "becomeMain", SkipsUnknown = "skipsUnknown";
    public static readonly string[] All = [CommandAt, Go, LockScope, BecomeMain, SkipsUnknown];
}

/// <summary>What the show lock stops (LockScope in LiveModel.swift).</summary>
[Flags]
public enum LockScope : byte
{
    None = 0, Tempo = 1, Mixer = 2, Launches = 4, Stops = 8, Cues = 16,
    Standard = Tempo | Mixer,
}

public static class LockRules
{
    public static LockScope Group(LiveCommand c) => c switch
    {
        LiveCommand.SetTempo => LockScope.Tempo,
        LiveCommand.SetVolume or LiveCommand.SetPan or LiveCommand.SetSend or LiveCommand.SetMute or LiveCommand.SetSolo => LockScope.Mixer,
        LiveCommand.FireScene or LiveCommand.FireClip or LiveCommand.Play or LiveCommand.ContinuePlaying => LockScope.Launches,
        LiveCommand.Stop or LiveCommand.StopAll or LiveCommand.StopTrack => LockScope.Stops,
        _ => LockScope.None,   // scene selection is never locked
    };

    public static bool Blocks(this LockScope scope, LiveCommand c) => (scope & Group(c)) != 0;
}

// MARK: Messages after the handshake

public abstract record RemoteMessage
{
    private RemoteMessage() { }

    // iPhone → computer
    public sealed record Command(int Id, LiveCommand Cmd) : RemoteMessage;
    public sealed record CommandAt(int Id, LiveCommand Cmd, int? Structure) : RemoteMessage;
    public sealed record Go(int Id, int Scene, int? Structure) : RemoteMessage;
    public sealed record LockScopeMsg(bool On, byte Scope) : RemoteMessage;
    public sealed record BecomeMain(int Id) : RemoteMessage;
    public sealed record Cue(int Id, ushort Keycode) : RemoteMessage;
    public sealed record AllNotesOff(int Id) : RemoteMessage;
    public sealed record Ping(double Time, RemoteWatchState? Watch = null) : RemoteMessage;
    public sealed record Lock(bool On) : RemoteMessage;
    // computer → iPhone
    public sealed record WaitingForApproval(string Code) : RemoteMessage;
    public sealed record Welcome(string MacName, IReadOnlyList<string>? Features = null) : RemoteMessage;
    public sealed record Denied : RemoteMessage;
    public sealed record Update(LiveUpdate Value) : RemoteMessage;
    public sealed record Status(RemoteStatus Value) : RemoteMessage;
    public sealed record Result(int Id, bool Ok, string? Error, string Backup) : RemoteMessage;
    public sealed record Pong(double Time) : RemoteMessage;

    public JsonObject ToJson()
    {
        JsonObject P(params (string K, JsonNode? V)[] kv) { var o = new JsonObject(); foreach (var (k, v) in kv) if (v is not null) o[k] = v; return o; }
        JsonNode? N(int? v) => v is int i ? JsonValue.Create(i) : null;
        return this switch
        {
            Command c => SwiftJson.Case("command", P(("id", c.Id), ("_1", LiveCodable.Encode(c.Cmd)))),
            CommandAt c => SwiftJson.Case("commandAt", P(("id", c.Id), ("_1", LiveCodable.Encode(c.Cmd)), ("structure", N(c.Structure)))),
            Go g => SwiftJson.Case("go", P(("id", g.Id), ("scene", g.Scene), ("structure", N(g.Structure)))),
            LockScopeMsg l => SwiftJson.Case("lockScope", P(("on", l.On), ("scope", (int)l.Scope))),
            BecomeMain b => SwiftJson.Case("becomeMain", P(("id", b.Id))),
            Cue c => SwiftJson.Case("cue", P(("id", c.Id), ("keycode", (int)c.Keycode))),
            AllNotesOff a => SwiftJson.Case("allNotesOff", P(("id", a.Id))),
            Ping p => SwiftJson.Case("ping", P(("_0", SwiftJson.Num(p.Time)), ("watch", p.Watch?.ToJson()))),
            Lock l => SwiftJson.Case("lock", P(("_0", l.On))),
            WaitingForApproval w => SwiftJson.Case("waitingForApproval", P(("code", w.Code))),
            Welcome w => SwiftJson.Case("welcome", P(("macName", w.MacName),
                ("features", w.Features is null ? null : new JsonArray(w.Features.Select(f => (JsonNode?)f).ToArray())))),
            Denied => SwiftJson.Case("denied"),
            Update u => SwiftJson.Case("update", P(("_0", LiveCodable.Encode(u.Value)))),
            Status s => SwiftJson.Case("status", P(("_0", s.Value.ToJson()))),
            Result r => SwiftJson.Case("result", P(("id", r.Id), ("ok", r.Ok), ("error", r.Error), ("backup", r.Backup))),
            Pong p => SwiftJson.Case("pong", P(("_0", SwiftJson.Num(p.Time)))),
            _ => throw new InvalidOperationException("unknown message"),
        };
    }

    /// <summary>
    /// Reads a message from the iPhone. null for a kind this version does not know or a bad value
    /// (the connection stays; the Mac 2.4 skips such messages too). Only the iPhone → computer kinds
    /// are read, plus the few the tests' fake iPhone needs.
    /// </summary>
    public static RemoteMessage? FromJson(JsonNode? n)
    {
        if (SwiftJson.OneCase(n) is not (string name, JsonObject p)) return null;
        int? I(string k) => SwiftJson.Int(p, k);
        switch (name)
        {
            case "command":
                return I("id") is int cid && LiveCodable.Decode(p["_1"]) is LiveCommand cc ? new Command(cid, cc) : null;
            case "commandAt":
                {
                    if (I("id") is not int id || LiveCodable.Decode(p["_1"]) is not LiveCommand c) return null;
                    if (p.ContainsKey("structure") && p["structure"] is not null && I("structure") is null) return null;
                    return new CommandAt(id, c, I("structure"));
                }
            case "go":
                {
                    if (I("id") is not int id || I("scene") is not int s) return null;
                    if (p.ContainsKey("structure") && p["structure"] is not null && I("structure") is null) return null;
                    return new Go(id, s, I("structure"));
                }
            case "lockScope":
                return SwiftJson.Bool(p, "on") is bool on && I("scope") is int sc && sc is >= 0 and <= 255 ? new LockScopeMsg(on, (byte)sc) : null;
            case "becomeMain": return I("id") is int b ? new BecomeMain(b) : null;
            case "cue": return I("id") is int ci && I("keycode") is int k && k is >= 0 and <= 0xFFFF ? new Cue(ci, (ushort)k) : null;
            case "allNotesOff": return I("id") is int a ? new AllNotesOff(a) : null;
            case "ping":
                {
                    if (SwiftJson.Dbl(p, "_0") is not double t) return null;
                    // A watch that cannot be read is left out (as Swift's decodeIfPresent would fail the whole
                    // message, the iPhone never sends one).
                    return new Ping(t, RemoteWatchState.FromJson(p["watch"]));
                }
            case "lock": return SwiftJson.Bool(p, "_0") is bool l ? new Lock(l) : null;
            // Computer → iPhone (read by the tests' fake iPhone).
            case "waitingForApproval": return SwiftJson.Str(p, "code") is string code ? new WaitingForApproval(code) : null;
            case "welcome":
                return SwiftJson.Str(p, "macName") is string mn
                    ? new Welcome(mn, p["features"] is JsonArray fa ? fa.Select(x => (string?)x ?? "").ToList() : null) : null;
            case "denied": return new Denied();
            case "result":
                return I("id") is int ri && SwiftJson.Bool(p, "ok") is bool ok && SwiftJson.Str(p, "backup") is string bk
                    ? new Result(ri, ok, SwiftJson.Str(p, "error"), bk) : null;
            case "pong": return SwiftJson.Dbl(p, "_0") is double pt ? new Pong(pt) : null;
            default: return null;
        }
    }
}

/// <summary>An iPhone this computer allowed (stored in settings; the key binds the approval to that device).</summary>
public sealed record ApprovedDevice(string Id, string Name, byte[] PublicKey, DateTimeOffset ApprovedAt)
{
    /// <summary>Approved only if both the id and the key match (a device cannot take over another's approval).</summary>
    public static bool IsApproved(RemoteClientHello hello, IEnumerable<ApprovedDevice> list) =>
        list.Any(d => d.Id == hello.DeviceId && System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(d.PublicKey, hello.DevicePublicKey));
}

/// <summary>
/// When to ask the person to approve a new device (port of RemoteApprovalGate). At most one question
/// at a time, each with a time limit; after "Don't Allow", no answer, or the device leaving while
/// asked, that device is refused without asking for <see cref="CoolDown"/> seconds.
/// </summary>
public sealed class RemoteApprovalGate
{
    public const double Timeout = 60;
    public const double CoolDown = 60;

    public abstract record Decision
    {
        private Decision() { }
        public sealed record Ask(int Token) : Decision;
        public sealed record Busy : Decision;
        public sealed record CoolingDown : Decision;
    }

    private (int Token, string DeviceId, double Since)? open;
    private Dictionary<string, double> refusedAt = [];
    private int lastToken;

    public int? OpenToken => open?.Token;

    public Decision Request(string deviceId, double now)
    {
        if (refusedAt.TryGetValue(deviceId, out var t))
        {
            if (now - t < CoolDown) return new Decision.CoolingDown();
            refusedAt.Remove(deviceId);
        }
        if (open is { } o)
        {
            if (now - o.Since < Timeout) return new Decision.Busy();
            Finish(o.Token, false, now);   // ran out of time (missed timer)
        }
        lastToken += 1;
        open = (lastToken, deviceId, now);
        return new Decision.Ask(lastToken);
    }

    /// <summary>The question ended. False when it is not the open question any more (an old answer is then ignored).</summary>
    public bool Finish(int token, bool allowed, double now)
    {
        if (open is not { } o || o.Token != token) return false;
        open = null;
        if (!allowed)
        {
            if (refusedAt.Count > 200) refusedAt = refusedAt.Where(kv => now - kv.Value < CoolDown).ToDictionary();
            refusedAt[o.DeviceId] = now;
        }
        return true;
    }

    public bool IsExpired(int token, double now) => open is { } o && o.Token == token && now - o.Since >= Timeout;
}
