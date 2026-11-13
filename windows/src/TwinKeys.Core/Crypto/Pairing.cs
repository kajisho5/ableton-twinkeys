using System.Security.Cryptography;
using System.Text;

namespace TwinKeys.Core;

/// <summary>
/// The pairing code both computers share (port of Sources/TwinKeysCore/Pairing.swift). Only
/// computers with the same code can link, and their traffic is authenticated and encrypted with
/// keys derived from it.
/// </summary>
public static class Pairing
{
    /// <summary>31 characters without look-alikes (no 0/O, 1/I/L).</summary>
    public const string Alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
    public const int Length = 10;
    public static readonly byte[] Salt = Encoding.UTF8.GetBytes("TwinKeys pairing v2");
    public const int Iterations = 100_000;

    /// <summary>A new random code, shown as "XXXXX-XXXXX".</summary>
    public static string Generate()
    {
        var chars = new char[Length];
        for (int i = 0; i < Length; i++) chars[i] = Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)];
        return Formatted(new string(chars));
    }

    /// <summary>Upper case, without spaces and hyphens. Null if it is not a valid code.</summary>
    public static string? Normalize(string input)
    {
        var sb = new StringBuilder();
        foreach (var ch in input.ToUpperInvariant())
        {
            if (char.IsWhiteSpace(ch) || ch == '-' || ch == '‐' || ch == '－') continue;
            sb.Append(ch);
        }
        var s = sb.ToString();
        if (s.Length != Length) return null;
        foreach (var ch in s) if (!Alphabet.Contains(ch)) return null;
        return s;
    }

    public static string Formatted(string normalized) =>
        normalized.Length == Length ? normalized[..5] + "-" + normalized[5..] : normalized;

    /// <summary>PBKDF2-HMAC-SHA256 (RFC 8018).</summary>
    public static byte[] Pbkdf2(byte[] password, byte[] salt, int iterations, int length) =>
        Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, length);
}

/// <summary>Long-term key derived from a pairing code (slow on purpose: 100 000 HMAC rounds).</summary>
public sealed class PairingSecret
{
    public byte[] Key { get; }
    /// <summary>Short non-secret fingerprint, for logs (never the code itself).</summary>
    public string Fingerprint { get; }

    public PairingSecret(byte[] keyBytes)
    {
        Key = (byte[])keyBytes.Clone();
        var fp = SHA256.HashData([.. "fp"u8, .. keyBytes]);
        Fingerprint = Convert.ToHexStringLower(fp.AsSpan(0, 4));
    }

    /// <summary>Null if the code is not valid.</summary>
    public static PairingSecret? FromCode(string code)
    {
        var n = Pairing.Normalize(code);
        if (n is null) return null;
        return new PairingSecret(Pairing.Pbkdf2(Encoding.UTF8.GetBytes(n), Pairing.Salt, Pairing.Iterations, 32));
    }
}
