import XCTest
@testable import TwinKeysCore

// 2.4: the console settings are shared between the two Macs (packet type 0x22).

final class DeskPacketTests: XCTestCase {
    let ch = SecureChannel(secret: PairingSecret(keyBytes: Array(repeating: 3, count: 32)))

    func sealedSize(_ body: PacketBody) throws -> Int {
        try XCTUnwrap(ch.seal(Packet(session: 1, seq: 1, body: body), peerNonce: Array(repeating: 1, count: 16))).count
    }

    func testPacketsRoundTripAndFit() throws {
        let summary = DeskWireSummary(revision: 0x0102_0304_0506_0708, hash: 0xDEAD_BEEF, flags: 0b1011, model: 6,
                                      fadeTenths: 20, rowCount: 64, status: DeskPeerStatus.reading.rawValue, host: "255.255.255.255")
        let row = DeskWireRow(kind: 1, senderChannel: 120, receiverChannel: 7, fixedLevel: -32768,
                              name: String(repeating: "あ", count: 20))           // 60 bytes: cut to 40
        for d: DeskPacket in [.summary(summary), .row(revision: 9, index: 63, row), .request(revision: 77)] {
            let p = Packet(session: 3, seq: 4, body: .desk(d))
            let back = try Packet.decode(p.encode())
            if case let .row(rev, idx, r) = d, case let .desk(.row(rev2, idx2, r2)) = back.body {
                XCTAssertEqual([rev, UInt64(idx)], [rev2, UInt64(idx2)])
                XCTAssertEqual(r2.name, String(repeating: "あ", count: 13))        // 39 bytes, never half a character
                XCTAssertEqual([r2.kind, r2.senderChannel, r2.receiverChannel], [r.kind, r.senderChannel, r.receiverChannel])
                XCTAssertEqual(r2.fixedLevel, r.fixedLevel)
            } else {
                XCTAssertEqual(back, p)
            }
            XCTAssertLessThanOrEqual(try sealedSize(.desk(d)), WireProtocol.maxPacketSize)
        }
        // The layout (summary): kind, revision, hash, flags, model, fade, rows, status, host.
        let bytes = Packet(session: 0, seq: 0, body: .desk(.summary(DeskWireSummary(revision: 1, hash: 2, flags: 1, model: 1, fadeTenths: 5,
                                                                                      rowCount: 4, status: 3, host: "10.0.0.2")))).encode()
        XCTAssertEqual(bytes[3], 0x22)
        XCTAssertEqual(Array(bytes[12...]), [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 1, 1, 5, 4, 3, 8] + Array("10.0.0.2".utf8))
        // Its own type, not All Notes Off (0x20) or the iPhone summary (0x21).
        XCTAssertEqual(PacketBody.desk(.request(revision: 1)).typeCode, 0x22)
    }

    func testBadPayloadsAreRefused() {
        func decode(_ payload: [UInt8]) -> Error? {
            do { _ = try Packet.decode([0x54, 0x4B, 2, 0x22, 0, 0, 0, 1, 0, 0, 0, 1] + payload); return nil } catch { return error }
        }
        let rev: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]
        XCTAssertNil(decode([2] + rev))
        XCTAssertEqual(decode([2, 0, 0]) as? DecodeError, .badPayload)                                   // cut short
        XCTAssertEqual(decode([9] + rev) as? DecodeError, .badPayload)                                   // unknown kind
        XCTAssertEqual(decode([0] + rev + [0, 0, 0, 0, 0, 1, 5, 65, 0, 16] + Array(repeating: 49, count: 16)) as? DecodeError, .badPayload)  // too many rows, host too long
        XCTAssertEqual(decode([0] + rev + [0, 0, 0, 0, 0, 1, 5, 2, 0, 9] + [49]) as? DecodeError, .badPayload)   // host cut short
        XCTAssertEqual(decode([1] + rev + [0, 2, 1, 1, 0, 0, 0]) as? DecodeError, .badPayload)            // kind 2 is no channel kind
        // A later version may add bytes after the fields: still read.
        XCTAssertNil(decode([2] + rev + [7, 7]))
    }

    func testPeerStatusFromTheLink() {
        XCTAssertEqual(DeskPeerStatus(nil), .off)
        XCTAssertEqual(DeskPeerStatus(.reading), .reading)
        XCTAssertEqual(DeskPeerStatus(.connecting), .notConnected)
        XCTAssertEqual(DeskPeerStatus(.notReachable), .notConnected)
        XCTAssertEqual(DeskPeerStatus(.fixedLevels(unconfirmed: false)), .fixedLevels)
        XCTAssertEqual(DeskPeerStatus(.fixedLevels(unconfirmed: true)), .notConnected)     // the RCP port refused
        XCTAssertTrue(DeskPeerStatus.stale.isConnected)
        XCTAssertTrue(DeskPeerStatus.cannotRead.isConnected)
        XCTAssertFalse(DeskPeerStatus.off.isConnected)
        XCTAssertFalse(DeskPeerStatus.notConnected.isConnected)
    }
}

