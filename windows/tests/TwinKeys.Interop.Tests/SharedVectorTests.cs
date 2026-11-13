using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

namespace TwinKeys.Interop.Tests;

/// <summary>
/// Checks the C# code against shared/test-vectors/*.json, which Tests/TwinKeysCoreTests/
/// InteropVectorsTests.swift checks against the Mac code (docs/design-windows.md 6.6). If these
/// pass on both sides, the two speak the same bytes.
/// </summary>
public class SharedVectorTests
{
    static readonly string Dir = FindVectors();

    static string FindVectors()
    {
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d is not null; d = d.Parent)
        {
            var p = Path.Combine(d.FullName, "shared", "test-vectors");
            if (Directory.Exists(p)) return p;
        }
        throw new DirectoryNotFoundException("shared/test-vectors not found above " + AppContext.BaseDirectory);
    }

    internal static JsonObject LoadFile(string name) => Load(name);
    internal static bool SameJson(JsonNode? a, JsonNode? b) => Same(a, b);
    static JsonObject Load(string name) => (JsonObject)JsonNode.Parse(File.ReadAllText(Path.Combine(Dir, name)))!;
    static byte[] Hex(JsonNode? n) => Convert.FromHexString((string)n!);
    static string HexOf(byte[] b) => Convert.ToHexStringLower(b);
    static uint U32(JsonNode? n) => (uint)(long)n!;
    static byte U8(JsonNode? n) => (byte)(int)n!;
    static ulong U64(JsonNode? n) => ulong.Parse((string)n!, CultureInfo.InvariantCulture);

    // MARK: JSON <-> packet bodies (the same field names as the Swift test)

    internal static LiveCommand Command(JsonObject c) => (string)c["op"]! switch
    {
        "fireScene" => new LiveCommand.FireScene((int)c["scene"]!),
        "fireClip" => new LiveCommand.FireClip((int)c["track"]!, (int)c["scene"]!),
        "stopTrack" => new LiveCommand.StopTrack((int)c["track"]!),
        "stopAll" => new LiveCommand.StopAll(),
        "play" => new LiveCommand.Play(),
        "stop" => new LiveCommand.Stop(),
        "continuePlaying" => new LiveCommand.ContinuePlaying(),
        "setTempo" => new LiveCommand.SetTempo((double)c["bpm"]!),
        "setVolume" => new LiveCommand.SetVolume((int)c["track"]!, (double)c["value"]!),
        "setPan" => new LiveCommand.SetPan((int)c["track"]!, (double)c["value"]!),
        "setSend" => new LiveCommand.SetSend((int)c["track"]!, (int)c["send"]!, (double)c["value"]!),
        "setMute" => new LiveCommand.SetMute((int)c["track"]!, (bool)c["on"]!),
        "setSolo" => new LiveCommand.SetSolo((int)c["track"]!, (bool)c["on"]!),
        "selectScene" => new LiveCommand.SelectScene((int)c["scene"]!),
        var op => throw new InvalidDataException("unknown op " + op),
    };

    internal static JsonObject Describe(LiveCommand c) => c switch
    {
        LiveCommand.FireScene s => new() { ["op"] = "fireScene", ["scene"] = s.Scene },
        LiveCommand.FireClip x => new() { ["op"] = "fireClip", ["track"] = x.Track, ["scene"] = x.Scene },
        LiveCommand.StopTrack x => new() { ["op"] = "stopTrack", ["track"] = x.Track },
        LiveCommand.StopAll => new() { ["op"] = "stopAll" },
        LiveCommand.Play => new() { ["op"] = "play" },
        LiveCommand.Stop => new() { ["op"] = "stop" },
        LiveCommand.ContinuePlaying => new() { ["op"] = "continuePlaying" },
        LiveCommand.SetTempo x => new() { ["op"] = "setTempo", ["bpm"] = x.Bpm },
        LiveCommand.SetVolume x => new() { ["op"] = "setVolume", ["track"] = x.Track, ["value"] = x.Value },
        LiveCommand.SetPan x => new() { ["op"] = "setPan", ["track"] = x.Track, ["value"] = x.Value },
        LiveCommand.SetSend x => new() { ["op"] = "setSend", ["track"] = x.Track, ["send"] = x.Send, ["value"] = x.Value },
        LiveCommand.SetMute x => new() { ["op"] = "setMute", ["track"] = x.Track, ["on"] = x.On },
        LiveCommand.SetSolo x => new() { ["op"] = "setSolo", ["track"] = x.Track, ["on"] = x.On },
        LiveCommand.SelectScene x => new() { ["op"] = "selectScene", ["scene"] = x.Scene },
        _ => throw new InvalidDataException(),
    };

    internal static PacketBody Body(JsonObject b) => (string)b["type"]! switch
    {
        "hello" => new PacketBody.Hello(Guid.Parse((string)b["instance_id"]!), Hex(b["nonce"]), (string)b["name"]!),
        "helloAck" => new PacketBody.HelloAck(Guid.Parse((string)b["instance_id"]!), Hex(b["nonce"]), (string)b["name"]!),
        "bye" => new PacketBody.Bye(),
        "noteOn" => new PacketBody.NoteOn(U8(b["channel"]), U8(b["note"]), U8(b["velocity"])),
        "noteOff" => new PacketBody.NoteOff(U8(b["channel"]), U8(b["note"])),
        "allNotesOff" => new PacketBody.AllNotesOff(),
        "heartbeat" => new PacketBody.Heartbeat(U64(b["timestamp_nanos"])),
        "heartbeatAck" => new PacketBody.HeartbeatAck(U64(b["timestamp_nanos"])),
        "held" => new PacketBody.Held(U8(b["channel"]), b["notes"]!.AsArray().Select(U8).ToArray()),
        "features" => new PacketBody.Features(U8(b["flags"]), b["epoch"] is JsonNode e ? U8(e) : null),
        "noteAck" => new PacketBody.NoteAck(U32(b["seq"])),
        "cueName" => new PacketBody.CueName(U8(b["channel"]), U8(b["note"]), (string)b["label"]!, (string)b["memo"]!),
        "cueResend" => new PacketBody.CueResend(U32(b["original_seq"]), U8(b["channel"]), U8(b["note"]), U8(b["velocity"]), (bool)b["released"]!),
        "cueCount" => new PacketBody.CueCount(U32(b["seq"]), U32(b["count"])),
        "liveCommand" => new PacketBody.LiveCommandPacket(U32(b["id"]), Command(b["command"]!.AsObject())),
        "liveAck" => new PacketBody.LiveAck(U32(b["id"])),
        "liveStatus" => new PacketBody.LiveStatus((bool)b["connected"]!),
        "setSummary" => new PacketBody.SetSummary((ushort)(int)b["tracks"]!, (ushort)(int)b["scenes"]!, U32(b["hash"])),
        "setItem" => new PacketBody.SetItem(U8(b["kind"]), (ushort)(int)b["index"]!, (string)b["name"]!),
        "liveResult" => new PacketBody.LiveResult(U32(b["id"]), U8(b["code"])),
        "roleClaim" => new PacketBody.RoleClaim(U64(b["millis"])),
        "roleHandover" => new PacketBody.RoleHandover(),
        "remoteSummary" => new PacketBody.RemoteSummary(U8(b["phones"]), U8(b["watch"])),
        var t => throw new InvalidDataException("unknown type " + t),
    };

    internal static JsonObject Describe(PacketBody body) => body switch
    {
        PacketBody.Hello h => new() { ["type"] = "hello", ["instance_id"] = GuidBytes.ToSwiftString(h.InstanceId), ["nonce"] = HexOf(h.Nonce), ["name"] = h.Name },
        PacketBody.HelloAck h => new() { ["type"] = "helloAck", ["instance_id"] = GuidBytes.ToSwiftString(h.InstanceId), ["nonce"] = HexOf(h.Nonce), ["name"] = h.Name },
        PacketBody.Bye => new() { ["type"] = "bye" },
        PacketBody.NoteOn n => new() { ["type"] = "noteOn", ["channel"] = n.Channel, ["note"] = n.Note, ["velocity"] = n.Velocity },
        PacketBody.NoteOff n => new() { ["type"] = "noteOff", ["channel"] = n.Channel, ["note"] = n.Note },
        PacketBody.AllNotesOff => new() { ["type"] = "allNotesOff" },
        PacketBody.Heartbeat t => new() { ["type"] = "heartbeat", ["timestamp_nanos"] = t.TimestampNanos.ToString(CultureInfo.InvariantCulture) },
        PacketBody.HeartbeatAck t => new() { ["type"] = "heartbeatAck", ["timestamp_nanos"] = t.TimestampNanos.ToString(CultureInfo.InvariantCulture) },
        PacketBody.Held h => new() { ["type"] = "held", ["channel"] = h.Channel, ["notes"] = new JsonArray(h.Notes.Select(n => (JsonNode)(int)n).ToArray()) },
        PacketBody.Features f => f.Epoch is byte e
            ? new() { ["type"] = "features", ["flags"] = f.Flags, ["epoch"] = e }
            : new() { ["type"] = "features", ["flags"] = f.Flags },
        PacketBody.NoteAck a => new() { ["type"] = "noteAck", ["seq"] = a.Seq },
        PacketBody.CueName c => new() { ["type"] = "cueName", ["channel"] = c.Channel, ["note"] = c.Note, ["label"] = c.Label, ["memo"] = c.Memo },
        PacketBody.CueResend r => new() { ["type"] = "cueResend", ["original_seq"] = r.OriginalSeq, ["channel"] = r.Channel, ["note"] = r.Note, ["velocity"] = r.Velocity, ["released"] = r.Released },
        PacketBody.CueCount c => new() { ["type"] = "cueCount", ["seq"] = c.Seq, ["count"] = c.Count },
        PacketBody.LiveCommandPacket l => new() { ["type"] = "liveCommand", ["id"] = l.Id, ["command"] = Describe(l.Command) },
        PacketBody.LiveAck a => new() { ["type"] = "liveAck", ["id"] = a.Id },
        PacketBody.LiveStatus s => new() { ["type"] = "liveStatus", ["connected"] = s.Connected },
        PacketBody.SetSummary s => new() { ["type"] = "setSummary", ["tracks"] = s.Tracks, ["scenes"] = s.Scenes, ["hash"] = s.Hash },
        PacketBody.SetItem s => new() { ["type"] = "setItem", ["kind"] = s.Kind, ["index"] = s.Index, ["name"] = s.Name },
        PacketBody.LiveResult r => new() { ["type"] = "liveResult", ["id"] = r.Id, ["code"] = r.Code },
        PacketBody.RoleClaim r => new() { ["type"] = "roleClaim", ["millis"] = r.Millis.ToString(CultureInfo.InvariantCulture) },
        PacketBody.RoleHandover => new() { ["type"] = "roleHandover" },
        PacketBody.RemoteSummary r => new() { ["type"] = "remoteSummary", ["phones"] = r.Phones, ["watch"] = r.Watch },
        _ => new() { ["type"] = "desk" },
    };

    /// <summary>JSON equality where numbers compare by value (37 == 37.0).</summary>
    static bool Same(JsonNode? a, JsonNode? b)
    {
        if (a is JsonObject x && b is JsonObject y)
            return x.Count == y.Count && x.All(kv => y.ContainsKey(kv.Key) && Same(kv.Value, y[kv.Key]));
        if (a is JsonArray p && b is JsonArray q)
            return p.Count == q.Count && p.Zip(q).All(z => Same(z.First, z.Second));
        if (a is JsonValue u && b is JsonValue v)
        {
            if (u.GetValueKind() is System.Text.Json.JsonValueKind.Number && v.GetValueKind() is System.Text.Json.JsonValueKind.Number)
                return double.Parse(u.ToJsonString(), CultureInfo.InvariantCulture) == double.Parse(v.ToJsonString(), CultureInfo.InvariantCulture);
            return u.ToJsonString() == v.ToJsonString();
        }
        return a is null && b is null;
    }

    // MARK: pairing.json

    [Fact]
    public void Pbkdf2MatchesRfc7914()
    {
        foreach (var v in Load("pairing.json")["pbkdf2_rfc7914"]!.AsArray())
        {
            var key = Pairing.Pbkdf2(Encoding.UTF8.GetBytes((string)v!["password"]!), Encoding.UTF8.GetBytes((string)v["salt"]!), (int)v["iterations"]!, (int)v["length"]!);
            Assert.Equal((string)v["key"]!, HexOf(key));
        }
    }

    [Fact]
    public void PairingCodesGiveTheSameKeysAndFingerprints()
    {
        var f = Load("pairing.json");
        Assert.Equal(Pairing.Alphabet, (string)f["alphabet"]!);
        Assert.Equal(Pairing.Iterations, (int)f["iterations"]!);
        Assert.Equal((string)f["salt"]!, Encoding.UTF8.GetString(Pairing.Salt));
        int valid = 0;
        foreach (var c in f["codes"]!.AsArray())
        {
            var input = (string)c!["input"]!;
            var n = Pairing.Normalize(input);
            if (!(bool)c["valid"]!) { Assert.Null(n); continue; }
            valid++;
            Assert.Equal((string)c["normalized"]!, n);
            Assert.Equal((string)c["formatted"]!, Pairing.Formatted(n!));
            var secret = PairingSecret.FromCode(input)!;
            Assert.Equal((string)c["key"]!, HexOf(secret.Key));
            Assert.Equal((string)c["fingerprint"]!, secret.Fingerprint);
        }
        Assert.True(valid >= 4);
    }

    // MARK: packets.json

    public static TheoryData<string> PacketNames() => new(Load("packets.json")["packets"]!.AsArray().Select(p => (string)p!["name"]!));
    public static TheoryData<string> BadPacketNames() => new(Load("packets.json")["bad_packets"]!.AsArray().Select(p => (string)p!["name"]!));

    static JsonObject Find(string file, string group, string name) =>
        Load(file)[group]!.AsArray().Single(p => (string)p!["name"]! == name)!.AsObject();

    [Theory]
    [MemberData(nameof(PacketNames))]
    public void PacketEncodesToTheSameBytes(string name)
    {
        var v = Find("packets.json", "packets", name);
        var packet = new Packet(U32(v["session"]), U32(v["seq"]), Body(v["body"]!.AsObject()));
        Assert.Equal((string)v["bytes"]!, HexOf(packet.Encode()));
        var back = Packet.Decode(Hex(v["bytes"]));
        Assert.Equal(packet.Session, back.Session);
        Assert.Equal(packet.Seq, back.Seq);
        var described = Describe(back.Body);
        Assert.True(Same(v["decoded"], described), $"decoded {described.ToJsonString()} != {v["decoded"]!.ToJsonString()}");
        Assert.True(packet.Encode().Length + SecureChannel.TagSize <= WireProtocol.MaxPacketSize);
    }

    [Theory]
    [MemberData(nameof(BadPacketNames))]
    public void BadPacketIsRejectedForTheSameReason(string name)
    {
        var v = Find("packets.json", "bad_packets", name);
        var expected = (string)v["error"]!;
        string actual;
        try { Packet.Decode(Hex(v["bytes"])); actual = "none"; }
        catch (PacketDecodeException e) { actual = char.ToLowerInvariant(e.Error.ToString()[0]) + e.Error.ToString()[1..]; }
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void ProtocolConstants()
    {
        var f = Load("packets.json");
        Assert.Equal(WireProtocol.Version, (int)f["protocol_version"]!);
        Assert.Equal(WireProtocol.MaxPacketSize, (int)f["max_packet_size"]!);
    }

    // MARK: secure.json

    [Fact]
    public void KeysAndDirectionKeysMatch()
    {
        var f = Load("secure.json");
        var secret = PairingSecret.FromCode((string)f["code"]!)!;
        Assert.Equal((string)f["key"]!, HexOf(secret.Key));
        Assert.Equal((string)f["fingerprint"]!, secret.Fingerprint);
        var a = new SecureChannel(secret, Hex(f["nonce_a"]));
        Assert.Equal((string)f["direction_key_a_to_b"]!, HexOf(a.DirectionKey(Hex(f["nonce_a"]), Hex(f["nonce_b"]))));
        Assert.Equal((string)f["direction_key_b_to_a"]!, HexOf(a.DirectionKey(Hex(f["nonce_b"]), Hex(f["nonce_a"]))));
    }

    public static TheoryData<string> SealedNames() => new(Load("secure.json")["sealed"]!.AsArray().Select(p => (string)p!["name"]!));

    [Theory]
    [MemberData(nameof(SealedNames))]
    public void SealedPacketsMatchAndOpen(string name)
    {
        var f = Load("secure.json");
        var v = Find("secure.json", "sealed", name);
        var secret = new PairingSecret(Hex(f["key"]));
        var a = new SecureChannel(secret, Hex(f["nonce_a"]));
        var b = new SecureChannel(secret, Hex(f["nonce_b"]));
        var (from, to) = (string)v["sender"]! == "a" ? (a, b) : (b, a);
        var packet = new Packet(U32(v["session"]), U32(v["seq"]), Body(v["body"]!.AsObject()));
        Assert.Equal((string)v["plain"]!, HexOf(packet.Encode()));
        var sealedBytes = from.Seal(packet, to.MyNonce)!;
        Assert.Equal((string)v["sealed"]!, HexOf(sealedBytes));
        var opened = packet.Body.IsHelloOrAck ? to.OpenHello(Hex(v["sealed"])) : to.Open(Hex(v["sealed"]), from.MyNonce);
        Assert.Equal((string)v["plain"]!, HexOf(opened.Encode()));
        Assert.True(sealedBytes.Length <= WireProtocol.MaxPacketSize);
    }

    // MARK: hkdf.json

    [Fact]
    public void HkdfMatches()
    {
        foreach (var v in Load("hkdf.json")["hkdf_sha256"]!.AsArray())
            Assert.Equal((string)v!["okm"]!, HexOf(Hkdf.Sha256(Hex(v["ikm"]), Hex(v["salt"]), Hex(v["info"]), (int)v["length"]!)));
    }

    // MARK: sequence.json

    [Fact]
    public void SequenceFilterGivesTheSameAnswers()
    {
        foreach (var c in Load("sequence.json")["cases"]!.AsArray())
        {
            var f = new SequenceFilter();
            int i = 0;
            foreach (var s in c!["steps"]!.AsArray())
            {
                bool got = f.Accept(U32(s!["session"]), U32(s["seq"]), (bool)s["allow_late"]!);
                Assert.True((bool)s["accepted"]! == got, $"{c["name"]} step {i}: expected {s["accepted"]}, got {got}");
                i++;
            }
        }
    }

    // MARK: livecommand.json

    [Fact]
    public void LiveCommandsMatch()
    {
        var f = Load("livecommand.json");
        foreach (var v in f["commands"]!.AsArray())
        {
            var c = Command(v!["command"]!.AsObject());
            Assert.Equal((string)v["bytes"]!, HexOf(c.Encode()));
            Assert.Equal((bool)v["valid"]!, c.IsValid);
            Assert.Equal((bool)v["continuous"]!, c.IsContinuous);
            var back = LiveCommand.Decode(Hex(v["bytes"]));
            Assert.NotNull(back);
            Assert.True(Same(v["command"], Describe(back!)));
            var bridge = new JsonObject();
            foreach (var (k, value) in c.BridgeJson(7))
                bridge[k] = value switch { int i => i, double d => d, bool b => b, string s => s, _ => throw new InvalidDataException() };
            Assert.True(Same(v["bridge"], bridge), $"bridge {bridge.ToJsonString()} != {v["bridge"]!.ToJsonString()}");
            // The datagram the app really sends (Utf8JsonWriter) means the same JSON.
            Assert.True(Same(v["bridge"], JsonNode.Parse(c.BridgeJsonBytes(7))), "BridgeJsonBytes");
        }
        foreach (var v in f["bad"]!.AsArray())
            Assert.True((bool)v!["decodes"]! == (LiveCommand.Decode(Hex(v["bytes"])) is not null), (string)v["name"]!);
    }

    // MARK: setcheck.json (phase 2)

    [Fact]
    public void SetCheckMatches()
    {
        var f = Load("setcheck.json");
        Assert.NotEmpty(f["cases"]!.AsArray());
        foreach (var v in f["cases"]!.AsArray())
        {
            static List<string> L(JsonNode? n) => n!.AsArray().Select(x => (string)x!).ToList();
            var s = new SetSummary(L(v!["tracks"]), L(v["scenes"]));
            string name = (string)v["name"]!;
            Assert.True(L(v["cut_tracks"]).SequenceEqual(s.Tracks), name + " tracks");
            Assert.True(L(v["cut_scenes"]).SequenceEqual(s.Scenes), name + " scenes");
            Assert.True(U32(v["hash"]) == s.Hash, $"{name}: hash {s.Hash}, expected {v["hash"]}");
        }
    }
}
