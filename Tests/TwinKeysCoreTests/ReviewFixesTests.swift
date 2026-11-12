import XCTest
@testable import TwinKeysCore

// Fixes from the review of 2.2.0 (PR #8).

/// 1. An iPhone on 1.2 must not send a Mac on 2.1 what it cannot read (the Mac closes the
/// connection, the iPhone reconnects, and so on).
final class RemoteCompatTests: XCTestCase {
    let secret = PairingSecret(keyBytes: Array(repeating: 5, count: 32))

    /// The welcome as TwinKeys Remote 1.0–1.2 declares it (one name).
    private enum OldWelcome: Codable, Equatable { case welcome(macName: String) }

    func testWelcomeListsWhatTheMacUnderstandsAndStaysReadableForOlderIPhones() throws {
        let new = try JSONEncoder().encode(RemoteMessage.welcome(macName: "Main Stage Mac", features: RemoteFeature.all))
        XCTAssertEqual(try JSONDecoder().decode(OldWelcome.self, from: new), .welcome(macName: "Main Stage Mac"))
        // From a 2.2.0 Mac: no list.
        let old = try JSONEncoder().encode(OldWelcome.welcome(macName: "Main Stage Mac"))
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: old), .welcome(macName: "Main Stage Mac", features: nil))
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: new), .welcome(macName: "Main Stage Mac", features: RemoteFeature.all))
    }

    func testMessagesAreTranslatedForAnOlderMac() {
        let cmd = LiveCommand.fireClip(track: 1, scene: 2)
        let legacy = RemoteMacCompat(advertised: nil, legacy: true)
        XCTAssertEqual(legacy.translate(.commandAt(id: 3, cmd, structure: 9), sceneCount: 8), [.command(id: 3, cmd)])
        XCTAssertEqual(legacy.translate(.go(id: 4, scene: 2, structure: 9), sceneCount: 8),
                       [.command(id: 4, .fireScene(2)), .command(id: 4, .selectScene(3))])
        XCTAssertEqual(legacy.translate(.go(id: 4, scene: 7, structure: nil), sceneCount: 8), [.command(id: 4, .fireScene(7))])   // the last scene
        XCTAssertEqual(legacy.translate(.lockScope(on: true, scope: LockScope.standard.union(.launches).rawValue), sceneCount: 8), [.lock(true)])
        XCTAssertEqual(legacy.translate(.becomeMain(id: 5), sceneCount: 8), [])
        for m: RemoteMessage in [.cue(id: 1, keycode: 125), .allNotesOff(id: 2), .ping(1), .lock(false), .command(id: 6, .play)] {
            XCTAssertEqual(legacy.translate(m, sceneCount: 8), [m])
        }
        // A Mac that said nothing is assumed to be 2.2.0 (probed), and is sent everything.
        let unknown = RemoteMacCompat(advertised: nil, legacy: false)
        XCTAssertTrue(unknown.needsProbe)
        XCTAssertEqual(unknown.translate(.go(id: 4, scene: 2, structure: 9), sceneCount: 8), [.go(id: 4, scene: 2, structure: 9)])
        // A Mac that lists its features gets exactly those.
        let some = RemoteMacCompat(advertised: [RemoteFeature.commandAt], legacy: false)
        XCTAssertFalse(some.needsProbe)
        XCTAssertEqual(some.translate(.commandAt(id: 1, cmd, structure: nil), sceneCount: 8), [.commandAt(id: 1, cmd, structure: nil)])
        XCTAssertEqual(some.translate(.lockScope(on: false, scope: 3), sceneCount: 8), [.lock(false)])
        XCTAssertTrue(RemoteMacCompat(advertised: RemoteFeature.all, legacy: false).understands(RemoteFeature.becomeMain))
    }

    func testAnAuthenticMessageOfAnUnknownKindIsSkippedNotFatal() throws {
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = try server.receive(client.clientHello(deviceID: "d", deviceName: "n"))
        _ = try client.receive(server.serverHello(serverID: "m", serverName: "m"))
        let future = try client.seal(json: Data(#"{"somethingNew":{"x":1}}"#.utf8))
        XCTAssertEqual(try server.receive(future), [])                       // skipped, connection kept
        XCTAssertEqual(try server.receive(client.seal(.ping(3))), [.message(.ping(3, watch: nil))])
        // A frame that does not open still closes it.
        var bad = try client.seal(.ping(4))
        bad[bad.count - 1] ^= 1
        XCTAssertThrowsError(try server.receive(bad))
    }
}

/// 5. The backup's name as the main Mac knows it (cut to 32 bytes) and as Bonjour shows it.
final class RemoteNamesTests: XCTestCase {
    func testNamesCutOrRenamedByBonjourStillMatch() {
        let long = "舞台袖のバックアップ用マック二号機"                        // 51 bytes
        let cut = String(decoding: Array(truncatedUTF8(long, max: maxNameBytes)), as: UTF8.self)
        XCTAssertNotEqual(cut, long)
        XCTAssertTrue(RemoteNames.matches(bonjour: long, linkName: cut))
        XCTAssertTrue(RemoteNames.matches(bonjour: long + " (2)", linkName: cut))
        XCTAssertTrue(RemoteNames.matches(bonjour: "Backup Stage Mac", linkName: "Backup Stage Mac"))
        XCTAssertTrue(RemoteNames.matches(bonjour: "Backup Stage Mac (2)", linkName: "Backup Stage Mac"))
        XCTAssertFalse(RemoteNames.matches(bonjour: "Backup Stage Mac (two)", linkName: "Backup Stage Mac"))
        XCTAssertFalse(RemoteNames.matches(bonjour: "Main Stage Mac", linkName: "Backup Stage Mac"))
        XCTAssertFalse(RemoteNames.matches(bonjour: "Backup", linkName: ""))
        // A cut that ends in a space (the Mac trims it after cutting).
        let spaced = "Backup Stage Mac For The Big Hall Two"                  // cut after "...Hall "
        let spacedCut = String(decoding: Array(truncatedUTF8(spaced, max: maxNameBytes)), as: UTF8.self).trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(RemoteNames.matches(bonjour: spaced, linkName: spacedCut))
    }

    func testTheExactNameWinsAndTheCurrentMacIsNeverTheBackup() {
        // Both Macs are called "Stage Mac"; Bonjour shows the second as "Stage Mac (2)".
        let names = ["Stage Mac", "Stage Mac (2)"]
        XCTAssertEqual(RemoteNames.find("Stage Mac", in: names), "Stage Mac")
        XCTAssertEqual(RemoteNames.find("Stage Mac", in: names, excluding: "Stage Mac"), "Stage Mac (2)")
        XCTAssertNil(RemoteNames.find("Other", in: names))
    }
}

/// 8. The main-lost banner only for an unexpected loss.
final class MainLossWatchTests: XCTestCase {
    func testOnlyATimedOutLinkIsALoss() {
        var w = MainLossWatch()
        w.update(.connected(peer: "m"), now: 0)
        w.update(.connecting(peer: "m", attempt: 1, nextRetryAt: 2), now: 1)
        XCTAssertFalse(w.isLost(now: 3.9))
        XCTAssertTrue(w.isLost(now: 4))
        w.update(.connected(peer: "m"), now: 5)
        XCTAssertFalse(w.isLost(now: 10))
        // Disconnect here, or the other Mac said goodbye: idle, not lost.
        w.update(.idle, now: 11)
        XCTAssertFalse(w.isLost(now: 20))
        // Connecting to a Mac from idle is not a loss either.
        w.update(.connecting(peer: "x", attempt: 1, nextRetryAt: 22), now: 21)
        XCTAssertFalse(w.isLost(now: 30))
    }
}

extension CueTests {
    /// 8. The main Mac quits (goodbye): the backup's link ends without a loss.
    func testAGoodbyeIsNotALoss() {
        let t = self
        t.connect(); t.tick(1.1)
        var w = MainLossWatch()
        w.update(t.backup.snapshot().link, now: t.now)
        t.main.prepareForQuit(); t.pump()
        w.update(t.backup.snapshot().link, now: t.now)
        XCTAssertEqual(t.backup.snapshot().link, .idle)
        XCTAssertFalse(w.isLost(now: t.now + 10))
    }

    /// 3. A repeated liveAck after liveResult must not hide what the backup's Live did.
    func testARepeatedAckDoesNotOverwriteTheLiveResult() throws {
        let t = self
        t.backup.onLiveCommandRun = { _, answer in answer(.ran) }
        t.connect(); t.tick(1.1)
        var heldAcks: [[UInt8]] = []
        t.dropFromBackupFn = { x in
            guard x[3] == 0x19 else { return false }       // liveAck: hold it back
            heldAcks.append(x)
            return true
        }
        let id = try XCTUnwrap(t.main.forwardLive(.play)); t.pump()
        // The backup answers liveResult on another queue.
        let deadline = Date().addingTimeInterval(2)
        while t.main.liveDelivery(id) != "ran", Date() < deadline { Thread.sleep(forTimeInterval: 0.01); t.pump() }
        XCTAssertEqual(t.main.liveDelivery(id), "ran")
        XCTAssertFalse(heldAcks.isEmpty)
        for a in heldAcks { t.main.receive(a, knownPeer: t.backupID.uuidString) }     // late ack
        XCTAssertEqual(t.main.liveDelivery(id), "ran")
        XCTAssertTrue(Conductor.isSettledLiveDelivery("ran"))
        XCTAssertFalse(Conductor.isSettledLiveDelivery("delivered"))      // a liveResult is still to come
        XCTAssertFalse(Conductor.isSettledLiveDelivery("waiting"))
        XCTAssertTrue(Conductor.isSettledLiveDelivery("unknown"))
    }

    /// 4. Return to Main only while linked (otherwise both Macs would only receive).
    func testReturnToMainIsRefusedWhileNotLinked() {
        let t = self
        t.backup.claimMain()
        XCTAssertFalse(t.backup.handOverMain())
        XCTAssertTrue(t.backup.snapshot().sendKeys)
        XCTAssertTrue(t.backup.claimsMain)
        t.connect(); t.tick(1.1)
        XCTAssertTrue(t.backup.handOverMain()); t.pump()
        XCTAssertFalse(t.backup.snapshot().sendKeys)
    }

    /// 10. A later claim wins even when the clock of the Mac making it is behind.
    func testALaterClaimWinsDespiteClockSkew() {
        let t = self
        t.main.wallClock = { 2_000_000_000 }        // an hour ahead (and then some)
        t.backup.wallClock = { 1_000_000 }
        t.connect(); t.tick(1.1)
        t.main.claimMain(); t.tick(1.1)
        XCTAssertTrue(t.main.claimsMain)
        // Later, the operator makes the backup the main on purpose.
        t.backup.claimMain(); t.tick(1.1)
        XCTAssertTrue(t.backup.claimsMain)
        XCTAssertTrue(t.backup.snapshot().sendKeys)
        XCTAssertFalse(t.main.claimsMain)
        XCTAssertFalse(t.main.snapshot().sendKeys)
        // And back again.
        t.main.claimMain(); t.tick(1.1)
        XCTAssertTrue(t.main.claimsMain)
        XCTAssertFalse(t.backup.claimsMain)
    }
}
