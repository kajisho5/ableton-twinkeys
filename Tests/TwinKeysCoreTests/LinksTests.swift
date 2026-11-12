import Crypto
import XCTest
@testable import TwinKeysCore

/// Connection display (docs/design-links.md): the iPhone tells its Apple Watch with each ping, and the
/// main Mac tells the backup how many iPhones it has (packet remoteSummary).
final class LinksTests: XCTestCase {
    let secret = PairingSecret(keyBytes: Array(repeating: 9, count: 32))

    /// The ping as TwinKeys 2.2.0 and TwinKeys Remote 1.2.0 declare it (one Double), to check both
    /// directions of compatibility. Other cases do not matter: the decoder looks at the case key only.
    private enum OldMessage: Codable, Equatable {
        case ping(Double)
        case lock(Bool)
    }

    func testPingCarriesTheWatchAndRoundTrips() throws {
        let w = RemoteWatchState(paired: true, appInstalled: true, reachable: false)
        let none = RemoteWatchState(paired: false, appInstalled: false, reachable: false)
        for m: RemoteMessage in [.ping(12.5, watch: w), .ping(3), .ping(4, watch: none)] {
            XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(m)), m)
        }
        // Through the sealed channel too.
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = try server.receive(client.clientHello(deviceID: "d", deviceName: "n"))
        _ = try client.receive(server.serverHello(serverID: "m", serverName: "m"))
        XCTAssertEqual(try server.receive(client.seal(.ping(7, watch: w))), [.message(.ping(7, watch: w))])
        XCTAssertEqual(try server.receive(client.seal(.ping(8))), [.message(.ping(8, watch: nil))])
    }

    func testOlderMacsReadTheNewPingAndNewMacsReadTheOldOne() throws {
        let w = RemoteWatchState(paired: true, appInstalled: true, reachable: true)
        let new = try JSONEncoder().encode(RemoteMessage.ping(42, watch: w))
        // An older Mac skips the extra key: a plain ping (it answers with a pong and stays connected).
        XCTAssertEqual(try JSONDecoder().decode(OldMessage.self, from: new), .ping(42))
        // A ping from an older iPhone: no watch.
        let old = try JSONEncoder().encode(OldMessage.ping(5))
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: old), .ping(5, watch: nil))
        // Nothing to tell: no "watch" key at all (the same JSON as before).
        let plain = try JSONEncoder().encode(RemoteMessage.ping(5))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: [String: Any]])
        XCTAssertEqual(obj["ping"]?.keys.sorted(), ["_0"])
        let full = try XCTUnwrap(JSONSerialization.jsonObject(with: new) as? [String: [String: Any]])
        XCTAssertEqual(full["ping"]?.keys.sorted(), ["_0", "watch"])
    }

    /// Why the watch rides on the ping: a message case the other side does not know cannot be decoded,
    /// and the Mac (RemoteServer) closes the connection when `receive` throws.
    func testAnUnknownMessageCaseCannotBeDecoded() throws {
        let unknown = Data(#"{"watchState":{"paired":true,"appInstalled":true,"reachable":true}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteMessage.self, from: unknown))
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = try server.receive(client.clientHello(deviceID: "d", deviceName: "n"))
        _ = try client.receive(server.serverHello(serverID: "m", serverName: "m"))
        // The new ping goes through the same session without trouble.
        XCTAssertNoThrow(try server.receive(client.seal(.ping(1, watch: .init(paired: true, appInstalled: false, reachable: false)))))
    }

    func testWatchLevels() {
        let reachable = RemoteWatchState(paired: true, appInstalled: true, reachable: true)
        let away = RemoteWatchState(paired: true, appInstalled: true, reachable: false)
        let notInstalled = RemoteWatchState(paired: true, appInstalled: false, reachable: false)
        let notPaired = RemoteWatchState(paired: false, appInstalled: false, reachable: false)
        XCTAssertEqual(reachable.level, .reachable)
        XCTAssertEqual(away.level, .notReachable)
        XCTAssertEqual(notInstalled.level, .absent)
        XCTAssertEqual(notPaired.level, .absent)
        // Several iPhones: the best watch counts; an iPhone that tells nothing adds nothing.
        XCTAssertEqual(WatchLevel.combined([]), .absent)
        XCTAssertEqual(WatchLevel.combined([nil]), .absent)
        XCTAssertEqual(WatchLevel.combined([nil, away]), .notReachable)
        XCTAssertEqual(WatchLevel.combined([away, reachable, notPaired]), .reachable)
        XCTAssertEqual(WatchLevel.combined([notInstalled, notPaired]), .absent)
        XCTAssertEqual(WatchLevel(rawValue: WatchLevel.notReachable.rawValue), .notReachable)
    }

    func testRemoteSummaryPacketRoundTrips() throws {
        let p = Packet(session: 5, seq: 6, body: .remoteSummary(phones: 2, watch: WatchLevel.notReachable.rawValue))
        let bytes = p.encode()
        XCTAssertEqual(bytes, [0x54, 0x4B, 2, 0x21, 0, 0, 0, 5, 0, 0, 0, 6, 2, 1])
        XCTAssertEqual(try Packet.decode(bytes), p)
        let most = Packet(session: 1, seq: 1, body: .remoteSummary(phones: 255, watch: WatchLevel.reachable.rawValue))
        XCTAssertEqual(try Packet.decode(most.encode()), most)
        // Cut short.
        XCTAssertThrowsError(try Packet.decode(Array(bytes.dropLast()))) { XCTAssertEqual($0 as? DecodeError, .badPayload) }
        // A later version may add bytes: still read.
        XCTAssertEqual(try Packet.decode(bytes + [9]), p)
        // Its own type, not All Notes Off's (0x20).
        XCTAssertNotEqual(p.body.typeCode, PacketBody.allNotesOff.typeCode)
        // Sealed, it fits a packet easily.
        let ch = SecureChannel(secret: PairingSecret(keyBytes: Array(repeating: 3, count: 32)))
        let sealed = try XCTUnwrap(ch.seal(p, peerNonce: Array(repeating: 1, count: 16)))
        XCTAssertLessThanOrEqual(sealed.count, WireProtocol.maxPacketSize)
    }
}