final class DeskShareTests: XCTestCase {
    let a = macA, b = macB

    /// Settings made on Mac A: A's Ch 1 and 2 ⇄ B's Ch 9 and 10, ST IN 1 ⇄ ST IN 2.
    func configured(revision: UInt64 = 1_700_000_000_000) -> DeskSettings {
        var d = DeskSettings()
        d.enabled = true
        d.model = .ql5
        d.host = "192.168.0.128"
        d.fade = 1
        d.trigger = .automatic
        d.rows = [DeskRow(channels: [a: 1, b: 9], name: "Music L"), DeskRow(channels: [a: 2, b: 10], fixedLevel: -600, name: "Music R"),
                  DeskRow(kind: .stereoIn, channels: [a: 1, b: 2], name: "Amb")]
        d.revision = revision
        return d
    }

    /// Delivers packets from one share to the other until nothing more is sent.
    func exchange(_ from: inout DeskShare, _ fromID: String, _ to: inout DeskShare, _ toID: String,
                  _ packets: [DeskPacket], now: Double = 0, drop: (DeskPacket) -> Bool = { _ in false }) -> [DeskSettings] {
        var adopted: [DeskSettings] = []
        var queue = packets.map { ($0, true) }       // (packet, from -> to)
        var guardCount = 0
        while !queue.isEmpty, guardCount < 1000 {
            guardCount += 1
            let (p, forward) = queue.removeFirst()
            if drop(p) { continue }
            if forward {
                let (adopt, replies) = to.received(p, me: toID, peer: fromID, myName: toID, peerName: fromID, now: now)
                if let adopt { adopted.append(adopt) }
                queue += replies.map { ($0, false) }
            } else {
                let (adopt, replies) = from.received(p, me: fromID, peer: toID, myName: fromID, peerName: toID, now: now)
                if let adopt { adopted.append(adopt) }
                queue += replies.map { ($0, true) }
            }
        }
        return adopted
    }

