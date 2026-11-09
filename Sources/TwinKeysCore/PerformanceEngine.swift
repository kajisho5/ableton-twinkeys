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

/// Turns presses of cue keys into note on/off messages. Every cue key sends one fixed note
/// at full velocity on `channel`; there is no octave or velocity to change by mistake.
/// Not thread-safe: call from one thread (or behind a lock).
public struct PerformanceEngine: Sendable {
    /// MIDI channel (0-based) of every cue note.
    public var channel: UInt8 = 0
    /// Cue keys by key code.
    public private(set) var cueKeys: [UInt16: CueKey] = [:]
    /// keycode -> note currently sounding for that key.
    public private(set) var held: [UInt16: UInt8] = [:]

    public init(cueKeys: [CueKey] = CueKey.defaults, channel: UInt8 = 0) {
        self.channel = channel
        _ = setCueKeys(cueKeys)
    }

    public var heldNotes: [UInt8] { held.values.sorted() }

    /// Replaces the cue keys. Returns note-offs for keys still held.
    public mutating func setCueKeys(_ keys: [CueKey]) -> [MIDIMessage] {
        let offs = releaseAll()
        cueKeys = Dictionary(CueKey.sanitized(keys).map { ($0.keycode, $0) }, uniquingKeysWith: { a, _ in a })
        return offs
    }

    /// True if this key code is a cue key.
    public func isCueKey(_ keycode: UInt16) -> Bool { cueKeys[keycode] != nil }

    /// Handles one key event and returns the MIDI messages to send.
    public mutating func handle(_ input: KeyInput) -> [MIDIMessage] { handleEvents(input).map(\.message) }

    /// Like `handle`, with the cue key each message belongs to.
    public mutating func handleEvents(_ input: KeyInput) -> [(message: MIDIMessage, cue: CueKey?)] {
        if input.isDown {
            guard let cue = cueKeys[input.keycode] else { return [] }
            // Key repeat is never a new press; keys with ⌘ ⌃ ⌥ ⇧ are shortcuts, not cues.
            if input.isRepeat || !input.modifiers.isEmpty || held[input.keycode] != nil { return [] }
            held[input.keycode] = cue.note
            return [(.noteOn(channel: channel, note: cue.note, velocity: CueKey.velocity), cue)]
        }
        // A release always ends the note, even if the key was removed from the list meanwhile.
        if let note = held.removeValue(forKey: input.keycode) {
            return [(.noteOff(channel: channel, note: note), cueKeys[input.keycode])]
        }
        return []
    }

    /// Ends one sounding note as if its key had been released (key-up never seen).
    public mutating func release(note: UInt8) -> [MIDIMessage] {
        guard let key = held.first(where: { $0.value == note })?.key else { return [] }
        held.removeValue(forKey: key)
        return [.noteOff(channel: channel, note: note)]
    }

    /// Releases every held note (capture turned off, panic, etc.).
    public mutating func releaseAll() -> [MIDIMessage] {
        let offs = held.values.sorted().map { MIDIMessage.noteOff(channel: channel, note: $0) }
        held.removeAll()
        return offs
    }
}
