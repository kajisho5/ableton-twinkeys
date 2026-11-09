import XCTest
@testable import TwinKeysCore

final class ProtocolTests: XCTestCase {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func roundTrip(_ body: PacketBody) throws {
        let p = Packet(session: 0xDEADBEEF, seq: 0x01020304, body: body)
        let bytes = p.encode()
        XCTAssertLessThanOrEqual(bytes.count, WireProtocol.maxPacketSize)
        XCTAssertEqual(try Packet.decode(bytes), p)
    }

    func testRoundTripAllTypes() throws {
        try roundTrip(.hello(instanceID: id, name: "Stage Mac A"))
        try roundTrip(.helloAck(instanceID: id, name: ""))
        try roundTrip(.bye)
        try roundTrip(.noteOn(channel: 15, note: 127, velocity: 1))
        try roundTrip(.noteOff(channel: 0, note: 0))
        try roundTrip(.allNotesOff)
        try roundTrip(.heartbeat(timestampNanos: 0x0123_4567_89AB_CDEF))
        try roundTrip(.heartbeatAck(timestampNanos: UInt64.max))
        try roundTrip(.held(channel: 3, notes: [60, 64, 67]))
        try roundTrip(.held(channel: 0, notes: []))
    }

    func testHeaderLayout() {
        let b = Packet(session: 1, seq: 2, body: .noteOn(channel: 0, note: 60, velocity: 100)).encode()
        XCTAssertEqual(b, [0x54, 0x4B, 1, 0x10, 0, 0, 0, 1, 0, 0, 0, 2, 0, 60, 100])
    }

    func testLongNameIsTruncatedOnCharacterBoundary() throws {
        let name = String(repeating: "鍵", count: 20)   // 3 bytes each
        let p = try Packet.decode(Packet(session: 1, seq: 1, body: .hello(instanceID: id, name: name)).encode())
        guard case let .hello(_, n) = p.body else { return XCTFail() }
        XCTAssertEqual(n, String(repeating: "鍵", count: 10))
    }

    func testRejectsBadPackets() {
        XCTAssertThrowsError(try Packet.decode([0x54, 0x4B, 1])) { XCTAssertEqual($0 as? DecodeError, .tooShort) }
        XCTAssertThrowsError(try Packet.decode([0x00, 0x4B, 1, 0x20, 0, 0, 0, 0, 0, 0, 0, 0])) { XCTAssertEqual($0 as? DecodeError, .badMagic) }
        XCTAssertThrowsError(try Packet.decode([0x54, 0x4B, 9, 0x20, 0, 0, 0, 0, 0, 0, 0, 0])) { XCTAssertEqual($0 as? DecodeError, .unsupportedVersion(9)) }
        XCTAssertThrowsError(try Packet.decode([0x54, 0x4B, 1, 0x77, 0, 0, 0, 0, 0, 0, 0, 0])) { XCTAssertEqual($0 as? DecodeError, .unknownType(0x77)) }
        // Note number 200 is not valid MIDI.
        XCTAssertThrowsError(try Packet.decode([0x54, 0x4B, 1, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 100])) { XCTAssertEqual($0 as? DecodeError, .badPayload) }
        // Truncated payload.
        XCTAssertThrowsError(try Packet.decode([0x54, 0x4B, 1, 0x30, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2])) { XCTAssertEqual($0 as? DecodeError, .badPayload) }
    }

    func testSequenceFilterDropsDuplicatesAndReordered() {
        var f = SequenceFilter()
        XCTAssertTrue(f.accept(session: 7, seq: 10))
        XCTAssertFalse(f.accept(session: 7, seq: 10))   // duplicate (the second copy we send on purpose)
        XCTAssertTrue(f.accept(session: 7, seq: 12))    // a gap is fine (packet 11 lost)
        XCTAssertFalse(f.accept(session: 7, seq: 11))   // arrived late: dropped
        XCTAssertTrue(f.accept(session: 7, seq: 13))
    }

    func testSequenceFilterWrapAround() {
        var f = SequenceFilter()
        XCTAssertTrue(f.accept(session: 1, seq: UInt32.max - 1))
        XCTAssertTrue(f.accept(session: 1, seq: UInt32.max))
        XCTAssertTrue(f.accept(session: 1, seq: 0))
        XCTAssertTrue(f.accept(session: 1, seq: 1))
        XCTAssertFalse(f.accept(session: 1, seq: UInt32.max))
    }

    func testLatePacketFromPreviousSessionIsDropped() {
        var f = SequenceFilter()
        XCTAssertTrue(f.accept(session: 1, seq: 10))
        XCTAssertTrue(f.accept(session: 2, seq: 5))     // peer restarted
        XCTAssertFalse(f.accept(session: 1, seq: 11))   // delayed packet from before the restart
        XCTAssertFalse(f.accept(session: 2, seq: 5))    // second copy is still a duplicate
        XCTAssertTrue(f.accept(session: 2, seq: 6))
    }

    func testSequenceFilterNewSessionResets() {
        var f = SequenceFilter()
        XCTAssertTrue(f.accept(session: 1, seq: 500))
        // Peer restarted: counts from the beginning again with a new session value.
        XCTAssertTrue(f.accept(session: 2, seq: 0))
        XCTAssertTrue(f.accept(session: 2, seq: 1))
    }

    func testPeerFromTXTExcludesSelf() {
        XCTAssertNil(TXTKeys.peer(from: ["id": "me", "modes": "sr"], serviceName: "Mine", ownID: "me"))
        XCTAssertNil(TXTKeys.peer(from: ["modes": "sr"], serviceName: "NoID", ownID: "me"))
        let p = TXTKeys.peer(from: ["id": "other", "modes": "r"], serviceName: "Backup", ownID: "me")
        XCTAssertEqual(p, PeerInfo(id: "other", name: "Backup", sends: false, receives: true))
        XCTAssertEqual(p?.modeText, "Receive")
        XCTAssertEqual(TXTKeys.modes(sends: true, receives: true), "sr")
        XCTAssertTrue(TXTKeys.peer(from: ["id": "x", "v": "1"], serviceName: "A", ownID: "me")!.isCompatible)
        XCTAssertFalse(TXTKeys.peer(from: ["id": "x", "v": "2"], serviceName: "A", ownID: "me")!.isCompatible)
        XCTAssertTrue(TXTKeys.isDuplicateOfUs(["id": "me", "boot": "b2"], ownID: "me", ownBoot: "b1"))
        XCTAssertFalse(TXTKeys.isDuplicateOfUs(["id": "me", "boot": "b1"], ownID: "me", ownBoot: "b1"))
        XCTAssertFalse(TXTKeys.isDuplicateOfUs(["id": "other", "boot": "b2"], ownID: "me", ownBoot: "b1"))
    }
}
