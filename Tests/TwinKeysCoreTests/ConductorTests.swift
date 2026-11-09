import XCTest
@testable import TwinKeysCore

/// Two simulated Macs ("main" and "backup") wired through a fake network.
final class ConductorTests: XCTestCase {
    final class FakeMIDI: MIDIOutput {
        var sent: [[UInt8]] = []
        func send(_ bytes: [UInt8]) { sent.append(bytes) }
        var notes: [[UInt8]] { sent.filter { $0[0] & 0xF0 != 0xB0 } }
        var allNotesOffCount: Int { sent.filter { $0[0] & 0xF0 == 0xB0 && $0[1] == 123 }.count }
    }
    final class FakeNet: PacketSink {
        var outbox: [(peer: String, bytes: [UInt8])] = []
        var resets: [String] = []
        func send(_ bytes: [UInt8], to peer: String) { outbox.append((peer, bytes)) }
        func resetRoute(to peer: String) { resets.append(peer) }
    }

    var now = 0.0
    let mainID = UUID(), backupID = UUID()
    var mainMIDI = FakeMIDI(), backupMIDI = FakeMIDI()
    var mainNet = FakeNet(), backupNet = FakeNet()
    var main: Conductor!, backup: Conductor!
    var mainToBackupUp = true

    override func setUp() {
        var s = AppSettings()
        s.sendKeys = true; s.receiveNotes = true
        main = Conductor(instanceID: mainID, displayName: "Main", mapping: .default, settings: s,
                         midi: mainMIDI, net: mainNet, session: 1,
                         clock: { [unowned self] in now }, nanos: { [unowned self] in UInt64(now * 1e9) })
        var b = AppSettings(); b.sendKeys = false
        backup = Conductor(instanceID: backupID, displayName: "Backup", mapping: .default, settings: b,
                           midi: backupMIDI, net: backupNet, session: 2,
                           clock: { [unowned self] in now }, nanos: { [unowned self] in UInt64(now * 1e9) })
    }

    /// Deliver everything queued in both directions until quiet.
    func pump() {
        for _ in 0..<10 {
            let a = mainNet.outbox; mainNet.outbox.removeAll()
            let b = backupNet.outbox; backupNet.outbox.removeAll()
            if a.isEmpty && b.isEmpty { return }
            if mainToBackupUp {
                for (_, bytes) in a { backup.receive(bytes, knownPeer: mainID.uuidString) }
                for (_, bytes) in b { main.receive(bytes, knownPeer: backupID.uuidString) }
            }
        }
    }

    func connect() {
        main.connect(to: backupID.uuidString)
        pump()
        XCTAssertEqual(main.snapshot().link, .connected(peer: backupID.uuidString))
        XCTAssertEqual(backup.snapshot().link, .connected(peer: mainID.uuidString))
    }

    func testKeyPressPlaysSameNoteOnBothMacs() {
        connect()
        main.handleKey(KeyInput(keycode: 0x00, isDown: true))
        main.handleKey(KeyInput(keycode: 0x02, isDown: true))   // chord
        pump()
        main.handleKey(KeyInput(keycode: 0x00, isDown: false))
        main.handleKey(KeyInput(keycode: 0x02, isDown: false))
        pump()
        let expected: [[UInt8]] = [[0x90, 60, 100], [0x90, 64, 100], [0x80, 60, 0], [0x80, 64, 0]]
        XCTAssertEqual(mainMIDI.notes, expected)
        // Each note was sent twice on the wire, but arrives once.
        XCTAssertEqual(backupMIDI.notes, expected)
        XCTAssertEqual(backup.snapshot().peerNames[mainID.uuidString], "Main")
    }

    func testReceiverWithReceiveOffPlaysNothing() {
        connect()
        backup.setReceiveNotes(false)
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        XCTAssertEqual(backupMIDI.notes, [])
    }

    func testSendOffMeansKeysDoNothing() {
        connect()
        main.setSendKeys(false)
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        XCTAssertEqual(mainMIDI.notes, []); XCTAssertEqual(backupMIDI.notes, [])
    }

