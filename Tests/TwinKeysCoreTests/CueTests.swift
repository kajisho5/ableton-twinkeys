import XCTest
@testable import TwinKeysCore

/// Cue keys and the delivery check, with two simulated Macs.
final class CueTests: XCTestCase {
    typealias FakeMIDI = ConductorTests.FakeMIDI
    typealias FakeNet = ConductorTests.FakeNet

    var now = 0.0
    let mainID = UUID(), backupID = UUID()
    var mainMIDI = FakeMIDI(), backupMIDI = FakeMIDI()
    var mainNet = FakeNet(), backupNet = FakeNet()
    var main: Conductor!, backup: Conductor!
    /// Drop packets in this direction while false.
    var mainToBackupUp = true, backupToMainUp = true
    /// Packet types the backup's packets are dropped for (to act like an older version).
    var dropFromBackup: Set<UInt8> = []
    var dropFromBackupFn: ([UInt8]) -> Bool = { _ in false }
    /// Drop single main -> backup packets chosen by this test (returns true to drop).
    var dropMain: ([UInt8]) -> Bool = { _ in false }
    let secret = PairingSecret(keyBytes: Array(repeating: 7, count: 32))
    let down = KeyNames.down

    func make(_ id: UUID, _ name: String, _ s: AppSettings, _ midi: FakeMIDI, _ net: FakeNet, session: UInt32) -> Conductor {
        let c = Conductor(instanceID: id, displayName: name, settings: s, midi: midi, net: net,
                          session: session, clock: { [unowned self] in now }, nanos: { [unowned self] in UInt64(now * 1e9) })
        c.setPairing(secret)
        return c
    }

    override func setUp() {
        var s = AppSettings(); s.receiveNotes = false
        main = make(mainID, "Main", s, mainMIDI, mainNet, session: 1)
        var b = AppSettings(); b.sendKeys = false
        backup = make(backupID, "Backup", b, backupMIDI, backupNet, session: 2)
    }

    func pump() {
        for _ in 0..<10 {
            let a = mainNet.outbox; mainNet.outbox.removeAll()
            let b = backupNet.outbox; backupNet.outbox.removeAll()
            if a.isEmpty && b.isEmpty { return }
            if mainToBackupUp { for (_, x) in a where !dropMain(x) { backup.receive(x, knownPeer: mainID.uuidString) } }
            if backupToMainUp { for (_, x) in b where !dropFromBackup.contains(x[3]) && !dropFromBackupFn(x) { main.receive(x, knownPeer: backupID.uuidString) } }
        }
    }

    func connect() {
        main.connect(to: backupID.uuidString); pump()
        XCTAssertEqual(main.snapshot().link, .connected(peer: backupID.uuidString))
    }

    func tick(_ seconds: Double) {
        let end = now + seconds
        while now < end - 1e-9 { now += 0.05; main.tick(); backup.tick(); pump() }
    }

    func cueOnsAtBackup(_ note: UInt8) -> Int { backupMIDI.sent.filter { $0 == [0x90, note, 127] }.count }

    func testOnlyCueKeysAreSentAtFullVelocity() {
        main.handleKey(KeyInput(keycode: 0x00, isDown: true))          // A is not a cue key by default
        XCTAssertTrue(mainMIDI.sent.isEmpty)
        main.handleKey(KeyInput(keycode: down, isDown: true))
        main.handleKey(KeyInput(keycode: down, isDown: true, isRepeat: true))
        main.handleKey(KeyInput(keycode: down, isDown: false))
        XCTAssertEqual(mainMIDI.sent, [[0x90, 37, 127], [0x80, 37, 0]])
    }

    func testAddingLettersAndDigitsKeepsExistingNotes() {
        let keys = CueKey.adding(CueKey.alphanumericKeyCodes, to: CueKey.defaults)
        XCTAssertEqual(keys.count, 7 + 36)
        XCTAssertEqual(Array(keys.prefix(7)), CueKey.defaults)
        XCTAssertEqual(Set(keys.map(\.note)).count, keys.count)
        XCTAssertEqual(keys.first { $0.keycode == 0x00 }?.label, "A")
        XCTAssertEqual(keys.first { $0.keycode == 0x1D }?.label, "0")
        XCTAssertEqual(CueKey.adding([0x00], to: keys), keys, "already there: nothing added")
        let mid = FakeMIDI()
        var s = AppSettings(); s.cueKeys = keys
        let c = make(UUID(), "X", s, mid, FakeNet(), session: 9)
        c.handleKey(KeyInput(keycode: 0x00, isDown: true))
        XCTAssertEqual(mid.sent, [[0x90, 43, 127]])
    }