    func testTheOtherMacTakesOverNewerSettingsMirrored() throws {
        var sa = DeskShare(), sb = DeskShare()
        XCTAssertTrue(sa.setLocal(configured()))
        var mine = DeskSettings()
        mine.moveDeskWhenConfirming = false          // B's own answer is kept
        _ = sb.setLocal(mine)
        let adopted = exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)] + sa.rows(me: a, peer: b))
        let got = try XCTUnwrap(adopted.first)
        XCTAssertEqual(adopted.count, 1)
        XCTAssertTrue(got.sameShared(as: configured()))
        XCTAssertEqual(got.revision, configured().revision)
        XCTAssertFalse(got.moveDeskWhenConfirming)
        XCTAssertEqual(got.macNames, [a: a, b: b])
        // On B the two channels swap places: B's Ch 9 is its own.
        XCTAssertEqual(got.routes(me: b, other: a).first, DeskRoute(other: 1, own: 9, name: "Music L"))
        XCTAssertEqual(got.routes(me: b, other: a)[1].fixedLevel, -600)
        // Nothing goes back and forth afterwards.
        XCTAssertEqual(exchange(&sb, b, &sa, a, [sb.summary(me: b, peer: a)]).count, 0)
        XCTAssertEqual(exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)]).count, 0)
        XCTAssertFalse(sb.setLocal(got))             // the app stores what was taken over: nothing to send
    }

    func testOlderOrNeverSetSettingsAreNotTakenOver() {
        var sa = DeskShare(), sb = DeskShare()
        _ = sa.setLocal(configured(revision: 100))
        _ = sb.setLocal(configured(revision: 200))
        XCTAssertEqual(exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)] + sa.rows(me: a, peer: b)).count, 0)
        // Defaults (revision 0) never replace anything, even with a "newer" ID.
        var fresh = DeskShare()
        _ = sa.setLocal(configured(revision: 0))
        XCTAssertEqual(exchange(&fresh, "ZZZ", &sa, a, [fresh.summary(me: "ZZZ", peer: a)]).count, 0)
    }

    func testSameRevisionWithOtherContentGoesToTheHigherID() {
        var sa = DeskShare(), sb = DeskShare()
        var other = configured(revision: 5)
        other.fade = 2
        _ = sa.setLocal(configured(revision: 5))
        _ = sb.setLocal(other)
        // B's ID is higher: A takes B's, B never takes A's.
        XCTAssertEqual(exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)] + sa.rows(me: a, peer: b)).count, 0)
        let got = exchange(&sb, b, &sa, a, [sb.summary(me: b, peer: a)] + sb.rows(me: b, peer: a))
        XCTAssertEqual(got.first?.fade, 2)
    }

    func testALostRowIsAskedForAgain() {
        var sa = DeskShare(), sb = DeskShare()
        _ = sa.setLocal(configured())
        var dropped = 0
        let first = exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)] + sa.rows(me: a, peer: b), now: 0) { p in
            if case .row(_, 1, _) = p, dropped == 0 { dropped += 1; return true }
            return false
        }
        XCTAssertEqual(first.count, 0)
        // The next summary (heartbeat): B asks, A sends again, B takes it over.
        let second = exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)], now: 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(sb.local.rows.count, 3)
        // Asked at most once a second.
        var sc = DeskShare()
        _ = exchange(&sa, a, &sc, "C", [sa.summary(me: a, peer: "C")], now: 0)
        let r1 = sc.received(sa.summary(me: a, peer: "C"), me: "C", peer: a, myName: "C", peerName: a, now: 0.5).send
        let r2 = sc.received(sa.summary(me: a, peer: "C"), me: "C", peer: a, myName: "C", peerName: a, now: 0.6).send
        let r3 = sc.received(sa.summary(me: a, peer: "C"), me: "C", peer: a, myName: "C", peerName: a, now: 1.6).send
        XCTAssertEqual(r1.count + r2.count + r3.count, 2)
    }

    func testRowsBeforeTheirSummaryAndAnswersToRequests() {
        var sa = DeskShare(), sb = DeskShare()
        _ = sa.setLocal(configured())
        // Rows overtaking their summary on the network are kept.
        let got = exchange(&sa, a, &sb, b, sa.rows(me: a, peer: b) + [sa.summary(me: a, peer: b)])
        XCTAssertEqual(got.count, 1)
        // A request for another revision is answered with the summary only.
        let (_, replies) = sa.received(.request(revision: 3), me: a, peer: b, myName: a, peerName: b, now: 0)
        XCTAssertEqual(replies.count, 1)
        if case .summary = replies[0] {} else { XCTFail() }
        let (_, all) = sa.received(.request(revision: configured().revision), me: a, peer: b, myName: a, peerName: b, now: 0)
        XCTAssertEqual(all.count, 4)
    }

    func testABadHashIsNotTakenOver() {
        var sa = DeskShare(), sb = DeskShare()
        _ = sa.setLocal(configured())
        guard case var .summary(s) = sa.summary(me: a, peer: b) else { return XCTFail() }
        s.hash ^= 1
        XCTAssertEqual(exchange(&sa, a, &sb, b, [.summary(s)] + sa.rows(me: a, peer: b)).count, 0)
        XCTAssertEqual(sb.local, DeskSettings())
    }

    func testStatusAndPlaceholders() {
        var sa = DeskShare(), sb = DeskShare()
        XCTAssertTrue(sa.setStatus(.reading))
        XCTAssertFalse(sa.setStatus(.reading))
        // Settings made before the other Mac was known: the placeholder is sent as the other Mac.
        var d = configured()
        d.rows = [DeskRow(channels: [a: 1, DeskSettings.otherMacKey: 9])]
        _ = sa.setLocal(d)
        let got = exchange(&sa, a, &sb, b, [sa.summary(me: a, peer: b)] + sa.rows(me: a, peer: b))
        XCTAssertEqual(sb.peerStatus, .reading)
        XCTAssertEqual(got.first?.rows.first?.channels, [a: 1, b: 9])
        sb.linkChanged()
        XCTAssertNil(sb.peerStatus)
    }
}

/// Two Macs (Conductors) share the console settings over their link.
extension CueTests {
    func deskSettings(_ me: UUID, _ other: UUID, revision: UInt64) -> DeskSettings {
        var d = DeskSettings()
        d.enabled = true
        d.host = "192.168.0.128"
        d.rows = [DeskRow(channels: [me.uuidString: 1, other.uuidString: 9]), DeskRow(kind: .stereoIn, channels: [me.uuidString: 1, other.uuidString: 2])]
        d.revision = revision
        return d
    }

