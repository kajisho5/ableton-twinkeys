using System.Buffers.Binary;
using System.Text;

namespace TwinKeys.Core;

/// <summary>
/// TwinKeys UDP packet format (big-endian). Port of Sources/TwinKeysCore/WireProtocol.swift;
/// must stay byte-for-byte the same (checked against shared/test-vectors/packets.json).
/// <code>
///  0  'T' 'K'        magic
///  2  version (2: authenticated and encrypted, see SecureChannel)
///  3  type
///  4  session  u32   random per app launch; a new value resets sequence tracking
///  8  seq      u32   increases by 1 per packet
/// 12  payload
/// </code>
/// </summary>
public static class WireProtocol
{
    public const byte Version = 2;
    public const int HeaderSize = 12;
    public const int MaxPacketSize = 128;
    /// <summary>Maximum bytes of a peer name carried in hello packets.</summary>
    public const int MaxNameBytes = 32;
    /// <summary>Maximum notes listed in one held packet.</summary>
    public const int MaxHeldNotes = 32;
    /// <summary>Maximum bytes of a set item name (SetSummary.maxNameBytes in Swift).</summary>
    public const int MaxSetItemNameBytes = 40;
}

/// <summary>The payload of a packet. One nested record per packet type.</summary>
public abstract record PacketBody
{
    private PacketBody() { }

    /// <summary><paramref name="Nonce"/>: the sender's 16-byte per-launch value (part of the link keys).</summary>
    public sealed record Hello(Guid InstanceId, byte[] Nonce, string Name) : PacketBody;
    public sealed record HelloAck(Guid InstanceId, byte[] Nonce, string Name) : PacketBody;
    public sealed record Bye : PacketBody;
    public sealed record NoteOn(byte Channel, byte Note, byte Velocity) : PacketBody;
    public sealed record NoteOff(byte Channel, byte Note) : PacketBody;
    public sealed record AllNotesOff : PacketBody;
    public sealed record Heartbeat(ulong TimestampNanos) : PacketBody;
    public sealed record HeartbeatAck(ulong TimestampNanos) : PacketBody;
    /// <summary>Notes the sender's keys are still holding (sent with each heartbeat).</summary>
    public sealed record Held(byte Channel, byte[] Notes) : PacketBody;
    /// <summary>bit 0: cue delivery check; bit 1: just (re)connected. <paramref name="Epoch"/>: the sender's link counter (1.0.1+).</summary>
    public sealed record Features(byte Flags, byte? Epoch = null) : PacketBody;
    public sealed record NoteAck(uint Seq) : PacketBody;
    public sealed record CueName(byte Channel, byte Note, string Label, string Memo) : PacketBody;
    public sealed record CueResend(uint OriginalSeq, byte Channel, byte Note, byte Velocity, bool Released) : PacketBody;
    public sealed record CueCount(uint Seq, uint Count) : PacketBody;
    public sealed record LiveCommandPacket(uint Id, LiveCommand Command) : PacketBody;
    public sealed record LiveAck(uint Id) : PacketBody;
    public sealed record LiveStatus(bool Connected) : PacketBody;
    public sealed record SetSummary(ushort Tracks, ushort Scenes, uint Hash) : PacketBody;
    public sealed record SetItem(byte Kind, ushort Index, string Name) : PacketBody;
    public sealed record LiveResult(uint Id, byte Code) : PacketBody;
    /// <summary>"I am the main since this time" (wall clock, ms).</summary>
    public sealed record RoleClaim(ulong Millis) : PacketBody;
    public sealed record RoleHandover : PacketBody;
    public sealed record RemoteSummary(byte Phones, byte Watch) : PacketBody;
    /// <summary>
    /// Yamaha console sharing (Mac 2.4, packet 0x22). The Windows version does not implement it
    /// (docs/design-windows.md 1.4): the payload is kept as raw bytes and ignored.
    /// </summary>
    public sealed record Desk(byte[] Raw) : PacketBody;

