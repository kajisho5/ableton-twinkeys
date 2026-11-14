import Foundation

/// The cue standing by (QLab's playhead) as a Mac knows it.
public struct QLabCueRef: Equatable, Sendable, Codable {
    public var uniqueID: String
    public var number: String
    public init(uniqueID: String, number: String) { self.uniqueID = uniqueID; self.number = number }
}

/// What to send to this Mac's QLab for a command (docs/design-qlab.md 5.3). Pure decisions,
/// tested on Linux; QLabEngine sends the messages.
public enum QLabPlanner {
    public enum Plan: Equatable {
        /// Send these; if they all succeed the result is `code` (`.ok`, or `.corrected` when the
        /// backup had to move its playhead first).
        case send([OSCMessage], code: QLabResultCode)
        /// Send nothing.
        case refuse(QLabResultCode)
    }

    /// The main Mac's check before anything is sent (to its QLab or to the backup).
    public enum MainCheck: Equatable {
        case ok
        /// "iPhone で見ていた『次』と違うときは GO しない": QLab's next cue is not the one the
        /// iPhone (or the key) saw.
        case nextChanged(now: String?)
        /// A second identical GO within `QLabGoGuard.window`: merged with the first.
        case doublePress
    }

    /// `expect`: what the sender saw standing by (nil: no check). `playhead`: this Mac's playhead now.
    public static func mainCheck(_ cmd: QLabCommand, playhead: QLabCueRef?, refuseStale: Bool,
                                 guardState: inout QLabGoGuard, now: Double) -> MainCheck {
        // The double press first: the second tap of a double tap saw the same "next" as the first,
        // which QLab has already left; it is the same GO, not a stale one.
        if cmd.action.starts, guardState.blocks(cmd, now: now) { return .doublePress }
        if cmd.action == .go, refuseStale, let e = cmd.expect, e != playhead?.number {
            return .nextChanged(now: playhead?.number)
        }
        // Only a GO that is sent counts for the guard (a refused one may be pressed again at once).
        if cmd.action.starts { guardState.record(cmd, now: now) }
        return .ok
    }

    /// The messages for `cmd` on a Mac whose QLab has workspace `ws`, cues `cues` and playhead `playhead`.
    /// `asBackup`: a command forwarded by the main Mac (GO follows the main's number).
    public static func plan(_ cmd: QLabCommand, workspace ws: String, cues: [QLabCue], playhead: QLabCueRef?,
                            asBackup: Bool) -> Plan {
        guard cmd.isValid else { return .refuse(.noSuchCue) }
        func uid(_ number: String) -> String? { cues.first { $0.number == number }?.uniqueID }
        switch cmd.action {
        case .go:
            guard asBackup, let n = cmd.expect else { return .send([OSCMessage(QLabOSCAddress.go(ws))], code: .ok) }
            if playhead?.number == n { return .send([OSCMessage(QLabOSCAddress.go(ws))], code: .ok) }
            // Not standing by on the main's cue: GO that cue (never a different one; design 5.3-4).
            guard let id = uid(n) else { return .refuse(.noSuchCue) }
            return .send([OSCMessage(QLabOSCAddress.goCueID(ws, id))], code: .corrected)
        case .goCue:
            guard let n = cmd.cueNumber, let id = uid(n) else { return .refuse(.noSuchCue) }
            return .send([OSCMessage(QLabOSCAddress.goCueID(ws, id))], code: .ok)
        case .setPlayhead:
            guard let n = cmd.cueNumber, let id = uid(n) else { return .refuse(.noSuchCue) }
            return .send([OSCMessage(QLabOSCAddress.playheadID(ws, id))], code: .ok)
        case .playheadNext: return .send([OSCMessage(QLabOSCAddress.playheadNext(ws))], code: .ok)
        case .playheadPrevious: return .send([OSCMessage(QLabOSCAddress.playheadPrevious(ws))], code: .ok)
        case .panic: return .send([OSCMessage(QLabOSCAddress.panic(ws))], code: .ok)
        // `/stop` needs the edit permission in the dictionary's table (design 3.1): Stop uses hardStop.
        case .hardStop: return .send([OSCMessage(QLabOSCAddress.hardStop(ws))], code: .ok)
        case .pause: return .send([OSCMessage(QLabOSCAddress.pause(ws))], code: .ok)
        case .resume: return .send([OSCMessage(QLabOSCAddress.resume(ws))], code: .ok)
        }
    }

    /// Backup: the main Mac's playhead is `mainNumber`; move ours there (design 3.3-2). Nil: nothing
    /// to do (same cue, unknown, a GO a moment ago — auto-continue cues may still be moving — or no
    /// such cue here).
    public static func follow(mainNumber: String?, playhead: QLabCueRef?, cues: [QLabCue], workspace ws: String,
                              lastGoAt: Double, now: Double) -> OSCMessage? {
        guard let n = mainNumber, !n.isEmpty, n != playhead?.number else { return nil }
        guard now - lastGoAt >= followPause else { return nil }
        guard let id = cues.first(where: { $0.number == n })?.uniqueID, id != playhead?.uniqueID else { return nil }
        return OSCMessage(QLabOSCAddress.playheadID(ws, id))
    }

    /// No playhead following this soon after a GO (design 3.3-3).
    public static let followPause = 0.5
}

/// Two identical GOs within `window` count once (a double tap, or the same press from two paths).
/// Not QLab's own "double go protection".
public struct QLabGoGuard: Sendable {
    public static let window = 0.3
    private var last: (cmd: QLabCommand, at: Double)?
    public init() {}

    public func blocks(_ cmd: QLabCommand, now: Double) -> Bool {
        if let l = last, l.cmd == cmd, now - l.at < Self.window { return true }
        return false
    }

    public mutating func record(_ cmd: QLabCommand, now: Double) { last = (cmd, now) }

    /// `blocks`, then `record` when not blocked.
    public mutating func allow(_ cmd: QLabCommand, now: Double) -> Bool {
        if blocks(cmd, now: now) { return false }
        record(cmd, now: now)
        return true
    }
}

/// Ids of commands already run (a resend must never GO twice). Keeps the last 256.
public struct QLabSeenCommands: Sendable {
    private var order: [UInt64] = []
    private var results: [UInt64: QLabResultCode?] = [:]
    public init() {}

    public static func key(session: UInt32, id: UInt32) -> UInt64 { UInt64(session) << 32 | UInt64(id) }

    /// True the first time `key` is seen (then run it).
    public mutating func first(_ key: UInt64) -> Bool {
        guard results[key] == nil else { return false }
        results[key] = .some(nil)
        order.append(key)
        if order.count > 256 { results.removeValue(forKey: order.removeFirst()) }
        return true
    }

    public mutating func setResult(_ key: UInt64, _ r: QLabResultCode) { if results[key] != nil { results[key] = r } }

    /// The result, once the QLab answered (nil: not seen or still running).
    public func result(_ key: UInt64) -> QLabResultCode? { results[key] ?? nil }
}
