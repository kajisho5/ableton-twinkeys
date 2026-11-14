#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import XCTest
@testable import TwinKeysCore

/// QLabEngine against scripts/fake-qlab.py over real TCP with SLIP (docs/design-qlab.md 8.1): the
/// connection steps, passcodes, GO with the cue number, the playhead, running cues and Panic.
/// The app gives the same engine a Network.framework connection; here it is a plain socket.
/// Skipped when python3 is not there.
final class QLabFakeServerTests: XCTestCase {
    static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("scripts/fake-qlab.py")

    /// The fake QLab, its port and the EVENT lines it printed.
    final class Fake {
        let process = Process()
        let input = Pipe(), output = Pipe()
        private let lock = NSLock()
        private var text = ""
        var port: UInt16 = 0

        init(_ args: [String]) throws {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-u", QLabFakeServerTests.script.path, "--port", "0", "--no-udp"] + args
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let h = output.fileHandleForReading
            Thread.detachNewThread { [weak self] in
                while true {
                    let d = h.availableData
                    if d.isEmpty { return }
                    guard let self else { return }
                    self.lock.lock(); self.text += String(decoding: d, as: UTF8.self); self.lock.unlock()
                }
            }
            let deadline = Date().addingTimeInterval(10)
            while port == 0, Date() < deadline {
                if let r = all.range(of: "127.0.0.1:"), let end = all[r.upperBound...].firstIndex(of: "\n") {
                    port = UInt16(all[r.upperBound..<end]) ?? 0
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        var all: String { lock.lock(); defer { lock.unlock() }; return text }
        var events: [String] { all.split(separator: "\n").filter { $0.hasPrefix("EVENT ") }.map { String($0.dropFirst(6)) } }

        func type(_ line: String) { input.fileHandleForWriting.write(Data((line + "\n").utf8)) }

        func stop() {
            type("quit")
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
    }

    /// A blocking TCP socket to 127.0.0.1, read without waiting.
    final class Socket {
        let fd: Int32
        init?(port: UInt16) {
            #if os(Linux)
            fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
            #else
            fd = socket(AF_INET, SOCK_STREAM, 0)
            #endif
            guard fd >= 0 else { return nil }
            var a = sockaddr_in()
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            inet_pton(AF_INET, "127.0.0.1", &a.sin_addr)
            let ok = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if ok != 0 { close(fd); return nil }
        }
        func send(_ b: [UInt8]) { _ = b.withUnsafeBytes { write(fd, $0.baseAddress, b.count) } }
        func readAvailable() -> [UInt8]? {
            var buf = [UInt8](repeating: 0, count: 65536)
            #if os(Linux)
            let n = recv(fd, &buf, buf.count, Int32(MSG_DONTWAIT))
            #else
            let n = recv(fd, &buf, buf.count, MSG_DONTWAIT)
            #endif
            if n > 0 { return Array(buf[0..<n]) }
            if n == 0 { return nil }          // closed
            // Nothing to read yet; anything else (a reset on macOS) means the connection is gone.
            return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? [] : nil
        }
        deinit { close(fd) }
    }

    var fake: Fake!
    var sock: Socket!
    var engine: QLabEngine!
    var closed = false

    func start(_ args: [String] = [], passcode: String = "1234", workspace: String? = nil) throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/env") else { throw XCTSkip("no /usr/bin/env") }
        // A write to the dropped connection (or to the fake after it quit) must not end the test run.
        signal(SIGPIPE, SIG_IGN)
        fake = try Fake(args)
        guard fake.port != 0 else { fake.stop(); throw XCTSkip("python3 / fake-qlab.py did not start") }
        sock = try XCTUnwrap(Socket(port: fake.port))
        engine = QLabEngine(config: .init(workspaceName: workspace, passcode: passcode), clock: { ProcessInfo.processInfo.systemUptime })
        engine.send = { [unowned self] in self.sock.send($0) }
        engine.transportConnected()
    }

    override func tearDown() {
        fake?.stop()
        sock = nil
    }

    /// Runs the engine until `cond` holds (or `timeout`).
    @discardableResult
    func run(_ timeout: Double = 5, until cond: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let b = sock.readAvailable() { if !b.isEmpty { engine.received(b) } } else if !closed { closed = true; engine.transportClosed() }
            engine.tick()
            if cond() { return true }
            usleep(5_000)
        }
        return cond()
    }

    func command(_ c: QLabCommand, asBackup: Bool = false) -> QLabResultCode? {
        var r: QLabResultCode?
        engine.run(c, asBackup: asBackup) { r = $0 }
        run { r != nil }
        return r
    }

    func testConnectsReadsTheListAndFollowsGo() throws {
        try start()
        XCTAssertTrue(run { self.engine.snapshot.state == .ready && !self.engine.snapshot.cues.isEmpty && self.engine.snapshot.playhead != nil },
                      "state \(engine.snapshot.state)")
        let s = engine.snapshot
        XCTAssertEqual(s.workspace?.displayName, "sample-show")
        XCTAssertEqual(s.version, "5.6.5")
        XCTAssertEqual(s.listName, "Main")
        XCTAssertEqual(s.cues.map(\.number), ["1", "2", "3", "4", "10", "11", "11.5", "12", "13", "14", "15", "90"])
        XCTAssertEqual(s.cues.first { $0.number == "12" }?.depth, 1)
        XCTAssertEqual(s.playhead?.number, "1")
        XCTAssertTrue(run { self.engine.snapshot.showMode })
        // Lengths arrive in the background.
        XCTAssertTrue(run { self.engine.snapshot.cues.first { $0.number == "12" }?.duration == 200 })

        XCTAssertEqual(command(QLabCommand(action: .setPlayhead, cueNumber: "12")), .ok)
        XCTAssertTrue(run { self.engine.snapshot.playhead?.number == "12" })
        XCTAssertEqual(command(QLabCommand(action: .go, expect: "12")), .ok)
        // The playhead moves on (an /update), and cue 12 runs with its time left.
        XCTAssertTrue(run { self.engine.snapshot.playhead?.number == "13" })
        XCTAssertTrue(run { self.engine.snapshot.running.first?.number == "12" && self.engine.snapshot.running.first?.duration == 200 })
        let left = try XCTUnwrap(engine.snapshot.running.first?.left)
        XCTAssertGreaterThan(left, 190)
        XCTAssertEqual(fake.events.filter { $0.hasPrefix("go") }, ["go 12"])

        // Panic, and Panic again during the fade: stops at once.
        XCTAssertEqual(command(QLabCommand(action: .panic)), .ok)
        XCTAssertEqual(command(QLabCommand(action: .panic)), .ok)
        XCTAssertTrue(run { self.fake.events.contains("panicNow") })
        XCTAssertTrue(run { self.engine.snapshot.running.isEmpty })
    }

    func testBackupGoesTheMainsCueWhenItsPlayheadIsElsewhere() throws {
        try start()
        XCTAssertTrue(run { self.engine.snapshot.state == .ready && self.engine.snapshot.playhead != nil })
        // Standing by on 1; the main Mac GOes 13: the backup GOes 13 ("corrected"), never 1.
        XCTAssertEqual(command(QLabCommand(action: .go, expect: "13"), asBackup: true), .corrected)
        XCTAssertTrue(run { self.fake.events.contains("go 13") })
        XCTAssertFalse(fake.events.contains("go 1"))
        XCTAssertEqual(command(QLabCommand(action: .go, expect: "77"), asBackup: true), .noSuchCue)
        // Following the main Mac's playhead.
        XCTAssertFalse(engine.follow(mainNumber: "90"))      // a GO a moment ago: waits
        run(0.6) { false }
        XCTAssertTrue(engine.follow(mainNumber: "90"))
        XCTAssertTrue(run { self.engine.snapshot.playhead?.number == "90" })
        // The person moves the playhead on the Mac (the fake's terminal): seen through /update.
        fake.type("move 4")
        XCTAssertTrue(run { self.engine.snapshot.playhead?.number == "4" })
    }

    func testWrongAndViewOnlyPasscodes() throws {
        try start(passcode: "0000")
        XCTAssertTrue(run { self.engine.snapshot.state == .badPasscode }, "\(engine.snapshot.state)")
        var r: QLabResultCode?
        engine.run(QLabCommand(action: .go), asBackup: false) { r = $0 }
        XCTAssertEqual(r, .badPasscode)
        // Fixed in the settings: connects.
        engine.setConfig(.init(workspaceID: engine.config.workspaceID, workspaceName: "sample-show", passcode: "5678"))
        // 5678 can only view: the probe finds out, GO is refused.
        XCTAssertTrue(run { self.engine.snapshot.state == .viewOnly }, "\(engine.snapshot.state)")
        XCTAssertEqual(engine.snapshot.permissions, [.view])
        engine.run(QLabCommand(action: .go), asBackup: false) { r = $0 }
        XCTAssertEqual(r, .denied)
        XCTAssertFalse(engine.snapshot.cues.isEmpty)          // still shows the list
    }

    func testPermissionsInTheConnectAnswerAndNoPasscode() throws {
        try start(["--connect-permissions", "--no-passcode", "view,control"], passcode: "")
        XCTAssertTrue(run { self.engine.snapshot.state == .ready })
        XCTAssertEqual(engine.snapshot.permissions, [.view, .control])
    }

    func testNoPasscodeWithoutRights() throws {
        try start(passcode: "")
        XCTAssertTrue(run { self.engine.snapshot.state == .needsPasscode })
    }

    func testTwoWorkspacesWaitForAChoice() throws {
        try start(["--two-workspaces"])
        XCTAssertTrue(run { self.engine.snapshot.state == .choosingWorkspace })
        XCTAssertEqual(engine.snapshot.workspaces.map(\.displayName), ["sample-show", "rehearsal"])
        engine.setConfig(.init(workspaceID: engine.snapshot.workspaces[1].uniqueID, passcode: "1234"))
        XCTAssertTrue(run { self.engine.snapshot.state == .ready && self.engine.snapshot.cues.count == 1 })
        XCTAssertEqual(engine.snapshot.workspace?.displayName, "rehearsal")
    }

    func testOSCAccessOffShowsNoAnswer() throws {
        try start(["--silent"])
        XCTAssertTrue(run(5) { self.engine.snapshot.state == .noAnswer })
    }

    func testWorkspaceClosingAndConnectionDrop() throws {
        try start()
        // Ready and the list read: /updates 1 (sent right after the connect) has been handled by now.
        XCTAssertTrue(run { self.engine.snapshot.state == .ready && !self.engine.snapshot.cues.isEmpty && self.engine.snapshot.playhead != nil })
        var states: [QLabConnState] = []
        engine.onChange = { [unowned self] in if states.last != self.engine.snapshot.state { states.append(self.engine.snapshot.state) } }
        fake.type("close")
        // The workspace says it closes: back to the start, then connected again (the fake keeps it open).
        XCTAssertTrue(run { states.contains(.connecting) }, "states \(states); fake: \(fake.all)")
        XCTAssertTrue(run { self.engine.snapshot.state == .ready }, "states \(states)")
        fake.type("drop")
        XCTAssertTrue(run { self.closed })
        XCTAssertEqual(engine.snapshot.state, .connecting)
        XCTAssertFalse(engine.snapshot.transportUp)
        var r: QLabResultCode?
        engine.run(QLabCommand(action: .go), asBackup: false) { r = $0 }
        XCTAssertEqual(r, .notConnected)
    }
}
