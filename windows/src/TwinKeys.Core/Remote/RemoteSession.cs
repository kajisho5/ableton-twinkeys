using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Org.BouncyCastle.Math.EC.Rfc7748;

namespace TwinKeys.Core;

public static class RemoteProtocol
{
    public const int Version = 1;
    public const string ServiceType = "_twinkeys-remote._tcp";
    public const int MaxFrame = 4 * 1024 * 1024;
    internal const int TagSize = 32;
}

public sealed class RemoteException(string reason) : Exception(reason)
{
    public string Reason { get; } = reason;
}

/// <summary>
/// X25519 (RFC 7748). .NET 10 has no X25519 class (it came in .NET 11, which is not LTS), so this
/// uses BouncyCastle.Cryptography 2.7.0 (docs/design-windows.md 2.5). The raw 32-byte keys are the
/// same as CryptoKit's Curve25519.KeyAgreement rawRepresentation.
/// </summary>
public static class Curve25519
{
    public static byte[] NewPrivateKey() => RandomNumberGenerator.GetBytes(X25519.ScalarSize);

    public static byte[] PublicKey(byte[] privateKey)
    {
        var pub = new byte[X25519.PointSize];
        X25519.ScalarMultBase(privateKey, 0, pub, 0);
        return pub;
    }

    /// <summary>The shared value (CryptoKit's sharedSecretFromKeyAgreement). Throws for a key that gives all zeros, as CryptoKit does.</summary>
    public static byte[] Shared(byte[] privateKey, byte[] peerPublic)
    {
        if (peerPublic.Length != X25519.PointSize) throw new RemoteException("badKey");
        var s = new byte[X25519.PointSize];
        if (!X25519.CalculateAgreement(privateKey, 0, peerPublic, 0, s, 0)) throw new RemoteException("badKey");
        return s;
    }
}

/// <summary>
/// One side of a TwinKeys Remote connection over TCP (port of RemoteSession in
/// Sources/TwinKeysCore/RemoteChannel.swift; docs/design-windows.md 6.5). Feed received bytes with
/// <see cref="Receive"/>; send with <see cref="Seal"/>. Not thread-safe: one connection, one thread.
/// </summary>
public sealed class RemoteSession
{
    public enum Role { Client, Server }

    public abstract record Event
    {
        private Event() { }
        /// <summary>Server: a device said hello and proved the pairing code. Decide whether it is approved.</summary>
        public sealed record ClientHello(RemoteClientHello Hello, string ConfirmCode) : Event;
        /// <summary>Client: the computer answered; the encrypted channel is ready.</summary>
        public sealed record ServerHello(RemoteServerHello Hello, string ConfirmCode) : Event;
        public sealed record Message(RemoteMessage Value) : Event;
        /// <summary>An authentic message of a kind this version does not know (skipped; the connection stays).</summary>
        public sealed record Unknown(string Json) : Event;
    }

    public Role Side { get; }
    private readonly byte[] pairingKey;
    private byte[] buffer = [];
    private ChaCha20Poly1305? sendBox, receiveBox;
    private ulong sendCounter, receiveCounter;
    private byte[] clientHelloBytes = [];
    private readonly byte[]? deviceKey;
    private byte[]? ephemeral;
    private readonly byte[]? fixedEphemeral, fixedNonce;
    public RemoteClientHello? PeerHello { get; private set; }
    public bool IsReady => sendBox is not null;
    /// <summary>The session keys (client → server, server → client), for the shared test vectors.</summary>
    internal (byte[] C2S, byte[] S2C)? Keys { get; private set; }

    private RemoteSession(Role side, PairingSecret pairing, byte[]? deviceKey, byte[]? ephemeral, byte[]? nonce)
    {
        Side = side; pairingKey = pairing.Key; this.deviceKey = deviceKey; fixedEphemeral = ephemeral; fixedNonce = nonce;
    }

    /// <summary>Client (the iPhone; used by the tests' fake iPhone). <paramref name="deviceKey"/> is its X25519 private key.</summary>
    public static RemoteSession Client(PairingSecret pairing, byte[] deviceKey, byte[]? nonce = null) => new(Role.Client, pairing, deviceKey, null, nonce);

