import XCTest
@testable import TwinKeysCore

final class SetCheckTests: XCTestCase {
    func testSameSetsHaveNoDiff() {
        let a = SetSummary(tracks: ["Music", "SE"], scenes: ["1 Intro", "2 Main"])
        var p = PeerSet()
        p.summary(tracks: 2, scenes: 2, hash: a.hash)
        XCTAssertNil(SetDiff.compare(mine: a, peer: p))
        XCTAssertNil(SetDiff.compare(mine: a, peer: nil))
    }

    func testDifferentNamesAndCountsAreListed() throws {
        let main = SetSummary(tracks: ["Music", "SE", "FX"], scenes: ["1 Intro", "2 Main"])
        let backup = SetSummary(tracks: ["Music", "SE"], scenes: ["1 Intro", "2 Main v2"])
        var p = PeerSet()
        p.summary(tracks: 2, scenes: 2, hash: backup.hash)
        for (i, n) in backup.tracks.enumerated() { p.item(kind: .track, index: i, name: n) }
        for (i, n) in backup.scenes.enumerated() { p.item(kind: .scene, index: i, name: n) }
        let d = try XCTUnwrap(SetDiff.compare(mine: main, peer: p))
        XCTAssertTrue(d.complete)
        XCTAssertEqual(d.differences, 2)
        XCTAssertEqual(d.mainTracks, 3); XCTAssertEqual(d.backupTracks, 2)
        XCTAssertEqual(d.rows, [.init(kind: "track", index: 2, main: "FX", backup: nil),
                                .init(kind: "scene", index: 1, main: "2 Main", backup: "2 Main v2")])
    }

    func testNamesStillArrivingAreNotCountedAsDifferent() throws {
        let main = SetSummary(tracks: ["A", "B"], scenes: ["S"])
        var p = PeerSet()
        p.summary(tracks: 2, scenes: 1, hash: 12345)       // differs, names not here yet
        let d = try XCTUnwrap(SetDiff.compare(mine: main, peer: p))
        XCTAssertFalse(d.complete)
        XCTAssertEqual(d.differences, 0)
    }

    func testLongNamesAreCutTheSameWayOnBothSides() {
        let long = String(repeating: "あ", count: 40)        // 120 bytes
        let a = SetSummary(tracks: [long], scenes: [])
        XCTAssertLessThanOrEqual(a.tracks[0].utf8.count, SetSummary.maxNameBytes)
        XCTAssertEqual(a.hash, SetSummary(tracks: [long + "x"], scenes: []).hash)
    }

    func testPacketsRoundTrip() throws {
        for body in [PacketBody.setSummary(tracks: 300, scenes: 7, hash: 0xDEADBEEF),
                     .setItem(kind: 1, index: 513, name: "M2 本編")] {
            let p = Packet(session: 1, seq: 2, body: body)
            XCTAssertEqual(try Packet.decode(p.encode()), p)
        }
    }
}

/// The two Macs tell each other their sets over the link.
extension CueTests {
    func testMacsCompareTheirSets() throws {
        let t = self
        t.main.setLocalSet(SetSummary(tracks: (0..<12).map { "T\($0)" }, scenes: (0..<10).map { "S\($0)" }))
        t.backup.setLocalSet(SetSummary(tracks: (0..<11).map { "T\($0)" }, scenes: (0..<10).map { $0 == 6 ? "S6 v2" : "S\($0)" }))
        t.connect()
        t.tick(6)            // enough heartbeats for 21 names at 8 per heartbeat
        let d = try XCTUnwrap(t.main.setDiff)
        XCTAssertTrue(d.complete)
        XCTAssertEqual(d.differences, 2)       // track 11 missing on the backup, scene 6 renamed
        XCTAssertEqual(d.backupTracks, 11)
        // The backup sees the same difference from its side.
        XCTAssertEqual(try XCTUnwrap(t.backup.setDiff).differences, 2)
        // Same set on both: the warning goes away.
        t.backup.setLocalSet(SetSummary(tracks: (0..<12).map { "T\($0)" }, scenes: (0..<10).map { "S\($0)" }))
        t.tick(2)
        XCTAssertNil(t.main.setDiff)
    }
}

