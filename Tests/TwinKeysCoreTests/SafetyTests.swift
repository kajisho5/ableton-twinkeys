import XCTest
@testable import TwinKeysCore

final class SafetyTests: XCTestCase {
    func testAllNotesOffDestinations() {
        for t in [SafetyTrigger.panicButton, .appWillQuit, .manualDisconnect] {
            XCTAssertEqual(Safety.plan(for: t, connected: true), SafetyPlan(local: .all, remote: true), "\(t)")
            XCTAssertEqual(Safety.plan(for: t, connected: false), SafetyPlan(local: .all, remote: false), "\(t)")
        }
        for t in [SafetyTrigger.sendingTurnedOff, .keyCaptureTurnedOff] {
            XCTAssertEqual(Safety.plan(for: t, connected: true), SafetyPlan(local: .notesFromKeys, remote: true), "\(t)")
        }
        for t in [SafetyTrigger.connectionLost, .peerSaidBye] {
            // Never cut the main Mac's own playing because the network dropped.
            XCTAssertEqual(Safety.plan(for: t, connected: true), SafetyPlan(local: .notesFromPeer, remote: false), "\(t)")
        }
        // Every trigger turns off at least something on this Mac.
        for t in SafetyTrigger.allCases { XCTAssertNotEqual(Safety.plan(for: t, connected: true).local, .none) }
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

    func testKeepAndTouch() {
        var g = NoteGuard(timeout: 10)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        g.record(.noteOn(channel: 0, note: 62, velocity: 100), now: 0)
        XCTAssertEqual(g.expire(now: 11, keep: [NoteGuard.Key(channel: 0, note: 60)]), [.noteOff(channel: 0, note: 62)])
        g.touch(channel: 0, note: 60, now: 11)
        XCTAssertEqual(g.expire(now: 20), [])
        XCTAssertEqual(g.expire(now: 21), [.noteOff(channel: 0, note: 60)])
        g.touch(channel: 0, note: 99, now: 0)   // unknown note: ignored
        XCTAssertTrue(g.active.isEmpty)
    }

    func testZeroTimeoutDisablesAutoOff() {
        var g = NoteGuard(timeout: 0)
        g.record(.noteOn(channel: 0, note: 60, velocity: 100), now: 0)
        XCTAssertEqual(g.expire(now: 1000), [])
        XCTAssertEqual(g.releaseAll(), [.noteOff(channel: 0, note: 60)])
        XCTAssertEqual(g.releaseAll(), [])
    }
}
