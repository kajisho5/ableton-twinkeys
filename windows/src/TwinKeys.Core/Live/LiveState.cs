using System.Text.Json.Nodes;

namespace TwinKeys.Core;

// Port of the state part of Sources/TwinKeysCore/LiveModel.swift: what TwinKeysBridge tells about
// Live (LiveBridge/README.md, "State messages"). Phase 2 uses the song row (structure, counts,
// bridge version) and the track and scene names (set check); phase 3 sends the rest to the iPhone.

public sealed record LiveSong
{
    public double Tempo { get; init; } = 120;
    public bool Playing { get; init; }
    public string Beat { get; init; } = "1.1.1";
    public int SelectedTrack { get; init; }
    public int SelectedScene { get; init; }
    public string SetName { get; init; } = "";
    /// <summary>Number of tracks and scenes in Live (rows beyond them are dropped).</summary>
    public int? TrackCount { get; init; }
    public int? SceneCount { get; init; }
    /// <summary>Rises whenever Live's track or scene list changes (null from older scripts).</summary>
    public int? Structure { get; init; }
    /// <summary>Version of the TwinKeysBridge script Live is running (null: older than 2.2).</summary>
    public int? BridgeVersion { get; init; }
}

public sealed record LiveScene(int Index, string Name, string Color = "#888888", bool Triggered = false, bool Playing = false);

public sealed record LiveTrack(int Index, string Name, string Color = "#888888", double Volume = 0.85, double Pan = 0,
    bool Mute = false, bool Solo = false, int PlayingSlot = -1, int FiredSlot = -1, IReadOnlyList<double>? Sends = null)
{
    public IReadOnlyList<double> SendList => Sends ?? [];
}

public sealed record LiveClip(int Scene, bool HasClip, string Name = "", string Color = "#888888",
    bool IsPlaying = false, bool IsTriggered = false, double LengthBeats = 0);

public sealed record MasterStrip(double Volume = 0.85, double Pan = 0);

/// <summary>A change of the Live state (sent to the iPhone in phase 3).</summary>
public abstract record LiveUpdate
{
    private LiveUpdate() { }
    public sealed record Song(LiveSong Value) : LiveUpdate;
    public sealed record Scenes(IReadOnlyList<LiveScene> Items) : LiveUpdate;
    public sealed record Tracks(IReadOnlyList<LiveTrack> Items, MasterStrip Master) : LiveUpdate;
    public sealed record Clips(int Track, IReadOnlyList<LiveClip> Items) : LiveUpdate;
    public sealed record Meters(IReadOnlyDictionary<int, double[]> Items, double[] Master) : LiveUpdate;
    public sealed record Progress(IReadOnlyDictionary<int, double[]> Items) : LiveUpdate;
}

/// <summary>Everything known about this computer's Live, kept from TwinKeysBridge messages. Not thread-safe (the BridgeClient locks it).</summary>
public sealed class LiveState
{
    public LiveSong Song { get; private set; } = new();
    public List<LiveScene> Scenes { get; } = [];
    public List<LiveTrack> Tracks { get; } = [];
    public MasterStrip Master { get; private set; } = new();
    /// <summary>Clips[track][scene].</summary>
    public List<List<LiveClip>> Clips { get; } = [];
    public Dictionary<int, double[]> Meters { get; private set; } = [];
    public double[] MasterMeter { get; private set; } = [0, 0];
    public Dictionary<int, double[]> Progress { get; private set; } = [];

    public LiveState Copy()
    {
        var c = new LiveState { Song = Song, Master = Master, MasterMeter = [.. MasterMeter] };
        c.Scenes.AddRange(Scenes);
        c.Tracks.AddRange(Tracks);
        foreach (var col in Clips) c.Clips.Add([.. col]);
        c.Meters = Meters.ToDictionary(kv => kv.Key, kv => kv.Value.ToArray());
        c.Progress = Progress.ToDictionary(kv => kv.Key, kv => kv.Value.ToArray());
        return c;
    }

    private static double? D(JsonObject o, string k) => o[k] is JsonValue v && v.TryGetValue(out double d) ? d : null;
    private static int? I(JsonObject o, string k)
    {
        if (o[k] is not JsonValue v) return null;
        if (v.TryGetValue(out int i)) return i;
        if (v.TryGetValue(out double d) && double.IsFinite(d) && d >= int.MinValue && d <= int.MaxValue) return (int)d;
        return null;
    }
    private static bool B(JsonObject o, string k)
    {
        if (o[k] is not JsonValue v) return false;
        if (v.TryGetValue(out bool b)) return b;
        return v.TryGetValue(out double d) && d != 0;
    }
    private static string S(JsonObject o, string k)
    {
        var s = o[k] is JsonValue v && v.TryGetValue(out string? x) ? x ?? "" : "";
        // Swift's prefix(200) counts characters (grapheme clusters); text elements are the same idea.
        var info = new System.Globalization.StringInfo(s);
        return info.LengthInTextElements > 200 ? info.SubstringByTextElements(0, 200) : s;
    }
    private static double? Num(JsonNode? n) => n is JsonValue v && v.TryGetValue(out double d) ? d : null;