/// 2.2: the backup tells what its Live did with a forwarded command.
extension CueTests {
    func testBackupReportsWhatItsLiveDid() throws {
        let t = self
        var answers: [(LiveCommand, (Conductor.LiveRun) -> Void)] = []
        t.backup.onLiveCommandRun = { cmd, answer in answers.append((cmd, answer)) }
        t.connect(); t.tick(1.1)
        let a = try XCTUnwrap(t.main.forwardLive(.fireScene(1)))
        let b = try XCTUnwrap(t.main.forwardLive(.fireScene(2)))
        t.pump(); t.tick(0.05)
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(t.main.liveDelivery(a), "delivered")
        answers[0].1(.ran); answers[1].1(.noAnswer)
        // The answers are sent from another queue: wait for them, then deliver.
        let deadline = Date().addingTimeInterval(2)
        while (t.main.liveDelivery(a) != "ran" || t.main.liveDelivery(b) != "noLive") && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02); t.pump()
        }
        XCTAssertEqual(t.main.liveDelivery(a), "ran")
        XCTAssertEqual(t.main.liveDelivery(b), "noLive")
    }

    func testLiveResultPacketRoundTrip() throws {
        let p = Packet(session: 3, seq: 4, body: .liveResult(id: 77, code: 2))
        XCTAssertEqual(try Packet.decode(p.encode()), p)
    }
}

final class LockScopeTests: XCTestCase {
    func testStandardScopeKeepsTheOldRule() {
        for c: LiveCommand in [.fireScene(1), .fireClip(track: 0, scene: 1), .stopTrack(0), .stopAll, .play, .stop, .continuePlaying, .selectScene(2)] {
            XCTAssertTrue(c.allowedWhileLocked, "\(c)")
            XCTAssertFalse(LockScope.standard.blocks(c), "\(c)")
        }
        for c: LiveCommand in [.setTempo(120), .setVolume(track: 0, value: 0.5), .setPan(track: 0, value: 0), .setSend(track: 0, send: 0, value: 0.2), .setMute(track: 0, on: true), .setSolo(track: 0, on: true)] {
            XCTAssertFalse(c.allowedWhileLocked, "\(c)")
            XCTAssertTrue(LockScope.standard.blocks(c), "\(c)")
        }
    }

    func testEverythingLockedStillAllowsSceneSelection() {
        let all: LockScope = [.tempo, .mixer, .launches, .stops, .cues]
        XCTAssertTrue(all.blocks(.fireClip(track: 0, scene: 0)))
        XCTAssertTrue(all.blocks(.stop))
        XCTAssertFalse(all.blocks(.selectScene(3)))
    }

    func testNewMessagesRoundTrip() throws {
        for m: RemoteMessage in [.go(id: 4, scene: 7, structure: 12), .lockScope(on: true, scope: LockScope([.tempo, .cues]).rawValue)] {
            let d = try JSONEncoder().encode(m)
            XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: d), m)
        }
    }
}

/// 2.3: switching the main role to the backup and back.
extension CueTests {
    func testBackupBecomesMainAndTheOldMainOnlyReceivesWhenItComesBack() {
        let t = self
        var mainRoles: [Bool] = [], backupRoles: [Bool] = []
        t.main.onRoleChange = { mainRoles.append($0) }
        t.backup.onRoleChange = { backupRoles.append($0) }
        t.main.wallClock = { 1_000 }; t.backup.wallClock = { 1_000 }
        t.connect(); t.tick(1.1)
        // The main Mac dies (no packets either way).
        t.mainToBackupUp = false; t.backupToMainUp = false
        t.tick(8)
        t.backup.wallClock = { 2_000 }
        t.backup.claimMain()
        XCTAssertTrue(t.backup.snapshot().sendKeys)
        XCTAssertFalse(t.backup.snapshot().receiveNotes)
        XCTAssertEqual(backupRoles, [true])
        // Keys pressed on the backup now play there.
        t.backupMIDI.sent.removeAll()
        _ = t.backup.handleKey(KeyInput(keycode: t.down, isDown: true))
        XCTAssertFalse(t.backupMIDI.sent.isEmpty)
        _ = t.backup.handleKey(KeyInput(keycode: t.down, isDown: false))
        // The old main comes back: it stops sending keys by itself.
        t.mainToBackupUp = true; t.backupToMainUp = true
        t.main.connect(to: t.backupID.uuidString)
        t.tick(4)
        XCTAssertFalse(t.main.snapshot().sendKeys)
        XCTAssertTrue(t.main.snapshot().receiveNotes)
        XCTAssertEqual(mainRoles, [false])
        XCTAssertTrue(t.backup.claimsMain)
        // Return to main: the backup only receives again, the old main sends again.
        t.backup.handOverMain(); t.pump(); t.tick(1)
        XCTAssertFalse(t.backup.snapshot().sendKeys)
        XCTAssertTrue(t.main.snapshot().sendKeys)
        XCTAssertTrue(t.main.claimsMain)
    }

    func testRolePacketsRoundTrip() throws {
        for body in [PacketBody.roleClaim(millis: 1_731_400_000_123), .roleHandover] {
            let p = Packet(session: 1, seq: 9, body: body)
            XCTAssertEqual(try Packet.decode(p.encode()), p)
        }
    }
}
