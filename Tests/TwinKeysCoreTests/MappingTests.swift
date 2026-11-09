import XCTest
@testable import TwinKeysCore

final class MappingTests: XCTestCase {
    func down(_ k: UInt16, repeat r: Bool = false, mods: Modifiers = []) -> KeyInput { KeyInput(keycode: k, isDown: true, isRepeat: r, modifiers: mods) }
    func up(_ k: UInt16, mods: Modifiers = []) -> KeyInput { KeyInput(keycode: k, isDown: false, modifiers: mods) }

    func testDefaultLayoutMatchesComputerKeyboard() {
        var e = PerformanceEngine()
        // A = C3 (60), W = C#3, ; = E4
        XCTAssertEqual(e.handle(down(0x00)), [.noteOn(channel: 0, note: 60, velocity: 100)])
        XCTAssertEqual(e.handle(down(0x0D)), [.noteOn(channel: 0, note: 61, velocity: 100)])
        XCTAssertEqual(e.handle(down(0x29)), [.noteOn(channel: 0, note: 76, velocity: 100)])
        XCTAssertEqual(noteName(60), "C3")
    }

    func testMappingUsesKeyCodesNotCharacters() throws {
        // A JIS keyboard sends the same key code (0x00) for the key in the "A" position.
        // The mapping never looks at characters, so the layout does not matter.
        let codes = KeyMapping.default.notes.map(\.keycode)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertNoThrow(try KeyMapping.default.validate())
    }

    func testKeyRepeatIsIgnored() {
        var e = PerformanceEngine()
        XCTAssertEqual(e.handle(down(0x00)).count, 1)
        XCTAssertEqual(e.handle(down(0x00, repeat: true)), [])
        // A second key-down without key-up (can happen) is not a new press either.
        XCTAssertEqual(e.handle(down(0x00)), [])
        XCTAssertEqual(e.handle(up(0x00)), [.noteOff(channel: 0, note: 60)])
        XCTAssertEqual(e.handle(up(0x00)), [])
    }

    func testChord() {
        var e = PerformanceEngine()
        _ = e.handle(down(0x00)); _ = e.handle(down(0x02)); _ = e.handle(down(0x05))
        XCTAssertEqual(e.heldNotes, [60, 64, 67])
        XCTAssertEqual(e.handle(up(0x02)), [.noteOff(channel: 0, note: 64)])
        XCTAssertEqual(e.heldNotes, [60, 67])
    }

    func testModifierPressesAreIgnoredButReleasesStillEndNotes() {
        var e = PerformanceEngine()
        XCTAssertEqual(e.handle(down(0x00, mods: .command)), [])
        XCTAssertEqual(e.handle(down(0x01, mods: .shift)), [])
        XCTAssertEqual(e.handle(down(0x02)).count, 1)
        // Shift pressed while D is held: the release must still turn the note off.
        XCTAssertEqual(e.handle(up(0x02, mods: .shift)), [.noteOff(channel: 0, note: 64)])
    }

    func testOctaveChangeKeepsHeldNoteOff() {
        var e = PerformanceEngine()
        _ = e.handle(down(0x00))              // C3 on
        _ = e.handle(down(0x07)); _ = e.handle(up(0x07))   // octave up
        XCTAssertEqual(e.octave, 4)
        // The note that was started before the change ends with the same number.
        XCTAssertEqual(e.handle(up(0x00)), [.noteOff(channel: 0, note: 60)])
        XCTAssertEqual(e.handle(down(0x00)), [.noteOn(channel: 0, note: 72, velocity: 100)])
    }

    func testOctaveAndVelocityLimits() {
        var e = PerformanceEngine()
        for _ in 0..<20 { _ = e.handle(down(0x06)); _ = e.handle(up(0x06)) }
        XCTAssertEqual(e.octave, -2)
        XCTAssertEqual(e.handle(down(0x00)), [.noteOn(channel: 0, note: 0, velocity: 100)])
        _ = e.handle(up(0x00))
        for _ in 0..<20 { _ = e.handle(down(0x07)); _ = e.handle(up(0x07)) }
        XCTAssertEqual(e.octave, 8)
        // C8 = 120, E9 would be 136: out of MIDI range, so nothing is sent.
        XCTAssertEqual(e.handle(down(0x00)), [.noteOn(channel: 0, note: 120, velocity: 100)])
        XCTAssertEqual(e.handle(down(0x29)), [])
        for _ in 0..<10 { _ = e.handle(down(0x09)); _ = e.handle(up(0x09)) }
        XCTAssertEqual(e.velocity, 127)
        for _ in 0..<10 { _ = e.handle(down(0x08)); _ = e.handle(up(0x08)) }
        XCTAssertEqual(e.velocity, 20)   // lowest step on the 100/80/60/40/20 grid
    }

