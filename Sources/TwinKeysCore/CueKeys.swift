import Foundation

/// A key that fires one fixed MIDI note (a "cue"), whatever the octave or velocity.
/// Used for show playback: arrows to move between scenes, Space to play, and so on.
public struct CueKey: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// macOS virtual key code (position of the key).
    public var keycode: UInt16
    /// Short name of the key as shown on screen ("↓", "Space").
    public var label: String
    /// The person's own name for the cue ("Next scene"). May be empty.
    public var memo: String
    /// MIDI note number (0-127). Stays the same when other cue keys are added or removed,
    /// so mappings made in the DAW keep working.
    public var note: UInt8

    public var id: UInt16 { keycode }

    public init(keycode: UInt16, label: String? = nil, memo: String = "", note: UInt8) {
        self.keycode = keycode
        self.label = label ?? KeyNames.label(for: keycode)
        self.memo = memo
        self.note = note
    }

    /// Cue notes are given out from C1 (36) upwards.
    public static let firstNote: UInt8 = 36
    /// Every cue is sent at full velocity.
    public static let velocity: UInt8 = 127
    /// Most bytes of a memo sent to the other Mac (fits in one packet).
    public static let maxMemoBytes = 60
    public static let maxLabelBytes = 12

    /// ↑ ↓ ← → Space Return Esc, as suggested for a new install.
    public static let defaults: [CueKey] = [
        CueKey(keycode: KeyNames.up, note: 36),
        CueKey(keycode: KeyNames.down, note: 37),
        CueKey(keycode: KeyNames.left, note: 38),
        CueKey(keycode: KeyNames.right, note: 39),
        CueKey(keycode: KeyNames.space, note: 40),
        CueKey(keycode: KeyNames.returnKey, note: 41),
        CueKey(keycode: KeyNames.escape, note: 42),
    ]

    /// Letters A–Z and digits 0–9 (by key position), for adding them in one go.
    public static let alphanumericKeyCodes: [UInt16] = [
        0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
        0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06,
        0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19,
    ]

    /// Adds keys that are not cue keys yet, each with the next free note. Stops when notes run out.
    public static func adding(_ codes: [UInt16], to keys: [CueKey]) -> [CueKey] {
        var out = keys
        for code in codes where !KeyNames.isModifier(code) && !out.contains(where: { $0.keycode == code }) {
            guard let n = freeNote(in: out) else { break }
            out.append(CueKey(keycode: code, note: n))
        }
        return out
    }

    /// The lowest note from `firstNote` that no key in `keys` uses (nil when all are taken).
    public static func freeNote(in keys: [CueKey]) -> UInt8? {
        let used = Set(keys.map(\.note))
        return (Int(firstNote)...127).map { UInt8($0) }.first { !used.contains($0) }
    }

    /// Keeps only usable entries: no duplicate key or note, note in range, texts trimmed.
    public static func sanitized(_ keys: [CueKey]) -> [CueKey] {
        var seenKeys = Set<UInt16>(), seenNotes = Set<UInt8>(), out: [CueKey] = []
        for var k in keys where k.note < 128 && !seenKeys.contains(k.keycode) && !seenNotes.contains(k.note) {
            if KeyNames.isModifier(k.keycode) { continue }
            seenKeys.insert(k.keycode); seenNotes.insert(k.note)
            k.label = String(decoding: Array(truncatedUTF8(k.label, max: maxLabelBytes)), as: UTF8.self)
            if k.label.isEmpty { k.label = KeyNames.label(for: k.keycode) }
            k.memo = String(decoding: Array(truncatedUTF8(k.memo, max: maxMemoBytes)), as: UTF8.self)
            out.append(k)
        }
        return out
    }
}

/// Names of keys by macOS virtual key code (HIToolbox/Events.h kVK_* values).
public enum KeyNames {
    public static let up: UInt16 = 0x7E, down: UInt16 = 0x7D, left: UInt16 = 0x7B, right: UInt16 = 0x7C
    public static let space: UInt16 = 0x31, returnKey: UInt16 = 0x24, escape: UInt16 = 0x35
    public static let tab: UInt16 = 0x30, delete: UInt16 = 0x33, forwardDelete: UInt16 = 0x75
    public static let keypadEnter: UInt16 = 0x4C

    private static let table: [UInt16: String] = [
        0x7E: "↑", 0x7D: "↓", 0x7B: "←", 0x7C: "→",
        0x31: "Space", 0x24: "Return", 0x35: "Esc", 0x30: "Tab", 0x33: "Delete", 0x75: "Del ⌦",
        0x4C: "Enter", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8",
        0x19: "9", 0x1D: "0", 0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x2A: "\\", 0x29: ";",
        0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x32: "`",
        0x52: "Num 0", 0x53: "Num 1", 0x54: "Num 2", 0x55: "Num 3", 0x56: "Num 4", 0x57: "Num 5",
        0x58: "Num 6", 0x59: "Num 7", 0x5B: "Num 8", 0x5C: "Num 9", 0x41: "Num .", 0x45: "Num +",
        0x4E: "Num -", 0x43: "Num *", 0x4B: "Num /", 0x51: "Num =", 0x47: "Clear",
        0x5D: "¥", 0x5E: "_", 0x5F: "Num ,", 0x66: "英数", 0x68: "かな",
    ]

    /// Modifier keys (⌘ ⇧ ⌥ ⌃ fn, Caps Lock) cannot be cue keys.
    public static func isModifier(_ code: UInt16) -> Bool {
        [0x37, 0x36, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E, 0x39, 0x3F].contains(code)
    }

    public static func label(for code: UInt16) -> String {
        table[code] ?? "Key \(code)"
    }
}
