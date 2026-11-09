/// Tracks notes that were sent to a MIDI output so they can be turned off
/// automatically if their note-off never arrives, and on All Notes Off.
public struct NoteGuard: Sendable {
    public struct Key: Hashable, Sendable { public var channel: UInt8; public var note: UInt8 }
    /// Seconds after note-on before an automatic note-off. 0 or less disables it.
    public var timeout: Double
    public private(set) var active: [Key: Double] = [:]

    public init(timeout: Double) { self.timeout = timeout }

    /// Record a message that is being sent. `now` is in seconds (any monotonic clock).
    public mutating func record(_ m: MIDIMessage, now: Double) {
        switch m {
        case let .noteOn(ch, note, vel):
            if vel == 0 { active.removeValue(forKey: Key(channel: ch, note: note)) }
            else { active[Key(channel: ch, note: note)] = now }
        case let .noteOff(ch, note):
            active.removeValue(forKey: Key(channel: ch, note: note))
        }
    }

    /// Restarts the timer of a note that is known to be still held on purpose.
    public mutating func touch(channel: UInt8, note: UInt8, now: Double) {
        let k = Key(channel: channel, note: note)
        if active[k] != nil { active[k] = now }
    }

    /// Note-offs for notes held longer than `timeout`. They are removed from tracking.
    /// Notes in `keep` (for example keys still physically down) are left alone.
    public mutating func expire(now: Double, keep: Set<Key> = []) -> [MIDIMessage] {
        guard timeout > 0 else { return [] }
        let old = active.filter { now - $0.value >= timeout && !keep.contains($0.key) }.keys.sorted { ($0.channel, $0.note) < ($1.channel, $1.note) }
        for k in old { active.removeValue(forKey: k) }
        return old.map { .noteOff(channel: $0.channel, note: $0.note) }
    }

    /// Note-offs for everything still sounding; clears tracking.
    public mutating func releaseAll() -> [MIDIMessage] {
        let all = active.keys.sorted { ($0.channel, $0.note) < ($1.channel, $1.note) }
        active.removeAll()
        return all.map { .noteOff(channel: $0.channel, note: $0.note) }
    }
}
