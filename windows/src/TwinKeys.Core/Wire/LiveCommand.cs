using System.Buffers;
using System.Buffers.Binary;
using System.Text.Json;

namespace TwinKeys.Core;

/// <summary>
/// A Live command forwarded between the two computers (packet 0x18). Port of LiveCommand in
/// Sources/TwinKeysCore/LiveModel.swift: the binary form, the range checks and the TwinKeysBridge
/// JSON (run by <see cref="BridgeClient"/>).
/// </summary>
public abstract record LiveCommand
{
    private LiveCommand() { }

    public sealed record FireScene(int Scene) : LiveCommand;
    public sealed record FireClip(int Track, int Scene) : LiveCommand;
    public sealed record StopTrack(int Track) : LiveCommand;
    public sealed record StopAll : LiveCommand;
    public sealed record Play : LiveCommand;
    public sealed record Stop : LiveCommand;
    public sealed record ContinuePlaying : LiveCommand;
    public sealed record SetTempo(double Bpm) : LiveCommand;
    public sealed record SetVolume(int Track, double Value) : LiveCommand;
    public sealed record SetPan(int Track, double Value) : LiveCommand;
    public sealed record SetSend(int Track, int Send, double Value) : LiveCommand;
    public sealed record SetMute(int Track, bool On) : LiveCommand;
    public sealed record SetSolo(int Track, bool On) : LiveCommand;
    public sealed record SelectScene(int Scene) : LiveCommand;

    /// <summary>Continuous controls: only the latest value matters (no resend of old values).</summary>
    public bool IsContinuous => this is SetVolume or SetPan or SetSend or SetTempo;

    /// <summary>Range checks before anything is used (values from the network are not trusted).</summary>
    public bool IsValid
    {
        get
        {
            static bool Idx(int i) => i is >= 0 and <= 9999;
            static bool Unit(double v) => double.IsFinite(v) && v >= 0 && v <= 1;
            return this switch
            {
                FireScene s => Idx(s.Scene),
                SelectScene s => Idx(s.Scene),
                FireClip c => Idx(c.Track) && Idx(c.Scene),
                StopTrack t => Idx(t.Track),
                StopAll or Play or Stop or ContinuePlaying => true,
                SetTempo t => double.IsFinite(t.Bpm) && t.Bpm >= 20 && t.Bpm <= 999,
                SetVolume v => (v.Track == -1 || Idx(v.Track)) && Unit(v.Value),
                SetPan p => (p.Track == -1 || Idx(p.Track)) && double.IsFinite(p.Value) && p.Value >= -1 && p.Value <= 1,
                SetSend s => Idx(s.Track) && s.Send is >= 0 and <= 1 && Unit(s.Value),
                SetMute m => Idx(m.Track),
                SetSolo m => Idx(m.Track),
                _ => false,
            };
        }
    }

    public byte[] Encode()
    {
        static byte[] I16(int v) { var u = unchecked((ushort)v); return [(byte)(u >> 8), (byte)(u & 0xFF)]; }
        static byte[] F64(double v) { var b = new byte[8]; BinaryPrimitives.WriteDoubleBigEndian(b, v); return b; }
        static byte[] B(bool on) => [on ? (byte)1 : (byte)0];
        return this switch
        {
            FireScene s => [1, .. I16(s.Scene)],
            FireClip c => [2, .. I16(c.Track), .. I16(c.Scene)],
            StopTrack t => [3, .. I16(t.Track)],
            StopAll => [4],
            Play => [5],
            Stop => [6],
            ContinuePlaying => [7],
            SetTempo t => [8, .. F64(t.Bpm)],
            SetVolume v => [9, .. I16(v.Track), .. F64(v.Value)],
            SetPan p => [10, .. I16(p.Track), .. F64(p.Value)],
            SetMute m => [11, .. I16(m.Track), .. B(m.On)],
            SetSolo m => [12, .. I16(m.Track), .. B(m.On)],
            SelectScene s => [13, .. I16(s.Scene)],
            SetSend s => [14, .. I16(s.Track), unchecked((byte)s.Send), .. F64(s.Value)],
            _ => throw new InvalidOperationException("unknown command"),
        };
    }

