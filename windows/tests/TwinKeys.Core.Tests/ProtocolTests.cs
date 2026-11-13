namespace TwinKeys.Core.Tests;

public class ProtocolTests
{
    static readonly Guid Id = Guid.Parse("11111111-2222-3333-4444-555555555555");

    static void RoundTrip(PacketBody body)
    {
        var p = new Packet(0xDEADBEEF, 0x01020304, body);
        var bytes = p.Encode();
        Assert.True(bytes.Length <= WireProtocol.MaxPacketSize);
        Assert.Equal(bytes, Packet.Decode(bytes).Encode());
        Assert.Equal(body.GetType(), Packet.Decode(bytes).Body.GetType());
    }

    [Fact]
    public void RoundTripAllTypes()
    {
        RoundTrip(new PacketBody.Hello(Id, Enumerable.Range(1, 16).Select(i => (byte)i).ToArray(), "Stage PC"));
        RoundTrip(new PacketBody.HelloAck(Id, Enumerable.Repeat((byte)7, 16).ToArray(), ""));
        RoundTrip(new PacketBody.Bye());
        RoundTrip(new PacketBody.NoteOn(15, 127, 1));
        RoundTrip(new PacketBody.NoteOff(0, 0));
        RoundTrip(new PacketBody.AllNotesOff());
        RoundTrip(new PacketBody.Heartbeat(0x0123_4567_89AB_CDEF));
        RoundTrip(new PacketBody.HeartbeatAck(ulong.MaxValue));
        RoundTrip(new PacketBody.Held(3, [60, 64, 67]));
        RoundTrip(new PacketBody.Held(0, []));
        RoundTrip(new PacketBody.Features(1));
        RoundTrip(new PacketBody.Features(3, 200));
        RoundTrip(new PacketBody.NoteAck(0xDEADBEEF));
        RoundTrip(new PacketBody.CueName(1, 37, "↓", "次のシーン"));
        RoundTrip(new PacketBody.CueResend(5, 1, 37, 127, true));
        RoundTrip(new PacketBody.CueCount(9, 12));
        RoundTrip(new PacketBody.RoleClaim(1_763_100_000_000));
        RoundTrip(new PacketBody.RoleHandover());
        RoundTrip(new PacketBody.LiveCommandPacket(5, new LiveCommand.SetSend(4, 1, 0.25)));
    }

    [Fact]
    public void HeaderLayout()
    {
        var b = new Packet(1, 2, new PacketBody.NoteOn(0, 60, 100)).Encode();
        Assert.Equal(new byte[] { 0x54, 0x4B, 2, 0x10, 0, 0, 0, 1, 0, 0, 0, 2, 0, 60, 100 }, b);
    }

    [Fact]
    public void UuidIsSentInRfc4122Order()
    {
        var b = new Packet(1, 1, new PacketBody.Hello(Id, new byte[16], "")).Encode();
        Assert.Equal(Convert.FromHexString("11111111222233334444555555555555"), b[12..28]);
        Assert.Equal("11111111-2222-3333-4444-555555555555", GuidBytes.ToSwiftString(((PacketBody.Hello)Packet.Decode(b).Body).InstanceId));
    }

    [Fact]
    public void LongNameIsTruncatedOnCharacterBoundary()
    {
        var name = string.Concat(Enumerable.Repeat("鍵", 20));
        var p = Packet.Decode(new Packet(1, 1, new PacketBody.Hello(Id, new byte[16], name)).Encode());
        Assert.Equal(string.Concat(Enumerable.Repeat("鍵", 10)), ((PacketBody.Hello)p.Body).Name);
    }

    [Theory]
    [InlineData(new byte[] { 0x54, 0x4B, 1 }, DecodeError.TooShort)]
    [InlineData(new byte[] { 0x00, 0x4B, 1, 0x20, 0, 0, 0, 0, 0, 0, 0, 0 }, DecodeError.BadMagic)]
    [InlineData(new byte[] { 0x54, 0x4B, 9, 0x20, 0, 0, 0, 0, 0, 0, 0, 0 }, DecodeError.UnsupportedVersion)]
    [InlineData(new byte[] { 0x54, 0x4B, 2, 0x77, 0, 0, 0, 0, 0, 0, 0, 0 }, DecodeError.UnknownType)]
    [InlineData(new byte[] { 0x54, 0x4B, 2, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 100 }, DecodeError.BadPayload)]
    [InlineData(new byte[] { 0x54, 0x4B, 2, 0x30, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2 }, DecodeError.BadPayload)]
    public void RejectsBadPackets(byte[] bytes, DecodeError error)
    {
        var e = Assert.Throws<PacketDecodeException>(() => Packet.Decode(bytes));
        Assert.Equal(error, e.Error);
    }

