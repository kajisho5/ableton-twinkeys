using System.Security.Cryptography;

namespace TwinKeys.Core;

/// <summary>
/// Authentication and encryption of TwinKeys packets, protocol version 2 (port of
/// Sources/TwinKeysCore/SecureChannel.swift).
/// <list type="bullet">
/// <item>Hello / HelloAck are signed with HMAC-SHA256 under the pairing key K (16-byte tag).</item>
/// <item>Every other packet is sealed with ChaCha20-Poly1305 under HMAC(K, "dir" ‖ sender nonce ‖ receiver nonce).
/// The 12-byte header is the associated data; the AEAD nonce is session ‖ seq ‖ 0.</item>
/// </list>
/// ChaCha20Poly1305 needs Windows 10 build 20142 or later (docs/design-windows.md 2.4).
/// </summary>
public sealed class SecureChannel
{
    public const int TagSize = 16;
    public PairingSecret Secret { get; }
    /// <summary>Random per launch; part of every link key, so traffic of an earlier run cannot be replayed.</summary>
    public byte[] MyNonce { get; }

    public SecureChannel(PairingSecret secret, byte[]? myNonce = null)
    {
        Secret = secret;
        MyNonce = myNonce is null ? RandomNonce() : (byte[])myNonce.Clone();
    }

    public static byte[] RandomNonce() => RandomNumberGenerator.GetBytes(16);

    public static bool IsSupported => ChaCha20Poly1305.IsSupported;

    internal byte[] DirectionKey(byte[] sender, byte[] receiver) =>
        HMACSHA256.HashData(Secret.Key, (byte[])[.. "dir"u8, .. sender, .. receiver]);

    private byte[] HelloTag(ReadOnlySpan<byte> data) => HMACSHA256.HashData(Secret.Key, data)[..TagSize];

    /// <summary>Bytes to send. <paramref name="peerNonce"/> is needed for everything except hello/helloAck; null if unknown.</summary>
    public byte[]? Seal(Packet packet, byte[]? peerNonce)
    {
        var plain = packet.Encode();
        if (packet.Body.IsHelloOrAck) return [.. plain, .. HelloTag(plain)];
        if (peerNonce is null) return null;
        var header = plain.AsSpan(0, WireProtocol.HeaderSize);
        var payload = plain.AsSpan(WireProtocol.HeaderSize);
        var key = DirectionKey(MyNonce, peerNonce);
        var output = new byte[plain.Length + TagSize];
        header.CopyTo(output);
        Span<byte> nonce = stackalloc byte[12];
        plain.AsSpan(4, 8).CopyTo(nonce);
        using var aead = new ChaCha20Poly1305(key);
        aead.Encrypt(nonce, payload, output.AsSpan(WireProtocol.HeaderSize, payload.Length), output.AsSpan(plain.Length, TagSize), header);
        return output;
    }

    public enum OpenError { Malformed, BadSignature, NoLinkKey, BadSeal }

    public sealed class OpenException(OpenError error) : Exception($"Cannot open packet: {error}")
    {
        public OpenError Error { get; } = error;
    }

    /// <summary>Checks a received hello/helloAck. Returns the packet (with the peer's nonce inside).</summary>
    public Packet OpenHello(byte[] bytes)
    {
        if (bytes.Length <= WireProtocol.HeaderSize + TagSize) throw new OpenException(OpenError.Malformed);
        var plain = bytes.AsSpan(0, bytes.Length - TagSize);
        var tag = bytes.AsSpan(bytes.Length - TagSize);
        if (!CryptographicOperations.FixedTimeEquals(tag, HelloTag(plain))) throw new OpenException(OpenError.BadSignature);
        var p = Packet.TryDecode(plain) ?? throw new OpenException(OpenError.Malformed);
        if (!p.Body.IsHelloOrAck) throw new OpenException(OpenError.Malformed);
        return p;
    }

    /// <summary>Opens any other packet from a peer whose nonce is known.</summary>
    public Packet Open(byte[] bytes, byte[] peerNonce)
    {
        if (bytes.Length < WireProtocol.HeaderSize + TagSize) throw new OpenException(OpenError.Malformed);
        var header = bytes.AsSpan(0, WireProtocol.HeaderSize);
        var cipher = bytes.AsSpan(WireProtocol.HeaderSize, bytes.Length - WireProtocol.HeaderSize - TagSize);
        var tag = bytes.AsSpan(bytes.Length - TagSize);
        var key = DirectionKey(peerNonce, MyNonce);
        Span<byte> nonce = stackalloc byte[12];
        header[4..12].CopyTo(nonce);
        var plain = new byte[bytes.Length - TagSize];
        header.CopyTo(plain);
        try
        {
            using var aead = new ChaCha20Poly1305(key);
            aead.Decrypt(nonce, cipher, tag, plain.AsSpan(WireProtocol.HeaderSize), header);
        }
        catch (CryptographicException)
        {
            throw new OpenException(OpenError.BadSeal);
        }
        var p = Packet.TryDecode(plain) ?? throw new OpenException(OpenError.Malformed);
        if (p.Body.IsHelloOrAck) throw new OpenException(OpenError.Malformed);
        return p;
    }

    /// <summary>True if the bytes are a hello or helloAck (by header type; not yet verified).</summary>
    public static bool IsHello(ReadOnlySpan<byte> bytes) =>
        bytes.Length >= WireProtocol.HeaderSize && (bytes[3] == 0x01 || bytes[3] == 0x02);
}