    func testTheMacsShareTheConsoleSettings() {
        let t = self
        var atBackup: [DeskSettings] = [], atMain: [DeskSettings] = []
        t.backup.onDeskSettings = { atBackup.append($0) }
        t.main.onDeskSettings = { atMain.append($0) }
        t.connect(); t.tick(1.1)
        // Changed on the main Mac while linked: on the backup at once, mirrored.
        t.main.setDeskSettings(deskSettings(t.mainID, t.backupID, revision: 1000)); t.pump()
        XCTAssertEqual(atBackup.count, 1)
        XCTAssertEqual(atBackup.last?.routes(me: t.backupID.uuidString, other: t.mainID.uuidString).first, DeskRoute(other: 1, own: 9))
        XCTAssertTrue(atMain.isEmpty)
        // Changed on the backup: back on the main Mac.
        var edited = atBackup.last!
        edited.fade = 2
        edited.markChanged(nowMillis: 2000)
        t.backup.setDeskSettings(edited); t.pump()
        XCTAssertEqual(atMain.last?.fade, 2)
        XCTAssertEqual(atMain.last?.rows.first?.channels, [t.mainID.uuidString: 1, t.backupID.uuidString: 9])
        // Settled: heartbeats carry only the summary and nothing is taken over again.
        t.main.setDeskSettings(atMain.last!); t.backup.setDeskSettings(edited)
        t.tick(3)
        XCTAssertEqual(atMain.count, 1)
        XCTAssertEqual(atBackup.count, 1)
    }

    func testSettingsChangedWhileApartArriveWhenLinked() {
        let t = self
        var atBackup: [DeskSettings] = []
        t.backup.onDeskSettings = { atBackup.append($0) }
        t.main.setDeskSettings(deskSettings(t.mainID, t.backupID, revision: 1000))
        t.connect(); t.tick(0.2)
        XCTAssertEqual(atBackup.count, 1)            // sent when the link came up
    }

    func testEachMacTellsItsConsoleLink() {
        let t = self
        t.connect(); t.tick(1.1)
        XCTAssertEqual(t.backup.peerDeskStatus, .off)      // a new version that has no console link running
        t.main.setDeskStatus(.reading); t.pump()
        XCTAssertEqual(t.backup.peerDeskStatus, .reading)
        t.backup.setDeskStatus(.fixedLevels); t.pump()
        XCTAssertEqual(t.main.peerDeskStatus, .fixedLevels)
        t.mainToBackupUp = false; t.backupToMainUp = false
        t.tick(8)
        XCTAssertNil(t.backup.peerDeskStatus)
    }

    func testAnOlderMacThatDropsTheConsolePacketStaysLinked() {
        let t = self
        var atBackup: [DeskSettings] = []
        t.backup.onDeskSettings = { atBackup.append($0) }
        t.dropMain = { $0[3] == 0x22 }               // as an older backup: unknown type, dropped
        t.connect()
        t.main.setDeskSettings(deskSettings(t.mainID, t.backupID, revision: 1000))
        t.tick(5)
        XCTAssertEqual(t.main.snapshot().link, .connected(peer: t.backupID.uuidString))
        XCTAssertEqual(t.backup.snapshot().link, .connected(peer: t.mainID.uuidString))
        XCTAssertTrue(atBackup.isEmpty)
        XCTAssertNil(t.backup.peerDeskStatus)
    }

    func testLostConsoleRowsAreRepaired() {
        let t = self
        var atBackup: [DeskSettings] = []
        t.backup.onDeskSettings = { atBackup.append($0) }
        t.connect(); t.tick(1.1)
        var dropped = 0
        t.dropMain = { x in
            // The first row: a sealed row without a name is 44 bytes (a summary is longer, a request shorter).
            guard x[3] == 0x22, dropped < 1, x.count == 44 else { return false }
            dropped += 1
            return true
        }
        t.main.setDeskSettings(deskSettings(t.mainID, t.backupID, revision: 1000)); t.pump()
        XCTAssertEqual(dropped, 1)
        XCTAssertTrue(atBackup.isEmpty)
        t.tick(2.5)                                  // next summaries: asked for, sent again
        XCTAssertEqual(atBackup.count, 1)
    }
}
