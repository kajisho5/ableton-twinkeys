using System.Text.Json.Nodes;

namespace TwinKeys.Interop.Tests;

/// <summary>
/// QLab mode is Mac only (docs/design-qlab.md, phase 3): TwinKeys for Windows must drop the Mac's
/// QLab packets 0x23-0x26 as unknown types (never fail the link on them), and still read a features
/// packet that has the Mac's QLab bit set. Vectors: shared/test-vectors/qlab.json, written by
/// Tests/TwinKeysCoreTests/InteropVectorsTests.swift.
/// </summary>
public class QLabVectorTests
{
    static JsonObject File() => SharedVectorTests.LoadFile("qlab.json");

    public static TheoryData<string> PacketNames() => new(File()["packets"]!.AsArray().Select(p => (string)p!["name"]!));

    [Theory]
    [MemberData(nameof(PacketNames))]
    public void QLabPacketIsDroppedAsUnknownType(string name)
    {
        var v = File()["packets"]!.AsArray().First(p => (string)p!["name"]! == name)!;
        var bytes = Convert.FromHexString((string)v["bytes"]!);
        Assert.InRange(bytes[3], (byte)0x23, (byte)0x26);
        var e = Assert.Throws<PacketDecodeException>(() => Packet.Decode(bytes));
        Assert.Equal(DecodeError.UnknownType, e.Error);
        Assert.Equal("unknownType", (string)v["windows_error"]!);
    }

    [Fact]
    public void FeaturesWithTheQLabBitStillDecode()
    {
        var v = File()["features_with_qlab"]!;
        var p = Packet.Decode(Convert.FromHexString((string)v["bytes"]!));
        var f = Assert.IsType<PacketBody.Features>(p.Body);
        Assert.Equal((byte)(int)v["flags"]!, f.Flags);
        Assert.Equal((byte)(int)v["epoch"]!, f.Epoch);
        // Bit 0 (answers cues) is what Windows reads; bit 2 (QLab) is ignored.
        Assert.Equal(1, f.Flags & 1);
    }

    [Fact]
    public void QLabRemoteMessagesAreSkipped()
    {
        // The iPhone link's QLab messages (qlab, qlabCues, qlabStatus): Windows does not list "qlab"
        // in its welcome, so an iPhone never sends it one; anything that arrives is skipped.
        var list = File()["remote_messages"]!.AsArray();
        Assert.NotEmpty(list);
        foreach (var v in list)
            Assert.Null(RemoteMessage.FromJson(v!["message"]));
        Assert.DoesNotContain("qlab", RemoteFeature.All);
    }
}