    /// <summary>Server (this computer). <paramref name="ephemeral"/> and <paramref name="nonce"/> are only for tests.</summary>
    public static RemoteSession Server(PairingSecret pairing, byte[]? ephemeral = null, byte[]? nonce = null) => new(Role.Server, pairing, null, ephemeral, nonce);

    private static byte[] Utf8(JsonNode n) => Encoding.UTF8.GetBytes(n.ToJsonString(RemoteJson.Options));

    // MARK: Handshake

    public byte[] ClientHelloFrame(string deviceId, string deviceName)
    {
        if (Side != Role.Client) throw new InvalidOperationException("client only");
        var nonce = fixedNonce ?? RandomNumberGenerator.GetBytes(16);
        var name = new System.Globalization.StringInfo(deviceName);
        var hello = new RemoteClientHello(RemoteProtocol.Version, deviceId,
            name.LengthInTextElements > 64 ? name.SubstringByTextElements(0, 64) : deviceName, Curve25519.PublicKey(deviceKey!), nonce);
        var json = Utf8(hello.ToJson());
        clientHelloBytes = json;
        return Frame([.. json, .. Tag(json)]);
    }

    /// <summary>Tests: a client hello sent as these exact bytes (the shared vectors' fixed JSON).</summary>
    internal void UseClientHello(byte[] json) => clientHelloBytes = json;

    /// <summary>Server: the answer to a client hello (call after <see cref="Event.ClientHello"/>).</summary>
    public byte[] ServerHelloFrame(string serverId, string serverName)
    {
        if (Side != Role.Server || PeerHello is not RemoteClientHello ch) throw new RemoteException("notReady");
        var eph = fixedEphemeral ?? Curve25519.NewPrivateKey();
        ephemeral = eph;
        var info = new System.Globalization.StringInfo(serverName);
        var sh = new RemoteServerHello(RemoteProtocol.Version, serverId,
            info.LengthInTextElements > 64 ? info.SubstringByTextElements(0, 64) : serverName, Curve25519.PublicKey(eph), fixedNonce ?? RandomNumberGenerator.GetBytes(16));
        var json = Utf8(sh.ToJson());
        DeriveKeys(Curve25519.Shared(eph, ch.DevicePublicKey), json);
        return Frame([.. json, .. Tag([.. clientHelloBytes, .. json])]);
    }

    // MARK: Messages

    public byte[] Seal(RemoteMessage m) => SealJson(Utf8(m.ToJson()));

    internal byte[] SealJson(byte[] plain)
    {
        if (sendBox is null) throw new RemoteException("notReady");
        sendCounter += 1;
        var nonce = Nonce(sendCounter);
        var cipher = new byte[plain.Length];
        var tag = new byte[16];
        sendBox.Encrypt(nonce, plain, cipher, tag);
        return Frame([.. nonce.AsSpan(0, 8), .. cipher, .. tag]);
    }

    /// <summary>Feed bytes from the stream. Throws <see cref="RemoteException"/> when the connection must be closed.</summary>
    public List<Event> Receive(ReadOnlySpan<byte> bytes)
    {
        buffer = [.. buffer, .. bytes];
        var events = new List<Event>();
        while (buffer.Length >= 4)
        {
            uint len = BinaryPrimitives.ReadUInt32BigEndian(buffer);
            if (len > RemoteProtocol.MaxFrame) throw new RemoteException("frameTooLarge");
            if (buffer.Length < 4 + (int)len) break;
            var payload = buffer.AsSpan(4, (int)len).ToArray();
            buffer = buffer.AsSpan(4 + (int)len).ToArray();
            if (Handle(payload) is Event e) events.Add(e);
        }
        return events;
    }

