import Crypto
import Foundation

/// The pairing code both Macs share. Only Macs with the same code can link, and their
/// traffic is authenticated and encrypted with keys derived from it.
public enum Pairing {
    /// 31 characters without look-alikes (no 0/O, 1/I/L).
    public static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
    public static let length = 10
    static let salt = Array("TwinKeys pairing v2".utf8)
    public static let iterations = 100_000

    /// A new random code, shown as "XXXXX-XXXXX".
    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        let raw = String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
        return formatted(raw)
    }

    /// Upper case, without spaces and hyphens. Nil if it is not a valid code.
    public static func normalize(_ input: String) -> String? {
        let s = input.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "‐" && $0 != "－" }
        guard s.count == length, s.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return s
    }

    public static func formatted(_ normalized: String) -> String {
        let chars = Array(normalized)
        guard chars.count == length else { return normalized }
        return String(chars[0..<5]) + "-" + String(chars[5...])
    }

    /// PBKDF2-HMAC-SHA256 (RFC 8018), built on swift-crypto's HMAC.
    public static func pbkdf2(password: [UInt8], salt: [UInt8], iterations: Int, length: Int) -> [UInt8] {
        let key = SymmetricKey(data: password)
        var out: [UInt8] = []
        var block: UInt32 = 1
        while out.count < length {
            var u = Array(HMAC<SHA256>.authenticationCode(
                for: salt + [UInt8(block >> 24), UInt8((block >> 16) & 0xFF), UInt8((block >> 8) & 0xFF), UInt8(block & 0xFF)],
                using: key))
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Array(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for i in 0..<t.count { t[i] ^= u[i] }
                }
            }
            out += t
            block += 1
        }
        return Array(out.prefix(length))
    }
}

/// Long-term key derived from a pairing code (slow on purpose: ~100 000 HMAC rounds).
public struct PairingSecret: Sendable {
    public let key: SymmetricKey
    /// Short non-secret fingerprint, for logs (never the code itself).
    public let fingerprint: String

    public init?(code: String) {
        guard let n = Pairing.normalize(code) else { return nil }
        let k = Pairing.pbkdf2(password: Array(n.utf8), salt: Pairing.salt, iterations: Pairing.iterations, length: 32)
        self.init(keyBytes: k)
    }

    /// For tests: use key bytes directly.
    public init(keyBytes: [UInt8]) {
        key = SymmetricKey(data: keyBytes)
        let fp = SHA256.hash(data: Array("fp".utf8) + keyBytes)
        fingerprint = fp.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
