/// Modifier keys held at the time of a key event.
public struct Modifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

/// One raw key event from the global key monitor.
public struct KeyInput: Sendable {
    public var keycode: UInt16
    public var isDown: Bool
    public var isRepeat: Bool
    public var modifiers: Modifiers
    public init(keycode: UInt16, isDown: Bool, isRepeat: Bool = false, modifiers: Modifiers = []) {
        self.keycode = keycode; self.isDown = isDown; self.isRepeat = isRepeat; self.modifiers = modifiers
    }
}

/// Turns physical key presses into note on/off messages.
/// Not thread-safe: call from one thread (or behind a lock).
public struct PerformanceEngine: Sendable {
    public private(set) var mapping: KeyMapping
    public private(set) var octave: Int
    public private(set) var velocity: Int
    public var channel: UInt8 = 0
    /// keycode -> note that is currently sounding for that key.
    public private(set) var held: [UInt16: UInt8] = [:]
    /// Control keys currently down (to ignore their auto-repeat / double press).
    private var heldControls: Set<UInt16> = []

    public init(mapping: KeyMapping = .default) {
        self.mapping = mapping
        self.octave = mapping.baseOctave
        self.velocity = mapping.defaultVelocity
    }

    public var heldNotes: [UInt8] { held.values.sorted() }

    /// Replaces the mapping. Returns note-offs for anything still held.
    public mutating func setMapping(_ m: KeyMapping) -> [MIDIMessage] {
        let offs = releaseAll()
        mapping = m
        octave = min(max(octave, m.minOctave), m.maxOctave)
        return offs
    }

    /// Handles one key event and returns the MIDI messages to send.
    public mutating func handle(_ input: KeyInput) -> [MIDIMessage] {
        if input.isDown {
            // Key repeat is never a new physical press.
            if input.isRepeat { return [] }
            // Keys pressed together with a modifier are shortcuts, not notes.
            if !input.modifiers.isEmpty { return [] }
            if held[input.keycode] != nil || heldControls.contains(input.keycode) { return [] }

            if let semi = mapping.semitone(for: input.keycode) {
                let n = 12 * (octave + 2) + semi
                guard (0...127).contains(n) else { return [] }
                let note = UInt8(n)
                // Same note already sounding from another key is not possible with
                // unique semitones, but guard anyway.
                held[input.keycode] = note
                return [.noteOn(channel: channel, note: note, velocity: UInt8(velocity))]
            }
            switch input.keycode {
            case mapping.octaveDown: heldControls.insert(input.keycode); octave = max(mapping.minOctave, octave - 1)
            case mapping.octaveUp: heldControls.insert(input.keycode); octave = min(mapping.maxOctave, octave + 1)
            case mapping.velocityDown: heldControls.insert(input.keycode); velocity = max(1, velocity - mapping.velocityStep)
            case mapping.velocityUp: heldControls.insert(input.keycode); velocity = min(127, velocity + mapping.velocityStep)
            default: break
            }
            return []
        } else {
            heldControls.remove(input.keycode)
            // A release always ends the note, even if a modifier is down now.
            if let note = held.removeValue(forKey: input.keycode) {
                return [.noteOff(channel: channel, note: note)]
            }
            return []
        }
    }

    /// Releases every held note (used when capture is turned off, on panic, etc.).
    public mutating func releaseAll() -> [MIDIMessage] {
        let offs = held.values.sorted().map { MIDIMessage.noteOff(channel: channel, note: $0) }
        held.removeAll()
        heldControls.removeAll()
        return offs
    }
}
