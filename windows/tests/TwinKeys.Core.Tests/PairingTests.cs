using System.Text;

namespace TwinKeys.Core.Tests;

public class PairingTests
{
    [Fact]
    public void Pbkdf2Rfc7914Vector1() =>
        Assert.Equal(Convert.FromHexString("55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"),
            Pairing.Pbkdf2(Encoding.UTF8.GetBytes("passwd"), Encoding.UTF8.GetBytes("salt"), 1, 64));

    [Fact]
    public void CodeFormat()
    {
        var c = Pairing.Generate();
        Assert.Equal(11, c.Length);
        Assert.Equal('-', c[5]);
        Assert.NotNull(Pairing.Normalize(c));
        Assert.NotEqual(Pairing.Generate(), Pairing.Generate());
        Assert.Equal("K7MQ2WX9TP", Pairing.Normalize(" k7mq2 wx9tp "));
        Assert.Equal("K7MQ2WX9TP", Pairing.Normalize("K7MQ2-WX9TP"));
        Assert.Null(Pairing.Normalize("K7MQ2-WX9T"));
        Assert.Null(Pairing.Normalize("K7MQ2-WX9T0"));
        Assert.Equal("K7MQ2-WX9TP", Pairing.Formatted("K7MQ2WX9TP"));
    }

    [Fact]
    public void SameCodeSameKeyDifferentCodeDifferentKey()
    {
        var a = PairingSecret.FromCode("K7MQ2-WX9TP")!;
        var b = PairingSecret.FromCode("k7mq2wx9tp")!;
        var c = PairingSecret.FromCode("K7MQ2-WX9TQ")!;
        Assert.Equal(a.Fingerprint, b.Fingerprint);
        Assert.NotEqual(a.Fingerprint, c.Fingerprint);
        Assert.Null(PairingSecret.FromCode("short"));
    }

    [Fact]
    public void SealOpenRoundTripAndTamper()
    {
        var s = new PairingSecret(Enumerable.Range(1, 32).Select(i => (byte)i).ToArray());
        var a = new SecureChannel(s);
        var b = new SecureChannel(s);
        var note = new Packet(4, 9, new PacketBody.NoteOn(0, 60, 100));
        Assert.Null(a.Seal(note, null));
        var bytes = a.Seal(note, b.MyNonce)!;
        Assert.Equal(note, b.Open(bytes, a.MyNonce));
        var t = (byte[])bytes.Clone(); t[5] ^= 1;
        Assert.Throws<SecureChannel.OpenException>(() => b.Open(t, a.MyNonce));
        Assert.Throws<SecureChannel.OpenException>(() => a.Open(bytes, b.MyNonce));
        var hello = new Packet(4, 1, new PacketBody.Hello(Guid.NewGuid(), a.MyNonce, "A"));
        var hb = a.Seal(hello, null)!;
        Assert.Equal(hello.Encode(), b.OpenHello(hb).Encode());
        var other = new SecureChannel(new PairingSecret(Enumerable.Repeat((byte)9, 32).ToArray()));
        var e = Assert.Throws<SecureChannel.OpenException>(() => other.OpenHello(hb));
        Assert.Equal(SecureChannel.OpenError.BadSignature, e.Error);
        Assert.True(hb.Length <= WireProtocol.MaxPacketSize);
    }
}