    public byte TypeCode => this switch
    {
        Hello => 0x01,
        HelloAck => 0x02,
        Bye => 0x03,
        NoteOn => 0x10,
        NoteOff => 0x11,
        Held => 0x12,
        Features => 0x13,
        NoteAck => 0x14,
        CueName => 0x15,
        CueResend => 0x16,
        CueCount => 0x17,
        LiveCommandPacket => 0x18,
        LiveAck => 0x19,
        LiveStatus => 0x1A,
        SetSummary => 0x1B,
        SetItem => 0x1C,
        LiveResult => 0x1D,
        RoleClaim => 0x1E,
        RoleHandover => 0x1F,
        AllNotesOff => 0x20,
        RemoteSummary => 0x21,
        Desk => 0x22,
        Heartbeat => 0x30,
        HeartbeatAck => 0x31,
        _ => throw new InvalidOperationException("unknown packet body"),
    };

    public bool IsHelloOrAck => this is Hello or HelloAck;
}

public enum DecodeError { TooShort, BadMagic, UnsupportedVersion, UnknownType, BadPayload }

public sealed class PacketDecodeException(DecodeError error) : Exception($"Bad packet: {error}")
{
    public DecodeError Error { get; } = error;
}

public sealed record Packet(uint Session, uint Seq, PacketBody Body)
{
    public byte[] Encode()
    {
        var b = new List<byte>(64) { 0x54, 0x4B, WireProtocol.Version, Body.TypeCode };
        AppendBE(b, Session);
        AppendBE(b, Seq);
        switch (Body)
        {
            case PacketBody.Hello h: AppendHello(b, h.InstanceId, h.Nonce, h.Name); break;
            case PacketBody.HelloAck h: AppendHello(b, h.InstanceId, h.Nonce, h.Name); break;
            case PacketBody.Bye or PacketBody.AllNotesOff or PacketBody.RoleHandover: break;
            case PacketBody.NoteOn n: b.Add((byte)(n.Channel & 0x0F)); b.Add((byte)(n.Note & 0x7F)); b.Add((byte)(n.Velocity & 0x7F)); break;
            case PacketBody.NoteOff n: b.Add((byte)(n.Channel & 0x0F)); b.Add((byte)(n.Note & 0x7F)); break;
            case PacketBody.Heartbeat t: AppendBE(b, t.TimestampNanos); break;
            case PacketBody.HeartbeatAck t: AppendBE(b, t.TimestampNanos); break;
            case PacketBody.Held h:
                {
                    var list = h.Notes.Take(WireProtocol.MaxHeldNotes).ToArray();
                    b.Add((byte)(h.Channel & 0x0F));
                    b.Add((byte)list.Length);
                    foreach (var n in list) b.Add((byte)(n & 0x7F));
                    break;
                }
            case PacketBody.Features f:
                b.Add(f.Flags);
                if (f.Epoch is byte e) b.Add(e);
                break;
            case PacketBody.NoteAck a: AppendBE(b, a.Seq); break;
            case PacketBody.CueName c:
                {
                    var l = Utf8Text.Truncate(c.Label, CueKey.MaxLabelBytes);
                    var m = Utf8Text.Truncate(c.Memo, CueKey.MaxMemoBytes);
                    b.Add((byte)(c.Channel & 0x0F)); b.Add((byte)(c.Note & 0x7F));
                    b.Add((byte)l.Length); b.AddRange(l);
                    b.Add((byte)m.Length); b.AddRange(m);
                    break;
                }
            case PacketBody.CueResend r:
                AppendBE(b, r.OriginalSeq);
                b.Add((byte)(r.Channel & 0x0F)); b.Add((byte)(r.Note & 0x7F)); b.Add((byte)(r.Velocity & 0x7F)); b.Add(r.Released ? (byte)1 : (byte)0);
                break;
            case PacketBody.CueCount c: AppendBE(b, c.Seq); AppendBE(b, c.Count); break;
            case PacketBody.LiveCommandPacket l: AppendBE(b, l.Id); b.AddRange(l.Command.Encode()); break;
            case PacketBody.LiveAck a: AppendBE(b, a.Id); break;
            case PacketBody.LiveStatus s: b.Add(s.Connected ? (byte)1 : (byte)0); break;
            case PacketBody.SetSummary s:
                b.Add((byte)(s.Tracks >> 8)); b.Add((byte)(s.Tracks & 0xFF));
                b.Add((byte)(s.Scenes >> 8)); b.Add((byte)(s.Scenes & 0xFF));
                AppendBE(b, s.Hash);
                break;
            case PacketBody.SetItem s:
                {
                    var n = Utf8Text.Truncate(s.Name, WireProtocol.MaxSetItemNameBytes);
                    b.Add(s.Kind); b.Add((byte)(s.Index >> 8)); b.Add((byte)(s.Index & 0xFF)); b.Add((byte)n.Length); b.AddRange(n);
                    break;
                }
            case PacketBody.LiveResult r: AppendBE(b, r.Id); b.Add(r.Code); break;
            case PacketBody.RoleClaim r: AppendBE(b, r.Millis); break;
            case PacketBody.RemoteSummary r: b.Add(r.Phones); b.Add(r.Watch); break;
            case PacketBody.Desk d: b.AddRange(d.Raw); break;
            default: throw new InvalidOperationException("unknown packet body");
        }
        return b.ToArray();
    }

