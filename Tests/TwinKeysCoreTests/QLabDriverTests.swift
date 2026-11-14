import Foundation
import XCTest
@testable import TwinKeysCore

/// Two linked Conductors over a fake network (as ConductorTests, usable outside an XCTestCase).
final class TwoMacs {
    var now = 0.0
    let mainID = UUID(), backupID = UUID()
    let mainMIDI = ConductorTests.FakeMIDI(), backupMIDI = ConductorTests.FakeMIDI()
    let mainNet = ConductorTests.FakeNet(), backupNet = ConductorTests.FakeNet()
    var main: Conductor!, backup: Conductor!
    let secret = PairingSecret(keyBytes: Array(repeating: 42, count: 32))
    static let keys = [CueKey(keycode: 0x00, note: 60), CueKey(keycode: 0x02, note: 64)]

    init(nonces: ([UInt8], [UInt8])? = nil) {
        var s = AppSettings()
        s.sendKeys = true; s.receiveNotes = true; s.cueKeys = Self.keys
        main = Conductor(instanceID: mainID, displayName: "Main", settings: s, midi: mainMIDI, net: mainNet, session: 1,
                         clock: { [unowned self] in self.now }, nanos: { [unowned self] in UInt64(self.now * 1e9) })
        var b = AppSettings(); b.sendKeys = false; b.cueKeys = Self.keys
        backup = Conductor(instanceID: backupID, displayName: "Backup", settings: b, midi: backupMIDI, net: backupNet, session: 2,
                           clock: { [unowned self] in self.now }, nanos: { [unowned self] in UInt64(self.now * 1e9) })
        main.setPairing(secret, nonce: nonces?.0)
        backup.setPairing(secret, nonce: nonces?.1)
    }

    func pump() {
        for _ in 0..<10 {
            let a = mainNet.outbox; mainNet.outbox.removeAll()
            let b = backupNet.outbox; backupNet.outbox.removeAll()
            if a.isEmpty && b.isEmpty { return }
            for (_, bytes) in a { backup.receive(bytes, knownPeer: mainID.uuidString) }
            for (_, bytes) in b { main.receive(bytes, knownPeer: backupID.uuidString) }
        }
    }

    func connect() {
        main.connect(to: backupID.uuidString)
        pump()
        XCTAssertEqual(main.snapshot().link, .connected(peer: backupID.uuidString))
    }
}

/// QLab mode between two Macs (docs/design-qlab.md 5.3): the main Mac runs a command on its QLab
/// and forwards it; the backup follows the main Mac's cue number, corrects its playhead, refuses a
/// cue it does not have, and runs a resend only once.
final class QLabDriverTests: XCTestCase {
    /// A QLab that does what QLabPlanner says (instead of a TCP connection).
    final class SimQLab {
        var cues: [QLabCue]
        var playhead: Int?
        var started: [String] = []
        var events: [String] = []
        var state: QLabConnState = .ready
        var lastGoAt = -100.0
        var now: () -> Double
        init(numbers: [String], playhead: Int?, now: @escaping () -> Double) {
            cues = numbers.map { QLabCue(uniqueID: "u" + $0, number: $0, name: "Cue " + $0, type: .audio, duration: 10) }
            self.playhead = playhead
            self.now = now
        }
        var snapshot: QLabEngineSnapshot {
            var s = QLabEngineSnapshot()
            s.transportUp = true; s.state = state; s.permissions = [.view, .control]
            s.workspace = QLabWorkspaceInfo(uniqueID: "W", displayName: "sample-show")
            s.cues = cues; s.allCues = cues; s.listName = "Main"
            s.playhead = playhead.map { QLabCueRef(uniqueID: cues[$0].uniqueID, number: cues[$0].number) }
            s.lastGoAt = lastGoAt
            return s
        }
        func apply(_ m: OSCMessage) {
            let parts = m.address.split(separator: "/").map(String.init)
            func start(_ i: Int) { started.append(cues[i].number); playhead = i + 1 < cues.count ? i + 1 : nil; lastGoAt = now() }
            switch Array(parts.dropFirst(2)) {
            case ["go"]: if let p = playhead { start(p) }
            case let x where x.count == 3 && x[0] == "cue_id" && x[2] == "go":
                if let i = cues.firstIndex(where: { $0.uniqueID == x[1] }) { start(i) }
            case let x where x.count == 2 && x[0] == "playheadID":
                playhead = cues.firstIndex { $0.uniqueID == x[1] }; events.append("playhead \(cues[playhead!].number)")
            case ["playhead", "next"]: playhead = min((playhead ?? -1) + 1, cues.count - 1)
            case ["playhead", "previous"]: playhead = max((playhead ?? 1) - 1, 0)
            default: events.append(parts.last ?? "")
            }
        }
        func run(_ cmd: QLabCommand, asBackup: Bool, done: (QLabResultCode) -> Void) {
            guard state.canControl else { done(.notConnected); return }
            switch QLabPlanner.plan(cmd, workspace: "W", cues: cues, playhead: snapshot.playhead, asBackup: asBackup) {
            case let .refuse(c): done(c)
            case let .send(msgs, c): msgs.forEach(apply); done(c)
            }
        }
        func follow(_ n: String?) {
            if let m = QLabPlanner.follow(mainNumber: n, playhead: snapshot.playhead, cues: cues, workspace: "W", lastGoAt: lastGoAt, now: now()) { apply(m) }
        }
    }