    /// <summary>Applies one message from TwinKeysBridge. Returns the update, or null when it is not understood.</summary>
    public LiveUpdate? Apply(JsonObject m)
    {
        string? type = m["type"] is JsonValue tv && tv.TryGetValue(out string? tx) ? tx : null;
        switch (type)
        {
            case "song":
                {
                    var x = Song with
                    {
                        Tempo = D(m, "tempo") ?? Song.Tempo,
                        Playing = B(m, "playing"),
                        Beat = S(m, "beat"),
                        SelectedTrack = I(m, "selected_track") ?? Song.SelectedTrack,
                        SelectedScene = I(m, "selected_scene") ?? Song.SelectedScene,
                        SetName = S(m, "set_name"),
                    };
                    if (I(m, "tracks") is int nt && nt is >= 0 and <= 4096) x = x with { TrackCount = nt };
                    if (I(m, "scenes") is int ns && ns is >= 0 and <= 4096) x = x with { SceneCount = ns };
                    if (I(m, "structure") is int st) x = x with { Structure = st };
                    if (I(m, "bridge_version") is int bv) x = x with { BridgeVersion = bv };
                    Song = x;
                    Trim();
                    return new LiveUpdate.Song(x);
                }
            case "scenes":
                {
                    if (m["items"] is not JsonArray items) return null;
                    var list = new List<LiveScene>();
                    foreach (var o in items.OfType<JsonObject>())
                    {
                        if (I(o, "index") is not int idx || idx is < 0 or > 4095) continue;
                        var sc = new LiveScene(idx, S(o, "name"), S(o, "color"), B(o, "triggered"), B(o, "playing"));
                        while (Scenes.Count <= idx) Scenes.Add(new LiveScene(Scenes.Count, ""));
                        Scenes[idx] = sc;
                        list.Add(sc);
                    }
                    return new LiveUpdate.Scenes(list);
                }
            case "tracks":
                {
                    if (m["items"] is not JsonArray items) return null;
                    if (m["master"] is JsonObject mo) Master = new MasterStrip(D(mo, "volume") ?? Master.Volume, D(mo, "pan") ?? Master.Pan);
                    var list = new List<LiveTrack>();
                    foreach (var o in items.OfType<JsonObject>())
                    {
                        if (I(o, "index") is not int idx || idx is < 0 or > 4095) continue;
                        // Send A and Send B; stops at the first entry that is not a number, so B never moves into A.
                        var sends = new List<double>();
                        if (o["sends"] is JsonArray sa)
                            foreach (var n in sa.Take(2))
                            {
                                if (Num(n) is not double v || !double.IsFinite(v)) break;
                                sends.Add(Math.Clamp(v, 0, 1));
                            }
                        var tr = new LiveTrack(idx, S(o, "name"), S(o, "color"), D(o, "volume") ?? 0, D(o, "pan") ?? 0, B(o, "mute"), B(o, "solo"),
                            I(o, "playing_slot") ?? -1, I(o, "fired_slot") ?? -1, sends);
                        while (Tracks.Count <= idx) Tracks.Add(new LiveTrack(Tracks.Count, ""));
                        Tracks[idx] = tr;
                        list.Add(tr);
                    }
                    return new LiveUpdate.Tracks(list, Master);
                }
            case "clips":
                {
                    if (I(m, "track") is not int t || t is < 0 or > 4095 || m["items"] is not JsonArray items) return null;
                    while (Clips.Count <= t) Clips.Add([]);
                    var list = new List<LiveClip>();
                    foreach (var o in items.OfType<JsonObject>())
                    {
                        if (I(o, "scene") is not int sc || sc is < 0 or > 4095) continue;
                        var c = new LiveClip(sc, B(o, "has_clip"), S(o, "name"), S(o, "color"), B(o, "is_playing"), B(o, "is_triggered"), D(o, "length_beats") ?? 0);
                        while (Clips[t].Count <= sc) Clips[t].Add(new LiveClip(Clips[t].Count, false));
                        Clips[t][sc] = c;
                        list.Add(c);
                    }
                    return new LiveUpdate.Clips(t, list);
                }
            case "meters":
                {
                    if (m["items"] is not JsonArray items) return null;
                    foreach (var row in items.OfType<JsonArray>())
                    {
                        if (row.Count < 3) continue;
                        if (Num(row[0]) is double t && Num(row[1]) is double l && Num(row[2]) is double r && double.IsFinite(t)) Meters[(int)t] = [l, r];
                    }
                    if (m["master"] is JsonArray mm && mm.Count >= 2 && Num(mm[0]) is double a && Num(mm[1]) is double b) MasterMeter = [a, b];
                    return new LiveUpdate.Meters(Meters.ToDictionary(kv => kv.Key, kv => kv.Value), MasterMeter);
                }
            case "progress":
                {
                    if (m["items"] is not JsonArray items) return null;
                    var p = new Dictionary<int, double[]>();
                    foreach (var row in items.OfType<JsonArray>())
                    {
                        if (row.Count < 3) continue;
                        if (Num(row[0]) is double t && Num(row[1]) is double pos && Num(row[2]) is double len && double.IsFinite(t)) p[(int)t] = [pos, len];
                    }
                    Progress = p;
                    return new LiveUpdate.Progress(p);
                }
            default:
                return null;
        }
    }

    /// <summary>Drops tracks, scenes, clips, meters and progress beyond Live's current counts.</summary>
    private void Trim()
    {
        if (Song.TrackCount is int n)
        {
            if (Tracks.Count > n) Tracks.RemoveRange(n, Tracks.Count - n);
            if (Clips.Count > n) Clips.RemoveRange(n, Clips.Count - n);
            Meters = Meters.Where(kv => kv.Key < n).ToDictionary();
            Progress = Progress.Where(kv => kv.Key < n).ToDictionary();
        }
        if (Song.SceneCount is int s)
        {
            if (Scenes.Count > s) Scenes.RemoveRange(s, Scenes.Count - s);
            foreach (var col in Clips) if (col.Count > s) col.RemoveRange(s, col.Count - s);
        }
    }
}