    private static void AppendHello(List<byte> b, Guid id, byte[] nonce, string name)
    {
        b.AddRange(GuidBytes.ToBigEndian(id));
        var n = new byte[16];
        nonce.AsSpan(0, Math.Min(16, nonce.Length)).CopyTo(n);
        b.AddRange(n);
        var nameBytes = Utf8Text.Truncate(name, WireProtocol.MaxNameBytes);
        b.Add((byte)nameBytes.Length);
        b.AddRange(nameBytes);
    }

    private static void AppendBE(List<byte> b, uint v)
    {
        b.Add((byte)(v >> 24)); b.Add((byte)((v >> 16) & 0xFF)); b.Add((byte)((v >> 8) & 0xFF)); b.Add((byte)(v & 0xFF));
    }

    private static void AppendBE(List<byte> b, ulong v)
    {
        AppendBE(b, (uint)(v >> 32));
        AppendBE(b, (uint)(v & 0xFFFF_FFFF));
    }

    /// <summary>Decodes a plain packet. Throws <see cref="PacketDecodeException"/> on the same inputs Swift's decode throws on.</summary>
    public static Packet Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < WireProtocol.HeaderSize) throw new PacketDecodeException(DecodeError.TooShort);
        if (data[0] != 0x54 || data[1] != 0x4B) throw new PacketDecodeException(DecodeError.BadMagic);
        if (data[2] != WireProtocol.Version) throw new PacketDecodeException(DecodeError.UnsupportedVersion);
        uint session = BinaryPrimitives.ReadUInt32BigEndian(data[4..]);
        uint seq = BinaryPrimitives.ReadUInt32BigEndian(data[8..]);
        var p = data[WireProtocol.HeaderSize..];
        PacketBody body;
        switch (data[3])
        {
            case 0x01:
            case 0x02:
                {
                    Need(p.Length >= 33);
                    var id = GuidBytes.FromBigEndian(p[..16]);
                    var nonce = p[16..32].ToArray();
                    int len = p[32];
                    Need(len <= WireProtocol.MaxNameBytes && p.Length >= 33 + len);
                    var name = Utf8Text.Decode(p.Slice(33, len));
                    body = data[3] == 0x01 ? new PacketBody.Hello(id, nonce, name) : new PacketBody.HelloAck(id, nonce, name);
                    break;
                }
            case 0x03: body = new PacketBody.Bye(); break;
            case 0x10:
                Need(p.Length >= 3 && p[0] < 16 && p[1] < 128 && p[2] < 128);
                body = new PacketBody.NoteOn(p[0], p[1], p[2]);
                break;
            case 0x11:
                Need(p.Length >= 2 && p[0] < 16 && p[1] < 128);
                body = new PacketBody.NoteOff(p[0], p[1]);
                break;
            case 0x20: body = new PacketBody.AllNotesOff(); break;
            case 0x12:
                {
                    Need(p.Length >= 2 && p[0] < 16 && p[1] <= WireProtocol.MaxHeldNotes && p.Length >= 2 + p[1]);
                    var notes = p.Slice(2, p[1]).ToArray();
                    Need(notes.All(n => n < 128));
                    body = new PacketBody.Held(p[0], notes);
                    break;
                }
            case 0x30:
            case 0x31:
                {
                    Need(p.Length >= 8);
                    ulong t = BinaryPrimitives.ReadUInt64BigEndian(p);
                    body = data[3] == 0x30 ? new PacketBody.Heartbeat(t) : new PacketBody.HeartbeatAck(t);
                    break;
                }
            case 0x13:
                Need(p.Length >= 1);
                body = new PacketBody.Features(p[0], p.Length >= 2 ? p[1] : null);
                break;
            case 0x14:
                Need(p.Length >= 4);
                body = new PacketBody.NoteAck(BinaryPrimitives.ReadUInt32BigEndian(p));
                break;
            case 0x15:
                {
                    Need(p.Length >= 4 && p[0] < 16 && p[1] < 128);
                    int ll = p[2];
                    Need(ll <= CueKey.MaxLabelBytes && p.Length >= 4 + ll);
                    int ml = p[3 + ll];
                    Need(ml <= CueKey.MaxMemoBytes && p.Length >= 4 + ll + ml);
                    body = new PacketBody.CueName(p[0], p[1], Utf8Text.Decode(p.Slice(3, ll)), Utf8Text.Decode(p.Slice(4 + ll, ml)));
                    break;
                }
            case 0x16:
                Need(p.Length >= 8 && p[4] < 16 && p[5] < 128 && p[6] < 128);
                body = new PacketBody.CueResend(BinaryPrimitives.ReadUInt32BigEndian(p), p[4], p[5], p[6], p[7] != 0);
                break;
            case 0x17:
                Need(p.Length >= 8);
                body = new PacketBody.CueCount(BinaryPrimitives.ReadUInt32BigEndian(p), BinaryPrimitives.ReadUInt32BigEndian(p[4..]));
                break;
            case 0x18:
                {
                    Need(p.Length >= 5);
                    var c = LiveCommand.Decode(p[4..]);
                    Need(c is not null);
                    body = new PacketBody.LiveCommandPacket(BinaryPrimitives.ReadUInt32BigEndian(p), c!);
                    break;
                }
            case 0x19:
                Need(p.Length >= 4);
                body = new PacketBody.LiveAck(BinaryPrimitives.ReadUInt32BigEndian(p));
                break;
            case 0x1A:
                Need(p.Length >= 1);
                body = new PacketBody.LiveStatus(p[0] != 0);
                break;
            case 0x1B:
                Need(p.Length >= 8);
                body = new PacketBody.SetSummary((ushort)(p[0] << 8 | p[1]), (ushort)(p[2] << 8 | p[3]), BinaryPrimitives.ReadUInt32BigEndian(p[4..]));
                break;
            case 0x1C:
                {
                    Need(p.Length >= 4 && p[0] <= 1);
                    int len = p[3];
                    Need(len <= WireProtocol.MaxSetItemNameBytes && p.Length >= 4 + len);
                    body = new PacketBody.SetItem(p[0], (ushort)(p[1] << 8 | p[2]), Utf8Text.Decode(p.Slice(4, len)));
                    break;
                }
            case 0x1D:
                Need(p.Length >= 5);
                body = new PacketBody.LiveResult(BinaryPrimitives.ReadUInt32BigEndian(p), p[4]);
                break;
            case 0x1E:
                Need(p.Length >= 8);
                body = new PacketBody.RoleClaim(BinaryPrimitives.ReadUInt64BigEndian(p));
                break;
            case 0x1F: body = new PacketBody.RoleHandover(); break;
            case 0x21:
                Need(p.Length >= 2);
                body = new PacketBody.RemoteSummary(p[0], p[1]);
                break;
            case 0x22: body = new PacketBody.Desk(p.ToArray()); break;
            // 0x23-0x26 are the Mac's QLab mode (docs/design-qlab.md 6.2, phase 3). QLab runs on macOS
            // only, so this version does not drive it: they stay unknown and are dropped. A Mac sends
            // them only to a peer whose features have bit 2 (QLab), which this version never sets.
            default: throw new PacketDecodeException(DecodeError.UnknownType);
        }
        return new Packet(session, seq, body);
    }

    private static void Need(bool ok)
    {
        if (!ok) throw new PacketDecodeException(DecodeError.BadPayload);
    }

    /// <summary>Decodes, or returns null for anything Decode would reject.</summary>
    public static Packet? TryDecode(ReadOnlySpan<byte> data)
    {
        try { return Decode(data); }
        catch (PacketDecodeException) { return null; }
    }
}

