import XCTest
@testable import TwinKeysCore

final class PairingTests: XCTestCase {
    func hex(_ s: String) -> [UInt8] {
        let c = Array(s.replacingOccurrences(of: " ", with: ""))
        return stride(from: 0, to: c.count, by: 2).map { UInt8(String(c[$0...$0 + 1]), radix: 16)! }
    }

    // RFC 7914 section 11, PBKDF2-HMAC-SHA-256 test vectors.
    func testPBKDF2Vector1() {
        XCTAssertEqual(Pairing.pbkdf2(password: Array("passwd".utf8), salt: Array("salt".utf8), iterations: 1, length: 64),
                       hex("55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"))
    }

    func testPBKDF2Vector2() {
        XCTAssertEqual(Pairing.pbkdf2(password: Array("Password".utf8), salt: Array("NaCl".utf8), iterations: 80000, length: 64),
                       hex("4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"))
    }

    func testCodeFormat() {
        let c = Pairing.generate()
        XCTAssertEqual(c.count, 11)
        XCTAssertEqual(Array(c)[5], "-")
        XCTAssertNotNil(Pairing.normalize(c))
        XCTAssertNotEqual(Pairing.generate(), Pairing.generate())
        XCTAssertEqual(Pairing.normalize(" k7mq2 wx9tp "), "K7MQ2WX9TP")
        XCTAssertEqual(Pairing.normalize("K7MQ2-WX9TP"), "K7MQ2WX9TP")
        XCTAssertNil(Pairing.normalize("K7MQ2-WX9T"))     // too short
        XCTAssertNil(Pairing.normalize("K7MQ2-WX9T0"))    // 0 is not in the alphabet
        XCTAssertEqual(Pairing.formatted("K7MQ2WX9TP"), "K7MQ2-WX9TP")
    }

    func testSameCodeSameKeyDifferentCodeDifferentKey() {
        let a = PairingSecret(code: "K7MQ2-WX9TP")!, b = PairingSecret(code: "k7mq2wx9tp")!, c = PairingSecret(code: "K7MQ2-WX9TQ")!
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertNotEqual(a.fingerprint, c.fingerprint)
        XCTAssertNil(PairingSecret(code: "short"))
    }

    func testSealOpenRoundTripAndTamper() throws {
        let s = PairingSecret(keyBytes: Array(1...32))
        let a = SecureChannel(secret: s), b = SecureChannel(secret: s)
        let note = Packet(session: 4, seq: 9, body: .noteOn(channel: 0, note: 60, velocity: 100))
        XCTAssertNil(a.seal(note, peerNonce: nil))                  // no link key before the handshake
        let bytes = try XCTUnwrap(a.seal(note, peerNonce: b.myNonce))
        XCTAssertEqual(try b.open(bytes, peerNonce: a.myNonce), note)
        XCTAssertFalse(bytes.contains(60) && bytes.contains(100) && bytes.firstIndex(of: 60)! > 11)  // payload is not plain
        var t = bytes; t[5] ^= 1                                     // header is authenticated
        XCTAssertThrowsError(try b.open(t, peerNonce: a.myNonce))
        // Other direction uses another key.
        XCTAssertThrowsError(try a.open(bytes, peerNonce: b.myNonce))
        // Hello: signed, readable, rejected under another key.
        let hello = Packet(session: 4, seq: 1, body: .hello(instanceID: UUID(), nonce: a.myNonce, name: "A"))
        let hb = try XCTUnwrap(a.seal(hello, peerNonce: nil))
        XCTAssertEqual(try b.openHello(hb), hello)
        let other = SecureChannel(secret: PairingSecret(keyBytes: Array(repeating: 9, count: 32)))
        XCTAssertThrowsError(try other.openHello(hb)) { XCTAssertEqual($0 as? SecureChannel.OpenError, .badSignature) }
        XCTAssertLessThanOrEqual(hb.count, WireProtocol.maxPacketSize)
    }
}
