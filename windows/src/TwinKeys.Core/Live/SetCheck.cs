using System.Text;

namespace TwinKeys.Core;

// Port of Sources/TwinKeysCore/SetCheck.swift (2.1): comparing the Live sets open on the two
// computers (track and scene names only). The hash must be the Mac's to the bit, so a Mac and a
// Windows PC with the same set agree (shared/test-vectors/setcheck.json).

/// <summary>This computer's set: track and scene names, each cut to <see cref="MaxNameBytes"/> UTF-8 bytes.</summary>
public sealed class SetSummary : IEquatable<SetSummary>
{
    public IReadOnlyList<string> Tracks { get; }
    public IReadOnlyList<string> Scenes { get; }

    /// <summary>Names are cut to this many UTF-8 bytes on both sides, so long names still compare equal.</summary>
    public const int MaxNameBytes = 60;

    public SetSummary(IEnumerable<string> tracks, IEnumerable<string> scenes)
    {
        Tracks = tracks.Select(Cut).ToList();
        Scenes = scenes.Select(Cut).ToList();
    }

    public static SetSummary Of(LiveState s) => new(s.Tracks.Select(t => t.Name), s.Scenes.Select(x => x.Name));

    internal static string Cut(string name) => Utf8Text.TruncateString(name, MaxNameBytes);

    /// <summary>FNV-1a over the counts and every name (tracks, then scenes).</summary>
    public uint Hash
    {
        get
        {
            uint h = 2_166_136_261;
            void Add(ReadOnlySpan<byte> bytes) { foreach (var b in bytes) h = unchecked((h ^ b) * 16_777_619); }
            void AddU32(int v) { var u = (uint)v; Add([(byte)(u >> 24), (byte)(u >> 16), (byte)(u >> 8), (byte)u]); }
            AddU32(Tracks.Count);
            AddU32(Scenes.Count);
            foreach (var n in Tracks) { Add(Encoding.UTF8.GetBytes(n)); Add([0x1F]); }
            Add([0x1E]);
            foreach (var n in Scenes) { Add(Encoding.UTF8.GetBytes(n)); Add([0x1F]); }
            return h;
        }
    }

    public bool Equals(SetSummary? o) => o is not null && Tracks.SequenceEqual(o.Tracks) && Scenes.SequenceEqual(o.Scenes);
    public override bool Equals(object? obj) => Equals(obj as SetSummary);
    public override int GetHashCode() => (int)Hash;
}

public enum SetItemKind : byte { Track = 0, Scene = 1 }

/// <summary>The other computer's set as far as its names have arrived.</summary>
public sealed class PeerSet
{
    public int TrackCount { get; private set; }
    public int SceneCount { get; private set; }
    public uint Hash { get; private set; }
    public Dictionary<int, string> Tracks { get; private set; } = [];
    public Dictionary<int, string> Scenes { get; private set; } = [];

    /// <summary>A summary arrived: forget names beyond the new counts (a set with fewer rows was opened).</summary>
    public void Summary(int tracks, int scenes, uint hash)
    {
        if (hash != Hash || tracks != TrackCount || scenes != SceneCount)
        {
            Tracks = Tracks.Where(kv => kv.Key < tracks).ToDictionary();
            Scenes = Scenes.Where(kv => kv.Key < scenes).ToDictionary();
        }
        TrackCount = tracks; SceneCount = scenes; Hash = hash;
    }

    public void Item(SetItemKind kind, int index, string name)
    {
        switch (kind)
        {
            case SetItemKind.Track: if (index < TrackCount) Tracks[index] = name; break;
            case SetItemKind.Scene: if (index < SceneCount) Scenes[index] = name; break;
        }
    }

    /// <summary>All names up to the counts have arrived.</summary>
    public bool IsComplete => Tracks.Count >= TrackCount && Scenes.Count >= SceneCount;
}

/// <summary>How this computer's set differs from the other computer's.</summary>
public sealed record SetDiff(int MainTracks, int BackupTracks, int MainScenes, int BackupScenes, int Differences,
    IReadOnlyList<SetDiff.Row> Rows, bool Complete)
{
    /// <summary><paramref name="Main"/> is this computer's name (null: no such row), <paramref name="Backup"/> the other's (null: none, or not arrived).</summary>
    public sealed record Row(string Kind, int Index, string? Main, string? Backup);

    public const int MaxRows = 30;

    /// <summary>null when the two sets have the same names (or the other computer has not told its set yet).</summary>
    public static SetDiff? Compare(SetSummary mine, PeerSet? peer)
    {
        if (peer is null || (peer.TrackCount == 0 && peer.SceneCount == 0 && peer.Hash == 0)) return null;
        if (peer.Hash == mine.Hash && peer.TrackCount == mine.Tracks.Count && peer.SceneCount == mine.Scenes.Count) return null;
        var rows = new List<Row>();
        int differences = 0;
        void Scan(string kind, IReadOnlyList<string> local, Dictionary<int, string> remote, int remoteCount)
        {
            for (int i = 0; i < Math.Max(local.Count, remoteCount); i++)
            {
                string? a = i < local.Count ? local[i] : null;
                string? b = i < remoteCount ? remote.GetValueOrDefault(i) : null;
                // A row whose name has not arrived yet is not counted as different.
                if (i < remoteCount && b is null) continue;
                if (a != b)
                {
                    differences++;
                    if (rows.Count < MaxRows) rows.Add(new Row(kind, i, a, b));
                }
            }
        }
        Scan("track", mine.Tracks, peer.Tracks, peer.TrackCount);
        Scan("scene", mine.Scenes, peer.Scenes, peer.SceneCount);
        return new SetDiff(mine.Tracks.Count, peer.TrackCount, mine.Scenes.Count, peer.SceneCount, differences, rows, peer.IsComplete);
    }
}