/// <summary>UUID bytes in RFC 4122 order (Swift's <c>UUID.uuid</c>), not .NET's mixed-endian default.</summary>
public static class GuidBytes
{
    public static byte[] ToBigEndian(Guid g) => g.ToByteArray(bigEndian: true);
    public static Guid FromBigEndian(ReadOnlySpan<byte> b) => new(b[..16], bigEndian: true);
    /// <summary>Upper-case "D" form, the same text as Swift's <c>uuidString</c>.</summary>
    public static string ToSwiftString(Guid g) => g.ToString("D").ToUpperInvariant();
}

/// <summary>UTF-8 helpers that behave like the Swift code.</summary>
public static class Utf8Text
{
    private static readonly UTF8Encoding Lenient = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: false);

    /// <summary>At most <paramref name="max"/> UTF-8 bytes, never splitting a character (grapheme cluster).</summary>
    public static byte[] Truncate(string s, int max)
    {
        var outBytes = new List<byte>(Math.Min(max, s.Length * 3));
        var e = System.Globalization.StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext())
        {
            var bytes = Lenient.GetBytes(e.GetTextElement());
            if (outBytes.Count + bytes.Length > max) break;
            outBytes.AddRange(bytes);
        }
        return outBytes.ToArray();
    }

    public static string TruncateString(string s, int max) => Decode(Truncate(s, max));

    /// <summary>Like Swift's <c>String(decoding:as: UTF8.self)</c>: bad bytes become U+FFFD.</summary>
    public static string Decode(ReadOnlySpan<byte> b) => Lenient.GetString(b);
}

