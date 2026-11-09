import XCTest
@testable import TwinKeysCore

final class SafetyTests: XCTestCase {
    func testAllNotesOffDestinations() {
        let remoteWhenConnected: [SafetyTrigger] = [.panicButton, .appWillQuit, .manualDisconnect, .sendingTurnedOff, .keyCaptureTurnedOff]
        for t in remoteWhenConnected {
            XCTAssertEqual(Safety.plan(for: t, connected: true), SafetyPlan(local: true, remote: true), "\(t)")
            XCTAssertEqual(Safety.plan(for: t, connected: false), SafetyPlan(local: true, remote: false), "\(t)")
        }
        for t in [SafetyTrigger.connectionLost, .peerSaidBye] {
            XCTAssertEqual(Safety.plan(for: t, connected: true), SafetyPlan(local: true, remote: false), "\(t)")
        }
    }

    func testAutoNoteOffAfterTimeout() {
        var g = NoteGuard(timeout: 10)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        g.record(.noteOn(channel: 0, note: 64, velocity: 100), now: 5)
        XCTAssertEqual(g.expire(now: 9.9), [])
        XCTAssertEqual(g.expire(now: 10), [.noteOff(channel: 0, note: 60)])
        XCTAssertEqual(g.expire(now: 15), [.noteOff(channel: 0, note: 64)])
        XCTAssertEqual(g.expire(now: 100), [])
    }

    func testNoteOffCancelsAutoOff() {
        var g = NoteGuard(timeout: 10)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        g.record(.noteOff(channel: 0, note: 60), now: 1)
        XCTAssertEqual(g.expire(now: 20), [])
        // Velocity 0 note-on also means note-off.
        g.record(.noteOn(channel: 2, note: 61, velocity: 100), now: 0)
        g.record(.noteOn(channel: 2, note: 61, velocity: 0), now: 1)
        XCTAssertEqual(g.expire(now: 20), [])
    }

    func testRetriggerRestartsTimer() {
        var g = NoteGuard(timeout: 10)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 8)
        XCTAssertEqual(g.expire(now: 12), [])
        XCTAssertEqual(g.expire(now: 18), [.noteOff(channel: 0, note: 60)])
    }

    func testZeroTimeoutDisablesAutoOff() {
        var g = NoteGuard(timeout: 0)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        XCTAssertEqual(g.expire(now: 1000), [])
        XCTAssertEqual(g.releaseAll(), [.noteOff(channel: 0, note: 60)])
        XCTAssertEqual(g.releaseAll(), [])
    }
}
