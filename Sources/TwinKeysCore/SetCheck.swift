import Foundation

/// 2.1: comparing the Live sets open on the two Macs (track and scene names only).
///
/// Each Mac sends a summary with every heartbeat (counts and a hash of all names) and its names a
/// few at a time. The other Mac compares the summary with its own set and, when they differ, lists
/// the rows that differ. Nothing is ever changed in Live: this only warns.
public struct SetSummary: Equatable, Sendable {
    public var tracks: [String]
    public var scenes: [String]

    /// Names are cut to this many UTF-8 bytes on both sides, so long names still compare equal.
    public static let maxNameBytes = 60

    public init(tracks: [String], scenes: [String]) {
        self.tracks = tracks.map(Self.cut)
        self.scenes = scenes.map(Self.cut)
    }

    public init(_ s: LiveState) {
        self.init(tracks: s.tracks.map(\.name), scenes: s.scenes.map(\.name))
    }

    static func cut(_ name: String) -> String {
        String(decoding: Array(truncatedUTF8(name, max: maxNameBytes)), as: UTF8.self)
    }

    /// FNV-1a over the counts and every name (tracks, then scenes).
    public var hash: UInt32 {
        var h: UInt32 = 2_166_136_261
        func add(_ bytes: some Sequence<UInt8>) { for b in bytes { h = (h ^ UInt32(b)) &* 16_777_619 } }
        add(withUnsafeBytes(of: UInt32(tracks.count).bigEndian, Array.init))
        add(withUnsafeBytes(of: UInt32(scenes.count).bigEndian, Array.init))
        for n in tracks { add(n.utf8); add([0x1F]) }
        add([0x1E])
        for n in scenes { add(n.utf8); add([0x1F]) }
        return h
    }
}

/// The other Mac's set as far as its names have arrived.
public struct PeerSet: Equatable, Sendable {
    public var trackCount = 0
    public var sceneCount = 0
    public var hash: UInt32 = 0
    public var tracks: [Int: String] = [:]
    public var scenes: [Int: String] = [:]
    public init() {}

    /// A summary arrived: forget names beyond the new counts (a set with fewer rows was opened).
    public mutating func summary(tracks: Int, scenes: Int, hash: UInt32) {
        if hash != self.hash || tracks != trackCount || scenes != sceneCount {
            self.tracks = self.tracks.filter { $0.key < tracks }
            self.scenes = self.scenes.filter { $0.key < scenes }
        }
        trackCount = tracks; sceneCount = scenes; self.hash = hash
    }

    public mutating func item(kind: SetItemKind, index: Int, name: String) {
        switch kind {
        case .track: if index < trackCount { tracks[index] = name }
        case .scene: if index < sceneCount { scenes[index] = name }
        }
    }

    /// All names up to the counts have arrived.
    public var isComplete: Bool { tracks.count >= trackCount && scenes.count >= sceneCount }
}

public enum SetItemKind: UInt8, Sendable { case track = 0, scene = 1 }

/// How this Mac's set differs from the other Mac's (shown on the Mac and on the iPhone).
public struct SetDiff: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public var kind: String        // "track" or "scene"
        public var index: Int
        public var main: String?       // nil: no such row on this Mac
        public var backup: String?     // nil: no such row on the other Mac (or not arrived yet)
        public init(kind: String, index: Int, main: String?, backup: String?) {
            self.kind = kind; self.index = index; self.main = main; self.backup = backup
        }
    }
    public var mainTracks: Int
    public var backupTracks: Int
    public var mainScenes: Int
    public var backupScenes: Int
    /// Number of rows that differ (all of them, even beyond `rows`).
    public var differences: Int
    /// The first rows that differ, for the detail list.
    public var rows: [Row]
    /// False while the other Mac's names are still arriving (the count may grow).
    public var complete: Bool

    public static let maxRows = 30

    public init(mainTracks: Int, backupTracks: Int, mainScenes: Int, backupScenes: Int,
                differences: Int, rows: [Row], complete: Bool) {
        self.mainTracks = mainTracks; self.backupTracks = backupTracks
        self.mainScenes = mainScenes; self.backupScenes = backupScenes
        self.differences = differences; self.rows = rows; self.complete = complete
    }

    /// nil when the two sets have the same names (or the other Mac has not told its set yet).
    public static func compare(mine: SetSummary, peer: PeerSet?) -> SetDiff? {
        guard let peer, peer.trackCount > 0 || peer.sceneCount > 0 || peer.hash != 0 else { return nil }
        if peer.hash == mine.hash, peer.trackCount == mine.tracks.count, peer.sceneCount == mine.scenes.count { return nil }
        var rows: [Row] = []
        var differences = 0
        func scan(_ kind: SetItemKind, _ local: [String], _ remote: [Int: String], _ remoteCount: Int) {
            for i in 0..<max(local.count, remoteCount) {
                let a = i < local.count ? local[i] : nil
                let b = i < remoteCount ? remote[i] : nil
                // A row whose name has not arrived yet is not counted as different.
                if i < remoteCount, b == nil { continue }
                if a != b {
                    differences += 1
                    if rows.count < maxRows { rows.append(Row(kind: kind == .track ? "track" : "scene", index: i, main: a, backup: b)) }
                }
            }
        }
        scan(.track, mine.tracks, peer.tracks, peer.trackCount)
        scan(.scene, mine.scenes, peer.scenes, peer.sceneCount)
        // Same counts and every name arrived and equal, but the hashes differ: the names arrived
        // from an older set. Report it as different without rows until the new names come.
        return SetDiff(mainTracks: mine.tracks.count, backupTracks: peer.trackCount,
                       mainScenes: mine.scenes.count, backupScenes: peer.sceneCount,
                       differences: differences, rows: rows, complete: peer.isComplete)
    }
}