    func testKeyRemovedWhileHeldStillEndsItsNote() {
        let mid = FakeMIDI()
        let c = make(UUID(), "X", AppSettings(), mid, FakeNet(), session: 9)
        c.handleKey(KeyInput(keycode: down, isDown: true))
        c.setCueKeys([])                        // ends held notes right away
        c.handleKey(KeyInput(keycode: down, isDown: false))
        XCTAssertEqual(mid.sent, [[0x90, 37, 127], [0x80, 37, 0]])
    }

    func testCueWithModifierIsNotSentAndNotSwallowed() {
        XCTAssertFalse(main.handleKey(KeyInput(keycode: down, isDown: true, modifiers: .shift)))
        XCTAssertTrue(mainMIDI.sent.isEmpty)
    }

    func testCueKeysAreSwallowedOnlyWhileCaptureIsOn() {
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: true)))
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: true, isRepeat: true)))
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: false)))
        XCTAssertFalse(main.handleKey(KeyInput(keycode: 0x00, isDown: true)))   // not a cue key
        main.setKeyCapture(false)
        XCTAssertFalse(main.handleKey(KeyInput(keycode: down, isDown: true)))
        main.setKeyCapture(true); main.setBlockCueKeys(false)
        XCTAssertFalse(main.handleKey(KeyInput(keycode: KeyNames.up, isDown: true)))
    }

    func testSwallowedKeyDownAlsoSwallowsItsKeyUpAfterCaptureTurnsOff() {
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: true)))
        main.setKeyCapture(false)
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: false)))
    }

    func testDeliveredCueShowsTheSameCountAndNameOnBothMacs() {
        main.setCueKeys([CueKey(keycode: down, memo: "Next scene", note: 37)])
        connect()
        for _ in 0..<3 {
            main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
            main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
        }
        let m = main.snapshot().lastCue!, b = backup.snapshot().lastCue!
        XCTAssertEqual(m.count, 3); XCTAssertEqual(b.count, 3)
        XCTAssertEqual(m.label, "↓"); XCTAssertEqual(b.label, "↓")
        XCTAssertEqual(b.memo, "Next scene")
        XCTAssertEqual(b.delivery, .received)
        if case .delivered = m.delivery {} else { XCTFail("expected delivered, got \(m.delivery)") }
        XCTAssertEqual(cueOnsAtBackup(37), 3)
    }

    func testLostCueIsResentOnceAndPlayedOnce() {
        connect(); tick(1.1)
        mainToBackupUp = false
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
        mainNet.outbox.removeAll()
        mainToBackupUp = true
        tick(0.25)
        XCTAssertEqual(cueOnsAtBackup(37), 1)
        XCTAssertEqual(backupMIDI.sent.filter { $0 == [0x80, 37, 0] }.count, 1, "key already up: ends right away")
        if case .delivered = main.snapshot().lastCue!.delivery {} else { XCTFail("\(main.snapshot().lastCue!.delivery)") }
        tick(1)
        XCTAssertEqual(cueOnsAtBackup(37), 1)
    }

    func testLostAnswerDoesNotPlayTheCueTwice() {
        connect(); tick(1.1)
        backupToMainUp = false
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        backupNet.outbox.removeAll()
        backupToMainUp = true
        tick(0.25)
        XCTAssertEqual(cueOnsAtBackup(37), 1)
        if case .delivered = main.snapshot().lastCue!.delivery {} else { XCTFail("\(main.snapshot().lastCue!.delivery)") }
    }

    func testNoAnswerWithinTimeoutIsMissing() {
        connect(); tick(1.1)
        mainToBackupUp = false
        main.handleKey(KeyInput(keycode: down, isDown: true))
        tick(0.4)
        XCTAssertEqual(main.snapshot().lastCue!.delivery, .missing)
        XCTAssertEqual(cueOnsAtBackup(37), 0)
    }

    func testOldPeerIsUnconfirmed() {
        // 0.5.0 never sends features, answers or cue names (it drops those packet types).
        dropFromBackup = [0x13, 0x14, 0x15]
        connect(); tick(1.1)
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        tick(0.4)
        XCTAssertEqual(main.snapshot().lastCue!.delivery, .unconfirmed)
        XCTAssertEqual(cueOnsAtBackup(37), 1, "no resend to an old peer")
    }

    func testCueWhileNotConnected() {
        main.handleKey(KeyInput(keycode: down, isDown: true))
        XCTAssertEqual(main.snapshot().lastCue!.delivery, .notConnected)
        XCTAssertEqual(mainMIDI.sent, [[0x90, 37, 127]], "the main Mac's own Live still gets the cue")
    }

    func testCountStartsAgainAfterReconnect() {
        connect()
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
        main.disconnect(); pump()
        connect()
        XCTAssertNil(main.snapshot().lastCue)
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        XCTAssertEqual(main.snapshot().lastCue!.count, 1)
        XCTAssertEqual(backup.snapshot().lastCue!.count, 1)
    }

    func testHeldCueKeyKeepsSoundingOnTheBackup() {
        connect()
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        tick(2.5)   // heartbeats carry the held list
        XCTAssertFalse(backupMIDI.sent.contains([0x80, 37, 0]))
    }

    func testFreeNoteAndSanitize() {
        XCTAssertEqual(CueKey.freeNote(in: CueKey.defaults), 43)
        let keys = CueKey.sanitized([CueKey(keycode: down, note: 37), CueKey(keycode: down, note: 50),
                                     CueKey(keycode: KeyNames.up, note: 37), CueKey(keycode: 0x37, note: 60)])
        XCTAssertEqual(keys.map(\.note), [37])
    }

    func testSettingsFromOlderVersionKeepPianoLayout() throws {
        let old = #"{"version":1,"send_keys":true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(s.cueKeys, CueKey.defaults)
        XCTAssertTrue(s.blockCueKeys)
        XCTAssertTrue(s.autoUpdate)
        XCTAssertFalse(s.menuBarOnly)
        // Round trip.
        var n = AppSettings(); n.cueKeys = [CueKey(keycode: 0x7A, memo: "Stop", note: 40)]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back.cueKeys, n.cueKeys)
    }

    func testNewPacketsRoundTrip() throws {
        for body: PacketBody in [.features(flags: 1), .noteAck(seq: 0xDEADBEEF),
                                 .cueName(channel: 1, note: 37, label: "↓", memo: "次のシーン"),
                                 .cueResend(originalSeq: 5, channel: 1, note: 37, velocity: 127, released: true),
                                 .cueCount(seq: 9, count: 12), .features(flags: 3, epoch: 200)] {
            let p = Packet(session: 3, seq: 4, body: body)
            XCTAssertEqual(try Packet.decode(p.encode()), p)
        }
        let long = Packet(session: 1, seq: 1, body: .cueName(channel: 1, note: 1, label: String(repeating: "あ", count: 20),
                                                           memo: String(repeating: "い", count: 40))).encode()
        XCTAssertLessThanOrEqual(long.count + SecureChannel.tagSize, WireProtocol.maxPacketSize)
    }

    func press() {
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
    }

    func testOneSidedReconnectKeepsBothCountsAndNames() {
        main.setCueKeys([CueKey(keycode: down, memo: "Next", note: 37)])
        connect(); tick(1.1)
        for _ in 0..<3 { press() }
        // Only main loses the link (backup -> main traffic is lost), then it comes back.
        backupToMainUp = false
        tick(3.5)
        backupToMainUp = true
        tick(2)
        XCTAssertEqual(main.snapshot().link, .connected(peer: backupID.uuidString))
        press()
        XCTAssertEqual(main.snapshot().lastCue!.count, backup.snapshot().lastCue!.count)
        XCTAssertEqual(backup.snapshot().lastCue!.label, "↓")
        XCTAssertEqual(backup.snapshot().lastCue!.memo, "Next")
    }

    func testOneSidedReconnectOnTheBackupKeepsBothCounts() {
        main.setCueKeys([CueKey(keycode: down, memo: "Next", note: 37)])
        connect(); tick(1.1)
        for _ in 0..<3 { press() }
        mainToBackupUp = false
        tick(3.5)
        mainToBackupUp = true
        tick(2)
        press()
        XCTAssertEqual(main.snapshot().lastCue!.count, backup.snapshot().lastCue!.count)
        XCTAssertEqual(backup.snapshot().lastCue!.memo, "Next")
    }

    func testStaleSwallowEntryDoesNotEatTheNextPress() {
        XCTAssertTrue(main.handleKey(KeyInput(keycode: down, isDown: true)))   // key-up never arrives
        main.setBlockCueKeys(false)
        XCTAssertFalse(main.handleKey(KeyInput(keycode: down, isDown: true)))
        XCTAssertFalse(main.handleKey(KeyInput(keycode: down, isDown: true, isRepeat: true)))
        XCTAssertFalse(main.handleKey(KeyInput(keycode: down, isDown: false)))
        // releaseHeldKeys (tap paused, Secure Input) also forgets swallowed keys.
        main.setBlockCueKeys(true)
        XCTAssertTrue(main.handleKey(KeyInput(keycode: KeyNames.up, isDown: true)))
        main.releaseHeldKeys()
        main.setBlockCueKeys(false)
        XCTAssertFalse(main.handleKey(KeyInput(keycode: KeyNames.up, isDown: false)))
    }

    // MARK: Fixes from the 1.0.0 review

    func testLostFirstOfTwoQuickPressesIsResentAndBothArrive() {
        connect(); tick(1.1)
        var dropping = true
        dropMain = { b in dropping && b[3] == 0x10 }          // both copies of press 1's note-on
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        dropping = false
        main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
        now += 0.04
        main.handleKey(KeyInput(keycode: KeyNames.up, isDown: true)); pump()
        main.handleKey(KeyInput(keycode: KeyNames.up, isDown: false)); pump()
        tick(0.5)
        XCTAssertEqual(cueOnsAtBackup(37), 1, "press 1 resent")
        XCTAssertEqual(cueOnsAtBackup(36), 1)
        XCTAssertEqual(backup.snapshot().lastCue?.count, 2)
        XCTAssertEqual(main.snapshot().lastCue?.count, 2)
        if case .delivered = main.snapshot().lastCue!.delivery {} else { XCTFail("\(main.snapshot().lastCue!.delivery)") }
    }

    func testOlderMissingCueStaysVisibleAfterALaterOneArrives() {
        connect(); tick(1.1)
        var dropping = true
        dropMain = { b in dropping && (b[3] == 0x10 || b[3] == 0x16) }   // press 1 and its resends
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        main.handleKey(KeyInput(keycode: down, isDown: false)); pump()
        tick(0.35)
        dropping = false
        // Not pressed again yet: press 1 shows as missing.
        XCTAssertEqual(main.snapshot().lastCue?.delivery, .missing)
    }

    func testCountsMeetAgainEvenIfTheResetPacketIsLost() {
        main.setCueKeys([CueKey(keycode: down, memo: "Next", note: 37)])
        connect(); tick(1.1)
        for _ in 0..<3 { press() }
        backupToMainUp = false
        tick(3.5)                                             // only main notices the drop
        backupToMainUp = true
        var first = true
        dropMain = { b in if b[3] == 0x13 && first { first = false; return true }; return false }
        tick(3)
        press()
        XCTAssertEqual(main.snapshot().lastCue!.count, backup.snapshot().lastCue!.count)
        XCTAssertEqual(backup.snapshot().lastCue!.memo, "Next")
    }

    func testReplayedOldHelloDoesNotBreakTheLink() {
        // A hello captured from an earlier launch of the main Mac (same pairing code, old session).
        let oldRun = make(mainID, "Main", AppSettings(), FakeMIDI(), FakeNet(), session: 77)
        let oldNet = FakeNet()
        let old = Conductor(instanceID: mainID, displayName: "Main", settings: AppSettings(), midi: nil, net: oldNet,
                            session: 77, clock: { [unowned self] in now }, nanos: { 0 })
        old.setPairing(secret)
        old.connect(to: backupID.uuidString)
        let captured = oldNet.outbox.map(\.bytes)
        _ = oldRun
        connect(); tick(1.1)
        for b in captured { XCTAssertNil(backup.receive(b, knownPeer: mainID.uuidString)) }
        for b in captured { XCTAssertNil(backup.receive(b, knownPeer: nil)) }
        tick(5)
        XCTAssertEqual(backup.snapshot().link, .connected(peer: mainID.uuidString))
        press()
        XCTAssertEqual(cueOnsAtBackup(37), 1, "cues still arrive")
    }

    func testRepeatedHelloIsNotUsedToMoveTheRoute() {
        let net = FakeNet()
        let m = Conductor(instanceID: mainID, displayName: "Main", settings: AppSettings(), midi: nil, net: net,
                          session: 1, clock: { [unowned self] in now }, nanos: { 0 })
        m.setPairing(secret)
        m.connect(to: backupID.uuidString)
        let hello = net.outbox[0].bytes
        XCTAssertEqual(backup.receive(hello, knownPeer: nil), mainID.uuidString)
        XCTAssertNil(backup.receive(hello, knownPeer: nil), "the same hello again changes nothing")
    }

    func testMainRestartWhileLinkedStillReconnects() {
        connect(); tick(1.1)
        press()
        // Main restarts (new session, new nonce) without saying goodbye.
        let newNet = FakeNet()
        main = Conductor(instanceID: mainID, displayName: "Main", settings: { var s = AppSettings(); s.receiveNotes = false; return s }(),
                         midi: mainMIDI, net: newNet, session: 5, clock: { [unowned self] in now }, nanos: { UInt64(self.now * 1e9) })
        main.setPairing(secret)
        mainNet = newNet
        main.connect(to: backupID.uuidString)
        for _ in 0..<40 { now += 0.05; main.tick(); backup.tick(); pump() }
        XCTAssertEqual(main.snapshot().link, .connected(peer: backupID.uuidString))
        press()
        XCTAssertEqual(cueOnsAtBackup(37), 2)
        XCTAssertEqual(backup.snapshot().lastCue?.count, main.snapshot().lastCue?.count)
    }

    func testResetWhileACueWaitsReportsItMissing() {
        connect(); tick(1.1)
        dropMain = { b in b[3] == 0x10 || b[3] == 0x16 }
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        dropMain = { _ in false }
        // The backup reconnected and asks to count again before the answer could come.
        backup.disconnect(); pump(); backup.connect(to: mainID.uuidString); pump()
        XCTAssertEqual(main.snapshot().lastCue?.delivery, .missing)
    }

    func testCueFromTheOtherMacDoesNotHideAWaitingCue() {
        var b = AppSettings(); b.sendKeys = true
        backup = make(backupID, "Backup", b, backupMIDI, backupNet, session: 2)
        var a = AppSettings(); a.receiveNotes = true
        main = make(mainID, "Main", a, mainMIDI, mainNet, session: 1)
        connect(); tick(1.1)
        dropMain = { b in b[3] == 0x10 || b[3] == 0x16 }
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        backup.handleKey(KeyInput(keycode: KeyNames.up, isDown: true)); pump()
        tick(0.4)
        XCTAssertEqual(main.snapshot().lastCue?.delivery, .missing)
    }

    func testOneBadCueKeyEntryKeepsTheOthers() throws {
        let json = #"{"cue_keys":[{"keycode":125,"note":37},{"keycode":"x"},{"keycode":126,"note":999},{"keycode":124,"label":"→","memo":"Go","note":39}],"midi_channel":"two"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.cueKeys.map(\.note), [37, 39])
        XCTAssertEqual(s.cueKeys[0].label, "↓")
        XCTAssertEqual(s.midiChannel, 1)
    }

    func testReplayOfAnEarlierMainSessionIsNotTakenBack() {
        connect(); tick(1.1)
        var captured: [[UInt8]] = []
        dropMain = { b in captured.append(b); return false }
        press(); tick(1.1)
        dropMain = { _ in false }
        // Main restarts as a new session and relinks.
        let newNet = FakeNet()
        main = Conductor(instanceID: mainID, displayName: "Main", settings: { var s = AppSettings(); s.receiveNotes = false; return s }(),
                         midi: mainMIDI, net: newNet, session: 5, clock: { [unowned self] in now }, nanos: { UInt64(self.now * 1e9) })
        main.setPairing(secret)
        mainNet = newNet
        main.connect(to: backupID.uuidString)
        for _ in 0..<40 { now += 0.05; main.tick(); backup.tick(); pump() }
        let before = cueOnsAtBackup(37)
        // Someone replays everything captured from the first session.
        for b in captured { backup.receive(b, knownPeer: mainID.uuidString) }
        pump(); tick(1)
        XCTAssertEqual(cueOnsAtBackup(37), before, "no old cue plays again")
        XCTAssertEqual(backup.snapshot().link, .connected(peer: mainID.uuidString))
    }

    func testResentCueEndsWhenTheKeyWasReleasedByTheApp() {
        connect(); tick(1.1)
        dropMain = { b in b[3] == 0x10 }
        main.handleKey(KeyInput(keycode: down, isDown: true)); pump()
        dropMain = { _ in false }
        main.releaseHeldKeys()                    // e.g. Secure Input started; no key-up seen
        tick(0.4)
        XCTAssertEqual(backupMIDI.sent.filter { $0[1] == 37 }.last, [0x80, 37, 0])
    }

    func testLateOrderFreePacketsAreAcceptedOnceButLateNotesAreNot() {
        var f = SequenceFilter()
        XCTAssertTrue(f.accept(session: 1, seq: 10))
        XCTAssertTrue(f.accept(session: 1, seq: 12))
        XCTAssertFalse(f.accept(session: 1, seq: 11), "a late note is still dropped")
        XCTAssertTrue(f.accept(session: 1, seq: 11, allowLate: true))
        XCTAssertFalse(f.accept(session: 1, seq: 11, allowLate: true), "only once")
        XCTAssertFalse(f.accept(session: 1, seq: 12, allowLate: true))
        XCTAssertTrue(f.accept(session: 1, seq: 200))
        XCTAssertFalse(f.accept(session: 1, seq: 100, allowLate: true), "too old")
    }
}
