import Crypto
import Foundation

/// Authentication and encryption of TwinKeys packets (protocol version 2).
///
/// - Hello / HelloAck are signed with HMAC-SHA256 under the pairing key K (16-byte tag).
///   They carry the sender's per-launch nonce.
/// - Every other packet is sealed with ChaCha20-Poly1305 under a key for its direction:
///   HMAC(K, "dir" ‖ sender nonce ‖ receiver nonce). The 12-byte header is authenticated data;
///   the AEAD nonce is session ‖ seq ‖ 0, unique per sender and packet.
public struct SecureChannel: Sendable {
    public static let tagSize = 16
    public let secret: PairingSecret
    /// Random per launch; part of every link key, so traffic of an earlier run cannot be replayed.
    public let myNonce: [UInt8]

    public init(secret: PairingSecret, myNonce: [UInt8] = SecureChannel.randomNonce()) {
        self.secret = secret
        self.myNonce = myNonce
    }

    public static func randomNonce() -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        return (0..<16).map { _ in UInt8.random(in: 0...255, using: &rng) }
    }

    private func directionKey(from sender: [UInt8], to receiver: [UInt8]) -> SymmetricKey {
        SymmetricKey(data: Array(HMAC<SHA256>.authenticationCode(for: Array("dir".utf8) + sender + receiver, using: secret.key)))
    }

    private func helloTag(_ data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: secret.key).prefix(Self.tagSize))
    }

    /// Bytes to send. `peerNonce` is needed for everything except hello/helloAck; nil if unknown.
    public func seal(_ packet: Packet, peerNonce: [UInt8]?) -> [UInt8]? {
        let plain = packet.encode()
        switch packet.body {
        case .hello, .helloAck:
            return plain + helloTag(plain)
        default:
            guard let peerNonce else { return nil }
            let header = Array(plain[0..<WireProtocol.headerSize])
            let payload = Array(plain[WireProtocol.headerSize...])
            let key = directionKey(from: myNonce, to: peerNonce)
            guard let nonce = try? ChaChaPoly.Nonce(data: Array(plain[4..<12]) + [0, 0, 0, 0]),
                  let box = try? ChaChaPoly.seal(payload, using: key, nonce: nonce, authenticating: header) else { return nil }
            return header + Array(box.ciphertext) + Array(box.tag)
        }
    }

    public enum OpenError: Error, Equatable { case malformed, badSignature, noLinkKey, badSeal }

    /// Checks a received hello/helloAck. Returns the packet (with the peer's nonce inside).
    public func openHello(_ bytes: [UInt8]) throws -> Packet {
        guard bytes.count > WireProtocol.headerSize + Self.tagSize else { throw OpenError.malformed }
        let plain = Array(bytes.dropLast(Self.tagSize))
        let tag = Array(bytes.suffix(Self.tagSize))
        guard constantTimeEqual(tag, helloTag(plain)) else { throw OpenError.badSignature }
        guard let p = try? Packet.decode(plain) else { throw OpenError.malformed }
        switch p.body { case .hello, .helloAck: return p; default: throw OpenError.malformed }
    }

    /// Opens any other packet from a peer whose nonce is known.
    public func open(_ bytes: [UInt8], peerNonce: [UInt8]) throws -> Packet {
        guard bytes.count >= WireProtocol.headerSize + Self.tagSize else { throw OpenError.malformed }
        let header = Array(bytes[0..<WireProtocol.headerSize])
        let body = Array(bytes[WireProtocol.headerSize...])
        let key = directionKey(from: peerNonce, to: myNonce)
        guard let nonce = try? ChaChaPoly.Nonce(data: Array(header[4..<12]) + [0, 0, 0, 0]),
              let box = try? ChaChaPoly.SealedBox(nonce: nonce,
                                                 ciphertext: body.dropLast(Self.tagSize),
                                                 tag: body.suffix(Self.tagSize)),
              let payload = try? ChaChaPoly.open(box, using: key, authenticating: header) else { throw OpenError.badSeal }
        guard let p = try? Packet.decode(header + Array(payload)) else { throw OpenError.malformed }
        switch p.body { case .hello, .helloAck: throw OpenError.malformed; default: return p }
    }

    /// True if the bytes are a hello or helloAck (by header type; not yet verified).
    public static func isHello(_ bytes: [UInt8]) -> Bool {
        bytes.count >= WireProtocol.headerSize && (bytes[3] == 0x01 || bytes[3] == 0x02)
    }

    private func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var d: UInt8 = 0
        for i in 0..<a.count { d |= a[i] ^ b[i] }
        return d == 0
    }
}