/// <summary>
/// Drops duplicated and reordered packets from one peer (port of Swift's SequenceFilter).
/// Accepts a packet only if its sequence number is newer than the last accepted one
/// (serial-number arithmetic, so wrap-around at 2^32 is handled). A different session value
/// means the peer restarted: tracking starts over.
/// </summary>
public sealed class SequenceFilter
{
    private uint? session;
    private uint last;
    /// <summary>Bit i set: sequence number last - 1 - i was already accepted.</summary>
    private ulong seen;
    private readonly List<uint> retired = [];

    /// <summary>
    /// <paramref name="allowLate"/>: a packet that arrives after a newer one is still accepted once,
    /// if it is among the last 64. Only for packets whose order does not matter; never for notes.
    /// </summary>
    public bool Accept(uint s, uint seq, bool allowLate = false)
    {
        if (session != s)
        {
            if (retired.Contains(s)) return false;
            if (session is uint old)
            {
                retired.Add(old);
                if (retired.Count > 8) retired.RemoveAt(0);
            }
            session = s; last = seq; seen = 0;
            return true;
        }
        int diff = unchecked((int)(seq - last));
        if (diff > 0)
        {
            seen = diff >= 64 ? 0 : (seen << diff) | (1UL << (diff - 1));
            last = seq;
            return true;
        }
        if (!(allowLate && diff < 0 && diff >= -64)) return false;
        ulong bit = 1UL << (-diff - 1);
        if ((seen & bit) != 0) return false;
        seen |= bit;
        return true;
    }

    public void Reset() { session = null; last = 0; seen = 0; retired.Clear(); }

    /// <summary>The peer used this session before and restarted since.</summary>
    public bool IsRetired(uint s) => retired.Contains(s);

    public uint? CurrentSession => session;
}