    [Fact]
    public void ConsoleChannelPacketIsReadAndIgnored()
    {
        var p = Packet.Decode(new byte[] { 0x54, 0x4B, 2, 0x22, 0, 0, 0, 1, 0, 0, 0, 2, 9, 9 });
        Assert.IsType<PacketBody.Desk>(p.Body);
    }

    [Fact]
    public void SequenceFilterDropsDuplicatesAndReordered()
    {
        var f = new SequenceFilter();
        Assert.True(f.Accept(7, 10));
        Assert.False(f.Accept(7, 10));
        Assert.True(f.Accept(7, 12));
        Assert.False(f.Accept(7, 11));
        Assert.True(f.Accept(7, 13));
    }

    [Fact]
    public void SequenceFilterWrapAround()
    {
        var f = new SequenceFilter();
        Assert.True(f.Accept(1, uint.MaxValue - 1));
        Assert.True(f.Accept(1, uint.MaxValue));
        Assert.True(f.Accept(1, 0));
        Assert.True(f.Accept(1, 1));
        Assert.False(f.Accept(1, uint.MaxValue));
    }

    [Fact]
    public void LatePacketFromPreviousSessionIsDropped()
    {
        var f = new SequenceFilter();
        Assert.True(f.Accept(1, 10));
        Assert.True(f.Accept(2, 5));
        Assert.False(f.Accept(1, 11));
        Assert.False(f.Accept(2, 5));
        Assert.True(f.Accept(2, 6));
    }

    [Fact]
    public void LateOrderFreePacketsAreAcceptedOnceButLateNotesAreNot()
    {
        var f = new SequenceFilter();
        Assert.True(f.Accept(1, 10));
        Assert.True(f.Accept(1, 12));
        Assert.False(f.Accept(1, 11));
        Assert.True(f.Accept(1, 11, allowLate: true));
        Assert.False(f.Accept(1, 11, allowLate: true));
        Assert.False(f.Accept(1, 12, allowLate: true));
        Assert.True(f.Accept(1, 200));
        Assert.False(f.Accept(1, 100, allowLate: true));
    }

    [Fact]
    public void PeerFromTxtExcludesSelf()
    {
        Assert.Null(TxtKeys.Peer(new Dictionary<string, string> { ["id"] = "me", ["modes"] = "sr" }, "Mine", "me"));
        Assert.Null(TxtKeys.Peer(new Dictionary<string, string> { ["modes"] = "sr" }, "NoID", "me"));
        var p = TxtKeys.Peer(new Dictionary<string, string> { ["id"] = "other", ["modes"] = "r", ["os"] = "win" }, "Backup", "me")!;
        Assert.Equal(new PeerInfo("other", "Backup", false, true, null, "win"), p);
        Assert.Equal("sr", TxtKeys.ModesValue(true, true));
        Assert.True(TxtKeys.Peer(new Dictionary<string, string> { ["id"] = "x", ["v"] = "2" }, "A", "me")!.IsCompatible);
        Assert.False(TxtKeys.Peer(new Dictionary<string, string> { ["id"] = "x", ["v"] = "1" }, "A", "me")!.IsCompatible);
        Assert.True(TxtKeys.IsDuplicateOfUs(new Dictionary<string, string> { ["id"] = "me", ["boot"] = "b2" }, "me", "b1"));
        Assert.False(TxtKeys.IsDuplicateOfUs(new Dictionary<string, string> { ["id"] = "me", ["boot"] = "b1" }, "me", "b1"));
    }

    [Fact]
    public void ManualAddressParse()
    {
        Assert.Equal(("192.168.1.20", (ushort)47801), ManualAddress.Parse(" 192.168.1.20 "));
        Assert.Equal(("192.168.1.20", (ushort)47802), ManualAddress.Parse("192.168.1.20:47802"));
        Assert.Equal(("fe80::1%12", (ushort)47801), ManualAddress.Parse("fe80::1%12"));
        Assert.Equal(("fe80::1%12", (ushort)47802), ManualAddress.Parse("[fe80::1%12]:47802"));
        Assert.Null(ManualAddress.Parse(""));
        Assert.Null(ManualAddress.Parse("host:0"));
        Assert.Null(ManualAddress.Parse("host:99999"));
        Assert.Null(ManualAddress.Parse("[fe80::1"));
    }
}