    private Event? Handle(byte[] p)
    {
        if (receiveBox is not null)
        {
            if (p.Length < 8 + 16) throw new RemoteException("decryptFailed");
            ulong counter = BinaryPrimitives.ReadUInt64BigEndian(p);
            if (counter <= receiveCounter) throw new RemoteException("outOfOrder");
            var plain = new byte[p.Length - 24];
            try { receiveBox.Decrypt(Nonce(counter), p.AsSpan(8, p.Length - 24), p.AsSpan(p.Length - 16), plain); }
            catch (CryptographicException) { throw new RemoteException("decryptFailed"); }
            receiveCounter = counter;
            JsonNode? node;
            try { node = JsonNode.Parse(plain); }
            catch (JsonException) { return new Event.Unknown(Encoding.UTF8.GetString(plain)); }
            return RemoteMessage.FromJson(node) is RemoteMessage m ? new Event.Message(m) : new Event.Unknown(Encoding.UTF8.GetString(plain));
        }
        if (p.Length <= RemoteProtocol.TagSize) throw new RemoteException("badHello");
        var json = p.AsSpan(0, p.Length - RemoteProtocol.TagSize).ToArray();
        var t = p.AsSpan(p.Length - RemoteProtocol.TagSize).ToArray();
        JsonNode? parsed;
        if (Side == Role.Server)
        {
            if (!CryptographicOperations.FixedTimeEquals(Tag(json), t)) throw new RemoteException("wrongPairingCode");
            try { parsed = JsonNode.Parse(json); } catch (JsonException) { throw new RemoteException("badHello"); }
            if (RemoteClientHello.FromJson(parsed) is not RemoteClientHello ch) throw new RemoteException("badHello");
            if (ch.Version != RemoteProtocol.Version) throw new RemoteException("versionMismatch");
            if (ch.DevicePublicKey.Length != 32 || ch.Nonce.Length != 16 || ch.DeviceId.Length == 0 || new System.Globalization.StringInfo(ch.DeviceId).LengthInTextElements > 64)
                throw new RemoteException("badHello");
            var hello = ch with { DeviceName = RemoteClientHello.SanitizedName(ch.DeviceName) };
            clientHelloBytes = json;
            PeerHello = hello;
            return new Event.ClientHello(hello, ConfirmCode(json));
        }
        if (!CryptographicOperations.FixedTimeEquals(Tag([.. clientHelloBytes, .. json]), t)) throw new RemoteException("wrongPairingCode");
        try { parsed = JsonNode.Parse(json); } catch (JsonException) { throw new RemoteException("badHello"); }
        if (RemoteServerHello.FromJson(parsed) is not RemoteServerHello sh) throw new RemoteException("badHello");
        if (sh.Version != RemoteProtocol.Version) throw new RemoteException("versionMismatch");
        DeriveKeys(Curve25519.Shared(deviceKey!, sh.EphemeralPublicKey), json);
        return new Event.ServerHello(sh, ConfirmCode(clientHelloBytes));
    }

    private void DeriveKeys(byte[] shared, byte[] serverHello)
    {
        byte[] info = [.. "TwinKeys remote v1"u8, .. SHA256.HashData([.. clientHelloBytes, .. serverHello])];
        var km = Hkdf.Sha256(shared, pairingKey, info, 64);
        byte[] c2s = km[..32], s2c = km[32..];
        Keys = (c2s, s2c);
        if (Side == Role.Client) { sendBox = new ChaCha20Poly1305(c2s); receiveBox = new ChaCha20Poly1305(s2c); }
        else { sendBox = new ChaCha20Poly1305(s2c); receiveBox = new ChaCha20Poly1305(c2s); }
    }

    internal byte[] Tag(byte[] data) => HMACSHA256.HashData(pairingKey, (byte[])[.. "remote"u8, .. data]);

    /// <summary>The 4 digits both sides show while the computer asks for approval (from the client hello).</summary>
    public static string ConfirmCode(byte[] clientHello)
    {
        var h = SHA256.HashData(clientHello);
        uint n = BinaryPrimitives.ReadUInt32BigEndian(h) % 10000;
        return n.ToString("D4", System.Globalization.CultureInfo.InvariantCulture);
    }

    internal static byte[] Nonce(ulong counter)
    {
        var n = new byte[12];
        BinaryPrimitives.WriteUInt64BigEndian(n, counter);
        return n;
    }

    internal static byte[] Frame(byte[] payload)
    {
        var f = new byte[4 + payload.Length];
        BinaryPrimitives.WriteUInt32BigEndian(f, (uint)payload.Length);
        payload.CopyTo(f, 4);
        return f;
    }
}

internal static class RemoteJson
{
    /// <summary>Non-ASCII text as UTF-8 (like Swift's JSONEncoder), not escaped.</summary>
    public static readonly JsonSerializerOptions Options = new() { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
}
