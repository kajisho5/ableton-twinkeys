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
            if mainToBackupUp { for (_, x) in a { backup.receive(x, knownPeer: mainID.uuidString) } }
            if backupToMainUp { for (_, x) in b where !dropFromBackup.contains(x[3]) { main.receive(x, knownPeer: backupID.uuidString) } }
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
                                 .cueResend(originalSeq: 5, channel: 1, note: 37, velocity: 127, released: true)] {
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
}
