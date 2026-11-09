/// A MIDI message TwinKeys can produce. Channels are 0-based (0 = MIDI channel 1).
public enum MIDIMessage: Equatable, Hashable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)

    /// MIDI 1.0 bytes (status, data1, data2).
    public var bytes: [UInt8] {
        switch self {
        case let .noteOn(ch, note, vel): return [0x90 | (ch & 0x0F), note & 0x7F, vel & 0x7F]
        case let .noteOff(ch, note): return [0x80 | (ch & 0x0F), note & 0x7F, 0]
        }
    }

    /// "All Notes Off" (CC 123) for every channel, as raw MIDI 1.0 bytes.
    public static var allNotesOffBytes: [[UInt8]] {
        (0..<16).map { [0xB0 | UInt8($0), 123, 0] }
    }
}

/// Note name in the convention where MIDI note 60 is "C3".
public func noteName(_ note: UInt8) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let octave = Int(note) / 12 - 2
    return "\(names[Int(note) % 12])\(octave)"
}
