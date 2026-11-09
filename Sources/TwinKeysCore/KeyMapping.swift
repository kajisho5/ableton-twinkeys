import Foundation

/// Mapping from physical key positions (macOS virtual key codes) to notes.
/// Key codes describe the position of a key, not its printed character,
/// so the same key position plays the same note on JIS and US keyboards.
public struct KeyMapping: Codable, Equatable, Sendable {
    public struct NoteKey: Codable, Equatable, Sendable {
        public var keycode: UInt16
        public var label: String
        public var semitone: Int
        public init(keycode: UInt16, label: String, semitone: Int) {
            self.keycode = keycode; self.label = label; self.semitone = semitone
        }
    }

    public var version: Int
    public var baseOctave: Int
    public var minOctave: Int
    public var maxOctave: Int
    public var notes: [NoteKey]
    public var octaveDown: UInt16
    public var octaveUp: UInt16
    public var velocityDown: UInt16
    public var velocityUp: UInt16
    public var velocityStep: Int
    public var defaultVelocity: Int

    enum CodingKeys: String, CodingKey {
        case version, notes
        case baseOctave = "base_octave", minOctave = "min_octave", maxOctave = "max_octave"
        case octaveDown = "octave_down", octaveUp = "octave_up"
        case velocityDown = "velocity_down", velocityUp = "velocity_up"
        case velocityStep = "velocity_step", defaultVelocity = "default_velocity"
    }

    /// Layout modelled on the common DAW "computer MIDI keyboard":
    /// home row = white keys, row above = black keys, Z/X = octave, C/V = velocity.
    /// Key codes are the macOS kVK_ANSI_* values (HIToolbox/Events.h).
    public static let `default` = KeyMapping(
        version: 1, baseOctave: 3, minOctave: -2, maxOctave: 8,
        notes: [
            NoteKey(keycode: 0x00, label: "A", semitone: 0),
            NoteKey(keycode: 0x0D, label: "W", semitone: 1),
            NoteKey(keycode: 0x01, label: "S", semitone: 2),
            NoteKey(keycode: 0x0E, label: "E", semitone: 3),
            NoteKey(keycode: 0x02, label: "D", semitone: 4),
            NoteKey(keycode: 0x03, label: "F", semitone: 5),
            NoteKey(keycode: 0x11, label: "T", semitone: 6),
            NoteKey(keycode: 0x05, label: "G", semitone: 7),
            NoteKey(keycode: 0x10, label: "Y", semitone: 8),
            NoteKey(keycode: 0x04, label: "H", semitone: 9),
            NoteKey(keycode: 0x20, label: "U", semitone: 10),
            NoteKey(keycode: 0x26, label: "J", semitone: 11),
            NoteKey(keycode: 0x28, label: "K", semitone: 12),
            NoteKey(keycode: 0x1F, label: "O", semitone: 13),
            NoteKey(keycode: 0x25, label: "L", semitone: 14),
            NoteKey(keycode: 0x23, label: "P", semitone: 15),
            NoteKey(keycode: 0x29, label: ";", semitone: 16),
        ],
        octaveDown: 0x06, octaveUp: 0x07, velocityDown: 0x08, velocityUp: 0x09,
        velocityStep: 20, defaultVelocity: 100
    )

    public func semitone(for keycode: UInt16) -> Int? {
        notes.first { $0.keycode == keycode }?.semitone
    }

    /// Checks values that would otherwise produce nonsense at runtime.
    public func validate() throws {
        guard minOctave <= baseOctave, baseOctave <= maxOctave else { throw MappingError.invalid("base_octave out of range") }
        guard (1...127).contains(defaultVelocity) else { throw MappingError.invalid("default_velocity must be 1-127") }
        guard velocityStep > 0 else { throw MappingError.invalid("velocity_step must be > 0") }
        let codes = notes.map(\.keycode) + [octaveDown, octaveUp, velocityDown, velocityUp]
        guard Set(codes).count == codes.count else { throw MappingError.invalid("a key code is used twice") }
    }

    public static func decode(_ data: Data) throws -> KeyMapping {
        let m = try JSONDecoder().decode(KeyMapping.self, from: data)
        try m.validate()
        return m
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}

public enum MappingError: Error, Equatable {
    case invalid(String)
}
