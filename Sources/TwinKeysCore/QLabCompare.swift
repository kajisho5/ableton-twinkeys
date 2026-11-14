import Foundation

/// Comparing the cue lists of the two Macs' QLabs (docs/design-qlab.md Q10), the same way as the
/// Live set check (SetCheck.swift): each Mac sends a summary (count and hash) with every heartbeat
/// (packet qlabState) and, while the hashes differ, its cues a few at a time (packet qlabItem).
/// Only warns; nothing is changed in QLab.
public struct QLabCueSummary: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var number: String
        public var type: QLabCueType
        public var name: String
        public init(number: String, type: QLabCueType, name: String) { self.number = number; self.type = type; self.name = name }
    }
    public var items: [Item]

    /// Names and numbers are cut like the packet cuts them, so long names still compare equal.
    public static let maxNameBytes = 64

    public init(_ cues: [QLabCue]) {
        items = cues.map {
            Item(number: Self.cut($0.number, QLabCommand.maxNumberBytes), type: $0.type, name: Self.cut($0.name, Self.maxNameBytes))
        }
    }

    static func cut(_ s: String, _ max: Int) -> String { String(decoding: Array(truncatedUTF8(s, max: max)), as: UTF8.self) }

    /// FNV-1a over the count and every cue (number, type, name).
    public var hash: UInt32 {
        var h: UInt32 = 2_166_136_261
        func add(_ bytes: some Sequence<UInt8>) { for b in bytes { h = (h ^ UInt32(b)) &* 16_777_619 } }
        add(withUnsafeBytes(of: UInt32(items.count).bigEndian, Array.init))
        for i in items { add(i.number.utf8); add([0x1F, i.type.rawValue, 0x1F]); add(i.name.utf8); add([0x1E]) }
        return h
    }
}

/// The other Mac's cue list as far as its items have arrived.
public struct QLabPeerCues: Equatable, Sendable {
    public var count = 0
    public var hash: UInt32 = 0
    public var items: [Int: QLabCueSummary.Item] = [:]
    public init() {}

    public mutating func summary(count: Int, hash: UInt32) {
        if hash != self.hash || count != self.count { items = items.filter { $0.key < count } }
        self.count = count; self.hash = hash
    }

    public mutating func item(index: Int, _ item: QLabCueSummary.Item) {
        if index < count { items[index] = item }
    }

    public var isComplete: Bool { items.count >= count }
}

/// How this Mac's cue list differs from the other Mac's.
public struct QLabCueDiff: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public var index: Int
        public var main: String?
        public var backup: String?
        public init(index: Int, main: String?, backup: String?) { self.index = index; self.main = main; self.backup = backup }
    }
    public var mainCount: Int
    public var backupCount: Int
    public var differences: Int
    public var rows: [Row]
    public var complete: Bool
    public static let maxRows = 30

    public init(mainCount: Int, backupCount: Int, differences: Int, rows: [Row], complete: Bool) {
        self.mainCount = mainCount; self.backupCount = backupCount; self.differences = differences; self.rows = rows; self.complete = complete
    }

    static func text(_ i: QLabCueSummary.Item) -> String { "\(i.number) \(i.type.short) \(i.name)" }

    /// nil when both lists are the same (or the other Mac has not told its list yet).
    public static func compare(mine: QLabCueSummary, peer: QLabPeerCues?) -> QLabCueDiff? {
        guard let peer, peer.count > 0 || peer.hash != 0 else { return nil }
        if peer.hash == mine.hash, peer.count == mine.items.count { return nil }
        var rows: [Row] = [], differences = 0
        for i in 0..<max(mine.items.count, peer.count) {
            let a = i < mine.items.count ? mine.items[i] : nil
            let b = i < peer.count ? peer.items[i] : nil
            if i < peer.count, b == nil { continue }         // not arrived yet
            if a != b {
                differences += 1
                if rows.count < maxRows { rows.append(Row(index: i, main: a.map(text), backup: b.map(text))) }
            }
        }
        return QLabCueDiff(mainCount: mine.items.count, backupCount: peer.count, differences: differences, rows: rows,
                           complete: peer.isComplete)
    }
}

/// A Mac's QLab in short for the other Mac (packet qlabState, design 6.2):
///
///     0  state        QLabConnState
///     1  permissions  QLabPermissions
///     2  flags        bit 0 Show Mode, bit 1 "follow my playhead" (from the main Mac), bits 2–3 target
///     3  running      cues running (at most 255)
///     4  cues  u16    cues in the shown list
///     6  hash  u32    QLabCueSummary.hash of that list
///    10  keys  u32    hash of what TwinKeys drives and the cue keys' QLab actions
///    14  playhead     length byte + cue number (at most 24 bytes; empty: none)
public struct QLabLinkState: Equatable, Sendable {
    public var state: QLabConnState
    public var permissions: QLabPermissions
    public var showMode: Bool
    public var follow: Bool
    public var target: QLabTarget
    public var running: Int
    public var cueCount: Int
    public var listHash: UInt32
    public var keysHash: UInt32
    public var playhead: String?

    public init(state: QLabConnState, permissions: QLabPermissions = [], showMode: Bool = false, follow: Bool = false,
                target: QLabTarget = .qlab, running: Int = 0, cueCount: Int = 0, listHash: UInt32 = 0, keysHash: UInt32 = 0,
                playhead: String? = nil) {
        self.state = state; self.permissions = permissions; self.showMode = showMode; self.follow = follow; self.target = target
        self.running = running; self.cueCount = cueCount; self.listHash = listHash; self.keysHash = keysHash; self.playhead = playhead
    }

    func encoded() -> [UInt8] {
        var b: [UInt8] = [state.rawValue, permissions.rawValue,
                          (showMode ? 1 : 0) | (follow ? 2 : 0) | (target.code << 2),
                          UInt8(clamping: running)]
        let n = UInt16(clamping: cueCount)
        b += [UInt8(n >> 8), UInt8(n & 0xFF)]
        b.appendBE(listHash); b.appendBE(keysHash)
        b.appendShort(playhead ?? "", max: QLabCommand.maxNumberBytes)
        return b
    }

    static func decode(_ p: [UInt8]) -> QLabLinkState? {
        guard p.count >= 15 else { return nil }
        var i = 14
        guard let ph = p.readShort(&i, max: QLabCommand.maxNumberBytes) else { return nil }
        // A state this version does not know (a newer Mac) shows as "connecting".
        return QLabLinkState(state: QLabConnState(rawValue: p[0]) ?? .connecting, permissions: QLabPermissions(rawValue: p[1]),
                             showMode: p[2] & 1 != 0, follow: p[2] & 2 != 0, target: QLabTarget(code: (p[2] >> 2) & 3),
                             running: Int(p[3]), cueCount: Int(UInt16(p[4]) << 8 | UInt16(p[5])),
                             listHash: p.readBE32(at: 6), keysHash: p.readBE32(at: 10), playhead: ph.isEmpty ? nil : ph)
    }

    /// Hash of the target and the cue keys' QLab actions (yellow when the Macs differ).
    public static func keysHash(target: QLabTarget, keys: [CueKey]) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        func add(_ bytes: some Sequence<UInt8>) { for b in bytes { h = (h ^ UInt32(b)) &* 16_777_619 } }
        add([target.code])
        for k in keys.sorted(by: { $0.keycode < $1.keycode }) {
            add(withUnsafeBytes(of: k.keycode.bigEndian, Array.init))
            add([k.qlab?.action?.rawValue ?? 0]); add((k.qlab?.cue ?? "").utf8); add([0x1E])
        }
        return h
    }
}
