using System.Security.Cryptography;

namespace TwinKeys.Core;

/// <summary>
/// HKDF-SHA256 (RFC 5869), as CryptoKit's <c>HKDF&lt;SHA256&gt;</c>. Only the iPhone link uses it
/// (phase 3, docs/design-windows.md 6.5); phase 1 checks it against shared/test-vectors/hkdf.json.
/// </summary>
public static class Hkdf
{
    public static byte[] Sha256(byte[] ikm, byte[] salt, byte[] info, int length) =>
        HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, length, salt, info);
}