    var link: TwoMacs!
    var mainQ: SimQLab!, backupQ: SimQLab!
    var mainD: QLabDriver!, backupD: QLabDriver!
    let numbers = ["1", "2", "10", "11", "12", "13", "14"]

    override func setUp() {
        link = TwoMacs()
        let clock = { [unowned self] in self.link.now }
        mainQ = SimQLab(numbers: numbers, playhead: 5, now: clock)        // 13 standing by
        backupQ = SimQLab(numbers: numbers, playhead: 5, now: clock)
        mainD = makeDriver(link.main, mainQ)
        backupD = makeDriver(link.backup, backupQ)
        mainD.attach(); backupD.attach()
        link.connect()
    }

    func makeDriver(_ c: Conductor, _ q: SimQLab) -> QLabDriver {
        QLabDriver(conductor: c, settings: QLabSettings(), target: .qlab, clock: { [unowned self] in self.link.now },
                   snapshot: { q.snapshot }, runLocal: { cmd, b, done in q.run(cmd, asBackup: b, done: done) },
                   followLocal: { q.follow($0) })
    }

    /// Sends `cmd` from the main Mac and waits for its outcome (the backup answers on another queue).
    func send(_ cmd: QLabCommand, deliver: Bool = true) -> QLabDriver.Outcome? {
        var out: QLabDriver.Outcome?
        mainD.command(cmd) { out = $0 }
        let deadline = Date().addingTimeInterval(3)
        while out == nil, Date() < deadline {
            if deliver { link.pump() } else { link.mainNet.outbox.removeAll() }
            Thread.sleep(forTimeInterval: 0.005)
            link.now += 0.01
            link.main.tick(); link.backup.tick()
            mainD.tick()
        }
        link.pump()
        return out
    }

    func testGoRunsOnBothMacsWithTheSameCue() {
        let o = send(QLabCommand(action: .go, expect: "13"))
        XCTAssertEqual(o, QLabDriver.Outcome(ok: true, error: nil, backup: "delivered"))
        XCTAssertEqual(mainQ.started, ["13"])
        XCTAssertEqual(backupQ.started, ["13"])
        XCTAssertEqual(mainD.lastCommand?.number, "13")
        XCTAssertEqual(mainD.lastCommand?.backup, "delivered")
    }

    func testBackupOnAnotherCueIsCorrected() {
        backupQ.playhead = 4                         // 12
        let o = send(QLabCommand(action: .go))       // a cue key: no expect from the sender
        XCTAssertEqual(o?.backup, "corrected")
        XCTAssertEqual(mainQ.started, ["13"])
        XCTAssertEqual(backupQ.started, ["13"])      // never 12
    }

    func testBackupWithoutTheCuePlaysNothing() {
        backupQ.cues.remove(at: 5)                   // no 13 on the backup
        backupQ.playhead = 4
        let o = send(QLabCommand(action: .go))
        XCTAssertEqual(o?.ok, true)
        XCTAssertEqual(o?.backup, "noSuchCue")
        XCTAssertEqual(backupQ.started, [])
    }

    func testGoIsRefusedWhenNextChangedAndNothingIsSent() {
        let o = send(QLabCommand(action: .go, expect: "12"))     // the iPhone still showed 12
        XCTAssertEqual(o, QLabDriver.Outcome(ok: false, error: "qlab_next_changed", backup: "notSent"))
        XCTAssertEqual(mainQ.started, [])
        XCTAssertEqual(backupQ.started, [])
        // With the setting off it goes.
        mainD.setSettings({ var s = QLabSettings(); s.refuseStaleGo = false; return s }(), target: .qlab)
        XCTAssertEqual(send(QLabCommand(action: .go, expect: "12"))?.ok, true)
        XCTAssertEqual(backupQ.started, ["13"])
    }

    func testMainQLabNotConnectedSendsNoGoToTheBackup() {
        mainQ.state = .connecting
        let o = send(QLabCommand(action: .go, expect: "13"))
        XCTAssertEqual(o, QLabDriver.Outcome(ok: false, error: "qlab_notConnected", backup: "notSent"))
        XCTAssertEqual(backupQ.started, [])
        // Panic still reaches the backup.
        let p = send(QLabCommand(action: .panic))
        XCTAssertEqual(p?.backup, "delivered")
        XCTAssertEqual(backupQ.events.last, "panic")
    }

