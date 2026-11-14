import Foundation

// 2.3 Apple Watch <-> iPhone over WatchConnectivity. This file is compiled into both apps
// (TwinKeysRemote and TwinKeysRemoteWatch), so it uses Foundation only.
// The watch never talks to the Macs: it shows `WatchState` and sends `WatchCommand`s, which the
// iPhone runs through RemoteModel (so the show lock works exactly as on the iPhone).

/// What the watch shows. Made by the iPhone (WatchLink.swift) whenever it changes, at most about twice a second.
struct WatchState: Codable, Equatable, Sendable {
    /// Scene names in Live's order (the position is the scene index; the watch shows index + 1).
    var names: [String] = []
    /// Index of the playing scene, if any.
    var playing: Int?
    /// Live's selected scene: the one GO plays next (out of range: none).
    var selected = 0
    /// Seconds left of the playing scene when this was made (`stamp`).
    var left: Double?
    /// Live's transport runs: the watch counts `left` down by itself.
    var running = false
    /// The iPhone is connected to the main Mac.
    var connected = false
    /// The main Mac's Live answers.
    var mainOK = false
    /// The backup Mac is linked and its Live answers.
    var backupOK = false
    /// Memo (or key name) of the last cue, and whether it reached the backup (nil: not known yet).
    var lastCue: String?
    var lastCueOK: Bool?
    /// The iPhone's show lock is on.
    var locked = false
    /// The iPhone's last command problem ("no_answer", "structure_changed", ...), while the iPhone shows it.
    var problem: String?
    /// When the iPhone made this (seconds since 1970).
    var stamp: Double = 0

    // QLab mode (docs/design-qlab.md 6.4): the iPhone and the watch ship together, so no older watch
    // has to read these. "live", "qlab" or "both".
    var target = "live"
    /// "12 雨の音（遠く）": the newest running cue.
    var qlabNow: String?
    /// "13 雷鳴 1": the cue standing by, and its number (GO checks it).
    var qlabNext: String?
    var qlabNextNumber: String?
    /// Seconds left of the running cue when this was made, and its length (the ring).
    var qlabLeft: Double?
    var qlabTotal: Double?
    /// Both QLabs can GO.
    var qlabOK = false
    /// A few cues around the playhead for the list page.
    var qlabCues: [WatchQLabCue] = []

    var qlab: Bool { target != "live" }

    /// Same, apart from the clock: the time left only counts when it moved off the countdown by over 1.5 s
    /// (so a running clip does not send a new state every second).
    func sameAs(_ newer: WatchState) -> Bool {
        var a = self, b = newer
        a.left = nil; b.left = nil; a.stamp = 0; b.stamp = 0
        a.qlabLeft = nil; b.qlabLeft = nil
        guard a == b else { return false }
        switch (qlabLeft, newer.qlabLeft) {
        case (nil, nil): break
        case let (l?, r?): if abs(max(0, l - (newer.stamp - stamp)) - r) >= 1.5 { return false }
        default: return false
        }
        switch (left, newer.left) {
        case (nil, nil): return true
        case let (l?, r?):
            let expected = running ? max(0, l - (newer.stamp - stamp)) : l
            return abs(expected - r) < 1.5
        default: return false
        }
    }

    /// "-0:26" style (as `formatTimeLeft` in TwinKeysCore, which the watch app does not link).
    static func formatLeft(_ seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded(.up))
        return String(format: "-%d:%02d", s / 60, s % 60)
    }
}

/// One row of the watch's QLab list.
struct WatchQLabCue: Codable, Equatable, Sendable {
    var number: String
    var name: String
    var running = false
    var next = false
}

/// What the watch asks the iPhone to do. Sent with `sendMessage` only (never queued for later: a late GO is worse than none).
enum WatchCommand: Codable, Equatable, Sendable {
    /// GO: play `scene` (the scene the watch showed as next), then the next scene becomes "next".
    case go(scene: Int)
    /// Choose the next scene (does not play).
    case select(scene: Int)
    case allNotesOff
    /// Send the current state back (the watch app opened, or the iPhone became reachable).
    case refresh
    /// QLab mode: GO the cue the watch showed as next (`expect`: its number).
    case qlabGo(expect: String?)
    /// QLab mode: Panic on both Macs (again during the fade: stop at once).
    case qlabPanic
    /// QLab mode: move the playhead to that cue on both Macs (no GO).
    case qlabPlayhead(number: String)
}

/// Dictionary keys and helpers shared by both sides.
enum WatchWire {
    static let stateKey = "state"
    static let commandKey = "cmd"
    static let okKey = "ok"
    static let errorKey = "err"
    /// A second GO within this time is ignored (as on the iPhone's GO screen).
    static let goGuard: TimeInterval = 0.5

    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