    func testTurningSendOffEndsHeldNotesOnBothMacs() {
        connect()
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        main.setKeyCapture(false); pump()
        XCTAssertEqual(mainMIDI.notes.last, [0x80, 60, 0])
        XCTAssertEqual(backupMIDI.notes.last, [0x80, 60, 0])
    }

    func testPanicSendsAllNotesOffToBothMacs() {
        connect()
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        main.panic(); pump()
        XCTAssertEqual(mainMIDI.allNotesOffCount, 16)
        XCTAssertEqual(backupMIDI.allNotesOffCount, 16)   // two copies sent, one applied
        XCTAssertTrue(mainMIDI.sent.contains([0x80, 60, 0]))
        XCTAssertTrue(backupMIDI.sent.contains([0x80, 60, 0]))
    }

    func testPanicWhenNotConnectedOnlyLocal() {
        main.panic()
        XCTAssertEqual(mainMIDI.allNotesOffCount, 16)
        XCTAssertTrue(mainNet.outbox.isEmpty)
    }

    func testQuitSendsAllNotesOffAndByeSoPeerStops() {
        connect()
        main.prepareForQuit(); pump()
        XCTAssertEqual(mainMIDI.allNotesOffCount, 32)   // panic + disconnect
        XCTAssertGreaterThanOrEqual(backupMIDI.allNotesOffCount, 16)
        XCTAssertEqual(backup.snapshot().link, .idle)
        XCTAssertEqual(main.snapshot().link, .idle)
    }

    func testNetworkLossKeepsMainNotesButEndsBackupNotesThenReconnects() {
        connect()
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        mainToBackupUp = false
        for _ in 0..<40 { now += 0.1; main.tick(); backup.tick(); pump() }   // 4 s of silence
        if case .connecting = backup.snapshot().link {} else { XCTFail("backup should be reconnecting") }
        XCTAssertEqual(backupMIDI.notes.last, [0x80, 60, 0])            // note from the main Mac was ended
        XCTAssertEqual(mainMIDI.notes, [[0x90, 60, 100]])               // main's own note keeps sounding
        mainToBackupUp = true
        for _ in 0..<60 { now += 0.1; main.tick(); backup.tick(); pump() }
        XCTAssertTrue(main.snapshot().link == .connected(peer: backupID.uuidString))
        XCTAssertTrue(backup.snapshot().link == .connected(peer: mainID.uuidString))
        XCTAssertNotNil(main.snapshot().latencyMs)
    }

    func testAutoNoteOffOnReceiverAfterTenSeconds() {
        connect()
        main.handleKey(KeyInput(keycode: 0x00, isDown: true)); pump()
        // Heartbeats keep the link up; the note-off never comes.
        for _ in 0..<99 { now += 0.1; main.tick(); backup.tick(); pump() }
        XCTAssertFalse(backupMIDI.sent.contains([0x80, 60, 0]))
        for _ in 0..<3 { now += 0.1; main.tick(); backup.tick(); pump() }
        XCTAssertTrue(backupMIDI.sent.contains([0x80, 60, 0]))
    }

    func testPacketsFromUnknownRouteAreIgnoredUnlessHello() {
        let note = Packet(session: 9, seq: 1, body: .noteOn(channel: 0, note: 60, velocity: 1)).encode()
        XCTAssertNil(backup.receive(note, knownPeer: nil))
        XCTAssertEqual(backupMIDI.sent, [])
        // A note from a known route but without a link is also ignored.
        XCTAssertEqual(backup.receive(note, knownPeer: "stranger"), "stranger")
        XCTAssertEqual(backupMIDI.sent, [])
        // Our own hello coming back (e.g. multicast loop) is ignored.
        let own = Packet(session: 9, seq: 2, body: .hello(instanceID: backupID, name: "x")).encode()
        XCTAssertNil(backup.receive(own, knownPeer: nil))
    }

    func testHelloResetsRouteForReconnect() {
        main.connect(to: backupID.uuidString)
        XCTAssertEqual(mainNet.resets, [backupID.uuidString])
    }
}