    func testVelocityStaysOnGridAndReturnsToDefault() {
        var e = PerformanceEngine()
        func press(_ k: UInt16) -> Int { _ = e.handle(down(k)); _ = e.handle(up(k)); return e.velocity }
        XCTAssertEqual([press(0x09), press(0x09), press(0x09)], [120, 127, 127])
        XCTAssertEqual([press(0x08), press(0x08), press(0x08)], [120, 100, 80])
        for _ in 0..<10 { _ = press(0x08) }
        XCTAssertEqual([press(0x09), press(0x09), press(0x09), press(0x09)], [40, 60, 80, 100])
    }

    func testSameNoteFromTwoKeysDoesNotCutTheOther() {
        var e = PerformanceEngine()
        XCTAssertEqual(e.handle(down(0x28)), [.noteOn(channel: 0, note: 72, velocity: 100)])  // K = C4
        _ = e.handle(down(0x07)); _ = e.handle(up(0x07))                                     // octave up
        XCTAssertEqual(e.handle(down(0x00)), [])                                             // A = C4 too
        XCTAssertEqual(e.handle(up(0x00)), [])
        XCTAssertEqual(e.heldNotes, [72])
        XCTAssertEqual(e.handle(up(0x28)), [.noteOff(channel: 0, note: 72)])
    }

    func testReloadedMappingAppliesBaseOctaveAndVelocity() {
        var e = PerformanceEngine()
        _ = e.handle(down(0x07)); _ = e.handle(up(0x07))
        var m = KeyMapping.default
        m.baseOctave = 2; m.defaultVelocity = 90
        _ = e.setMapping(m)
        XCTAssertEqual(e.octave, 2); XCTAssertEqual(e.velocity, 90)
    }

    func testControlKeyRepeatDoesNotKeepChangingOctave() {
        var e = PerformanceEngine()
        _ = e.handle(down(0x07)); _ = e.handle(down(0x07, repeat: true)); _ = e.handle(down(0x07))
        XCTAssertEqual(e.octave, 4)
    }

    func testReleaseAll() {
        var e = PerformanceEngine()
        _ = e.handle(down(0x00)); _ = e.handle(down(0x01))
        XCTAssertEqual(e.releaseAll(), [.noteOff(channel: 0, note: 60), .noteOff(channel: 0, note: 62)])
        XCTAssertEqual(e.heldNotes, [])
        XCTAssertEqual(e.handle(up(0x00)), [])
    }

    func testJSONRoundTripAndValidation() throws {
        let data = try KeyMapping.default.encoded()
        XCTAssertEqual(try KeyMapping.decode(data), KeyMapping.default)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"octave_down\""))

        var bad = KeyMapping.default
        bad.octaveUp = 0x00   // same key as a note
        XCTAssertThrowsError(try KeyMapping.decode(try bad.encoded()))
    }

    func testMIDIBytes() {
        XCTAssertEqual(MIDIMessage.noteOn(channel: 1, note: 60, velocity: 100).bytes, [0x91, 60, 100])
        XCTAssertEqual(MIDIMessage.noteOff(channel: 0, note: 60).bytes, [0x80, 60, 0])
        XCTAssertEqual(MIDIMessage.allNotesOffBytes.count, 16)
        XCTAssertEqual(MIDIMessage.allNotesOffBytes[15], [0xBF, 123, 0])
    }
}

final class ShippedFilesTests: XCTestCase {
    func testShippedDefaultMappingMatchesBuiltIn() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/mapping.default.json"))
        XCTAssertEqual(try KeyMapping.decode(data), KeyMapping.default)
    }
}