    public static LiveCommand? Decode(ReadOnlySpan<byte> b)
    {
        if (b.Length == 0) return null;
        int? I16(ReadOnlySpan<byte> x, int i) => x.Length >= i + 2 ? BinaryPrimitives.ReadInt16BigEndian(x[i..]) : null;
        double? F64(ReadOnlySpan<byte> x, int i) => x.Length >= i + 8 ? BinaryPrimitives.ReadDoubleBigEndian(x[i..]) : null;
        LiveCommand? c = b[0] switch
        {
            1 => I16(b, 1) is int s ? new FireScene(s) : null,
            2 => I16(b, 1) is int t && I16(b, 3) is int s ? new FireClip(t, s) : null,
            3 => I16(b, 1) is int t ? new StopTrack(t) : null,
            4 => new StopAll(),
            5 => new Play(),
            6 => new Stop(),
            7 => new ContinuePlaying(),
            8 => F64(b, 1) is double v ? new SetTempo(v) : null,
            9 => I16(b, 1) is int t && F64(b, 3) is double v ? new SetVolume(t, v) : null,
            10 => I16(b, 1) is int t && F64(b, 3) is double v ? new SetPan(t, v) : null,
            11 => I16(b, 1) is int t && b.Length > 3 ? new SetMute(t, b[3] != 0) : null,
            12 => I16(b, 1) is int t && b.Length > 3 ? new SetSolo(t, b[3] != 0) : null,
            13 => I16(b, 1) is int s ? new SelectScene(s) : null,
            14 => I16(b, 1) is int t && F64(b, 4) is double v ? new SetSend(t, b[3], v) : null,
            _ => null,
        };
        return c is not null && c.IsValid ? c : null;
    }

    /// <summary>Aimed at a track or scene by its position (so it must not run after Live's layout changed).</summary>
    public bool TargetsLayout => this is not (Play or Stop or ContinuePlaying or SetTempo or StopAll);

    /// <summary>The JSON datagram for TwinKeysBridge, with the optional "structure" check (LiveBridge/README.md).</summary>
    public byte[] BridgeJsonBytes(int id, int? structure = null)
    {
        var buf = new ArrayBufferWriter<byte>();
        using (var w = new Utf8JsonWriter(buf))
        {
            w.WriteStartObject();
            foreach (var (k, v) in BridgeJson(id))
            {
                switch (v)
                {
                    case int i: w.WriteNumber(k, i); break;
                    case double d: w.WriteNumber(k, d); break;
                    case bool b: w.WriteBoolean(k, b); break;
                    case string s: w.WriteString(k, s); break;
                }
            }
            if (structure is int st) w.WriteNumber("structure", st);
            w.WriteEndObject();
        }
        return buf.WrittenSpan.ToArray();
    }

    /// <summary>The JSON command for the TwinKeysBridge script (LiveBridge/README.md).</summary>
    public Dictionary<string, object> BridgeJson(int id)
    {
        var d = new Dictionary<string, object> { ["id"] = id };
        switch (this)
        {
            case FireScene s: d["cmd"] = "fire_scene"; d["scene"] = s.Scene; break;
            case FireClip c: d["cmd"] = "fire_clip"; d["track"] = c.Track; d["scene"] = c.Scene; break;
            case StopTrack t: d["cmd"] = "stop_track"; d["track"] = t.Track; break;
            case StopAll: d["cmd"] = "stop_all"; break;
            case Play: d["cmd"] = "play"; break;
            case Stop: d["cmd"] = "stop"; break;
            case ContinuePlaying: d["cmd"] = "continue"; break;
            case SetTempo t: d["cmd"] = "set_tempo"; d["bpm"] = t.Bpm; break;
            case SetVolume v: d["cmd"] = "set_volume"; d["track"] = v.Track; d["value"] = v.Value; break;
            case SetPan p: d["cmd"] = "set_pan"; d["track"] = p.Track; d["value"] = p.Value; break;
            case SetSend s: d["cmd"] = "set_send"; d["track"] = s.Track; d["send"] = s.Send; d["value"] = s.Value; break;
            case SetMute m: d["cmd"] = "set_mute"; d["track"] = m.Track; d["on"] = m.On; break;
            case SetSolo m: d["cmd"] = "set_solo"; d["track"] = m.Track; d["on"] = m.On; break;
            case SelectScene s: d["cmd"] = "select_scene"; d["scene"] = s.Scene; break;
        }
        return d;
    }
}
