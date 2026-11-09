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
        // A reloaded mapping takes effect as written (base octave and default velocity too).
        octave = m.baseOctave
        velocity = m.defaultVelocity
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
                // After an octave change two keys can map to the same note. While one key
                // holds it, the other key does nothing (otherwise releasing one would cut the other).
                if held.values.contains(note) { return [] }
                held[input.keycode] = note
                return [.noteOn(channel: channel, note: note, velocity: UInt8(velocity))]
            }
            switch input.keycode {
            case mapping.octaveDown: heldControls.insert(input.keycode); octave = max(mapping.minOctave, octave - 1)
            case mapping.octaveUp: heldControls.insert(input.keycode); octave = min(mapping.maxOctave, octave + 1)
            case mapping.velocityDown: heldControls.insert(input.keycode); velocity = velocityStepped(down: true)
            case mapping.velocityUp: heldControls.insert(input.keycode); velocity = velocityStepped(down: false)
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

    /// Velocity moves on a grid through the default (100, 80, 60 … with step 20), so it can
    /// always come back to the default. The top is 127.
    private func velocityStepped(down: Bool) -> Int {
        let step = mapping.velocityStep, base = mapping.defaultVelocity
        let lowest = ((base - 1) % step) + 1
        let offset = (velocity - base) % step
        if down {
            let onGrid = offset == 0 ? velocity - step : velocity - ((offset + step) % step)
            return max(lowest, onGrid)
        }
        return min(127, velocity + step - ((offset + step) % step))
    }

    /// Releases every held note (used when capture is turned off, on panic, etc.).
    public mutating func releaseAll() -> [MIDIMessage] {
        let offs = held.values.sorted().map { MIDIMessage.noteOff(channel: channel, note: $0) }
        held.removeAll()
        heldControls.removeAll()
        return offs
    }
}