/// The main Mac tells the backup its iPhones (with each heartbeat and when it changes).
extension CueTests {
    func testBackupLearnsTheMainMacsIPhones() {
        let t = self
        t.connect(); t.tick(1.1)
        XCTAssertNil(t.backup.peerRemoteSummary)                 // not told yet
        t.main.setRemoteSummary(RemoteSummary(phones: 1, watch: .reachable)); t.pump()
        // At once, not only with the next heartbeat.
        XCTAssertEqual(t.backup.peerRemoteSummary, RemoteSummary(phones: 1, watch: .reachable))
        t.main.setRemoteSummary(RemoteSummary(phones: 2, watch: .notReachable)); t.pump()
        XCTAssertEqual(t.backup.peerRemoteSummary, RemoteSummary(phones: 2, watch: .notReachable))
        XCTAssertNil(t.main.peerRemoteSummary)                   // the backup told nothing
        // Link lost: forgotten.
        t.mainToBackupUp = false; t.backupToMainUp = false
        t.tick(8)
        XCTAssertNil(t.backup.peerRemoteSummary)
        // Back: the heartbeat tells it again (nothing changed on the main Mac meanwhile).
        t.mainToBackupUp = true; t.backupToMainUp = true
        t.tick(8)
        XCTAssertEqual(t.main.snapshot().link, .connected(peer: t.backupID.uuidString))
        XCTAssertEqual(t.backup.peerRemoteSummary, RemoteSummary(phones: 2, watch: .notReachable))
    }

    func testALostSummaryIsRepairedByTheNextHeartbeat() {
        let t = self
        t.connect(); t.tick(1.1)
        var dropped = 0
        t.dropMain = { x in
            guard x[3] == 0x21, dropped == 0 else { return false }
            dropped += 1
            return true
        }
        t.main.setRemoteSummary(RemoteSummary(phones: 1, watch: .absent)); t.pump()
        XCTAssertEqual(dropped, 1)
        XCTAssertNil(t.backup.peerRemoteSummary)
        t.tick(1.1)
        XCTAssertEqual(t.backup.peerRemoteSummary, RemoteSummary(phones: 1, watch: .absent))
    }

    func testAnOlderBackupThatNeverSeesTheSummaryStaysLinked() {
        let t = self
        // As an older backup: the packet type is dropped (an older Packet.decode throws unknownType).
        t.dropMain = { $0[3] == 0x21 }
        t.connect()
        t.main.setRemoteSummary(RemoteSummary(phones: 3, watch: .reachable))
        t.tick(5)
        XCTAssertEqual(t.main.snapshot().link, .connected(peer: t.backupID.uuidString))
        XCTAssertEqual(t.backup.snapshot().link, .connected(peer: t.mainID.uuidString))
        XCTAssertNil(t.backup.peerRemoteSummary)
    }
}