    func testLostCommandIsResentOnceAndRunsOnce() {
        // The first copies are lost; the resend (0.1 s later) gets through.
        var out: QLabDriver.Outcome?
        mainD.command(QLabCommand(action: .go, expect: "13")) { out = $0 }
        link.mainNet.outbox.removeAll()
        for _ in 0..<12 { link.now += 0.01; link.main.tick() }      // 0.12 s: one resend queued
        let resends = link.mainNet.outbox
        XCTAssertFalse(resends.isEmpty)
        // Deliver it twice (a duplicate on the network).
        for (_, b) in resends + resends { link.backup.receive(b, knownPeer: link.mainID.uuidString) }
        let deadline = Date().addingTimeInterval(2)
        while out == nil, Date() < deadline { link.pump(); Thread.sleep(forTimeInterval: 0.005); link.now += 0.005; mainD.tick() }
        XCTAssertEqual(out?.backup, "delivered")
        XCTAssertEqual(backupQ.started, ["13"])
    }

    func testNoAnswerFromTheBackupTurnsRed() {
        let o = send(QLabCommand(action: .go, expect: "13"), deliver: false)
        XCTAssertEqual(o?.ok, true)
        XCTAssertEqual(o?.backup, "missing")
    }

    func testBackupFollowsTheMainPlayhead() {
        backupQ.playhead = 1
        mainD.publish(mainQ.snapshot, keys: CueKey.defaults)
        link.pump()
        XCTAssertEqual(backupQ.playhead, 5)
        // A GO a moment ago on the backup: it waits (auto-continue cues may still move).
        backupQ.playhead = 2
        backupQ.lastGoAt = link.now
        mainQ.playhead = 6
        mainD.publish(mainQ.snapshot, keys: CueKey.defaults)
        link.pump()
        XCTAssertEqual(backupQ.playhead, 2)
        // The backup never pulls the main.
        mainQ.playhead = 0
        backupD.publish(backupQ.snapshot, keys: CueKey.defaults)
        link.pump()
        XCTAssertEqual(mainQ.playhead, 0)
    }

    func testStatusShowsTheBackupsQLab() {
        mainD.publish(mainQ.snapshot, keys: CueKey.defaults)
        backupD.publish(backupQ.snapshot, keys: CueKey.defaults)
        link.pump()
        let st = mainD.status(mainQ.snapshot, stamp: 1)
        XCTAssertEqual(st.backup?.supported, true)
        XCTAssertEqual(st.backup?.sameCues, true)
        XCTAssertEqual(st.backup?.samePlayhead, true)
        XCTAssertEqual(st.backup?.playheadNumber, "13")
        XCTAssertNil(link.main.qlabDiff)
        // One cue renamed on the backup: the hashes differ and the items come with the heartbeats.
        backupQ.cues[2].name = "第1場 v2"
        backupD.publish(backupQ.snapshot, keys: CueKey.defaults)
        for _ in 0..<30 { link.now += 0.1; link.main.tick(); link.backup.tick(); link.pump() }
        XCTAssertEqual(mainD.status(mainQ.snapshot, stamp: 2).backup?.sameCues, false)
        XCTAssertEqual(link.main.qlabDiff?.differences, 1)
        XCTAssertEqual(link.main.qlabDiff?.rows.first?.index, 2)
    }

    func testCueKeysInQLabModeSendNoNotesUnlessAsked() {
        link.main.setCueKeyMode(notes: false, qlab: true)
        var keys: [String] = []
        link.main.onQLabCueKey = { keys.append($0.label) }
        link.main.handleKey(KeyInput(keycode: 0x00, isDown: true))
        link.main.handleKey(KeyInput(keycode: 0x00, isDown: true, isRepeat: true))
        link.main.handleKey(KeyInput(keycode: 0x00, isDown: false))
        link.pump()
        XCTAssertEqual(keys, ["A"])
        XCTAssertTrue(link.mainMIDI.notes.isEmpty)
        XCTAssertTrue(link.backupMIDI.notes.isEmpty)
        // Both: the note and the QLab action.
        link.main.setCueKeyMode(notes: true, qlab: true)
        link.main.handleKey(KeyInput(keycode: 0x00, isDown: true))
        link.main.handleKey(KeyInput(keycode: 0x00, isDown: false))
        link.pump()
        XCTAssertEqual(keys, ["A", "A"])
        XCTAssertEqual(link.backupMIDI.notes.count, 2)
    }

    func testAnOldPeerIsReportedUnsupported() throws {
        // A Mac whose features lack the QLab bit (an older TwinKeys, or TwinKeys for Windows).
        let a: [UInt8] = Array(repeating: 1, count: 16), b: [UInt8] = Array(repeating: 2, count: 16)
        let fresh = TwoMacs(nonces: (a, b))
        fresh.connect()
        XCTAssertEqual(fresh.main.peerUnderstandsQLab, true)
        let old = SecureChannel(secret: fresh.secret, myNonce: b)
        let bytes: [UInt8] = try XCTUnwrap(old.seal(Packet(session: 2, seq: 10_000, body: .features(flags: 1, epoch: 9)), peerNonce: a))
        fresh.main.receive(bytes, knownPeer: fresh.backupID.uuidString)
        XCTAssertEqual(fresh.main.peerUnderstandsQLab, false)
        XCTAssertEqual(fresh.main.forwardQLab(QLabCommand(action: .go)), Conductor.QLabForward.unsupported)
        fresh.main.disconnect()
        XCTAssertEqual(fresh.main.forwardQLab(QLabCommand(action: .go)), Conductor.QLabForward.notLinked)
    }
}
