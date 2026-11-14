import Foundation

// QLab mode types (docs/design-qlab.md 6.1, 6.3). Shared by the Mac app, the iPhone app and the tests.

/// What TwinKeys drives (Settings > "TwinKeys が動かすもの"). Default: Ableton Live, as before.
public enum QLabTarget: String, Codable, Sendable, CaseIterable {
    case live, qlab, both
    public var drivesLive: Bool { self != .qlab }
    public var drivesQLab: Bool { self != .live }
    /// On the wire (packet qlabState): 0 live, 1 qlab, 2 both.
    public var code: UInt8 { self == .live ? 0 : self == .qlab ? 1 : 2 }
    public init(code: UInt8) { self = code == 1 ? .qlab : code == 2 ? .both : .live }
}

/// A QLab action (Mac to Mac and iPhone to Mac).
public enum QLabAction: UInt8, Codable, Sendable, CaseIterable {
    case go = 1, playheadNext = 2, playheadPrevious = 3, panic = 4, hardStop = 5,
         goCue = 6,        // move to the numbered cue and GO (needs cueNumber)
         setPlayhead = 7,  // move the playhead to the numbered cue (no GO)
         pause = 8, resume = 9

    /// Name in settings.json (`cue_keys[].qlab.action`).
    public var name: String {
        switch self {
        case .go: return "go"
        case .playheadNext: return "next"
        case .playheadPrevious: return "previous"
        case .panic: return "panic"
        case .hardStop: return "stop"
        case .goCue: return "goCue"
        case .setPlayhead: return "playhead"
        case .pause: return "pause"
        case .resume: return "resume"
        }
    }

    public init?(name: String) {
        guard let a = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = a
    }

    public var needsCue: Bool { self == .goCue || self == .setPlayhead }
    /// Starts sound (GO and its kin): the double-press guard and the "next changed" check apply.
    public var starts: Bool { self == .go || self == .goCue }
}

public struct QLabCommand: Codable, Equatable, Sendable {
    public var action: QLabAction
    /// goCue / setPlayhead: the cue number to go to.
    public var cueNumber: String?
    /// GO: the cue number standing by on the main Mac (or on the iPhone) when it was pressed.
    public var expect: String?
    public init(action: QLabAction, cueNumber: String? = nil, expect: String? = nil) {
        self.action = action; self.cueNumber = cueNumber; self.expect = expect
    }

    /// Cue numbers longer than this cannot be carried between the Macs (packet limit).
    public static let maxNumberBytes = 24

    public var isValid: Bool {
        if action.needsCue, (cueNumber ?? "").isEmpty { return false }
        for s in [cueNumber, expect] {
            if let s, s.utf8.count > Self.maxNumberBytes { return false }
        }
        return true
    }
}

/// A cue key's QLab action (`cue_keys[].qlab` in settings.json), e.g. `{ "action": "goCue", "cue": "90" }`.
public struct QLabKeyAction: Codable, Equatable, Hashable, Sendable {
    public var action: QLabAction?
    public var cue: String?
    public init(_ action: QLabAction?, cue: String? = nil) { self.action = action; self.cue = cue }

    enum CodingKeys: String, CodingKey { case action, cue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let n = try c.decodeIfPresent(String.self, forKey: .action) ?? "none"
        action = QLabAction(name: n)
        cue = try c.decodeIfPresent(String.self, forKey: .cue)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action?.name ?? "none", forKey: .action)
        try c.encodeIfPresent(cue, forKey: .cue)
    }

    /// The command for a press of this key (nil: none, or "go to cue" without a number).
    public func command(expect: String?) -> QLabCommand? {
        guard let action else { return nil }
        let c = QLabCommand(action: action, cueNumber: action.needsCue ? cue : nil, expect: action.starts && action == .go ? expect : nil)
        return c.isValid ? c : nil
    }

    /// Design 4.1: Space = GO, ↓ = next, ↑ = previous, Esc = Panic, anything else nothing.
    public static func defaultFor(keycode: UInt16) -> QLabKeyAction? {
        switch keycode {
        case KeyNames.space: return QLabKeyAction(.go)
        case KeyNames.down: return QLabKeyAction(.playheadNext)
        case KeyNames.up: return QLabKeyAction(.playheadPrevious)
        case KeyNames.escape: return QLabKeyAction(.panic)
        default: return nil
        }
    }
}

/// What a Mac's QLab did with a command (packet qlabResult, design 6.2).
public enum QLabResultCode: UInt8, Sendable, Equatable {
    case ok = 0, corrected = 1, noSuchCue = 2, notConnected = 3, denied = 4, badPasscode = 5, noAnswer = 6

    /// As told to the iPhone in `result.backup` (and shown on the Mac).
    public var name: String {
        switch self {
        case .ok: return "delivered"
        case .corrected: return "corrected"
        case .noSuchCue: return "noSuchCue"
        case .notConnected: return "notConnected"
        case .denied: return "denied"
        case .badPasscode: return "badPasscode"
        case .noAnswer: return "noAnswer"
        }
    }
    public var ran: Bool { self == .ok || self == .corrected }
}

/// The link to this Mac's QLab (design 5.2). Raw values go on the wire (packet qlabState).
public enum QLabConnState: UInt8, Codable, Sendable {
    /// Ableton Live mode: QLab is not used.
    case off = 0
    /// TCP 53000 does not answer (QLab not open): retrying every 1 → 5 s.
    case connecting = 1
    /// Several workspaces are open and none is chosen.
    case choosingWorkspace = 2
    case authorizing = 3
    /// `badpass`: not retried by itself (QLab makes each wrong try wait longer).
    case badPasscode = 4
    /// Connected, but the passcode has no "control" permission: shows, cannot GO.
    case viewOnly = 5
    case ready = 6
    /// Nothing heard for 2 s while ready.
    case stale = 7
    /// TCP is up but QLab does not answer at all (OSC Access off?).
    case noAnswer = 8
    /// QLab is open with no workspace.
    case noWorkspace = 9
    /// No passcode, and "No Passcode" has no permissions.
    case needsPasscode = 10

    public var canControl: Bool { self == .ready || self == .stale }
    public var canView: Bool { self == .ready || self == .stale || self == .viewOnly }
}

/// QLab's OSC permissions (design 3.1).
public struct QLabPermissions: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let view = QLabPermissions(rawValue: 1)
    public static let edit = QLabPermissions(rawValue: 2)
    public static let control = QLabPermissions(rawValue: 4)
}

/// Cue types as TwinKeys shows them (packet qlabItem carries the code).
public enum QLabCueType: UInt8, Codable, Sendable, CaseIterable {
    case other = 0, audio, video, fade, group, memo, network, midi, wait, start, stop, mic, light, script, text, camera, cueList

    public init(qlab: String) {
        switch qlab.lowercased() {
        case "audio": self = .audio
        case "video": self = .video
        case "fade": self = .fade
        case "group": self = .group
        case "memo": self = .memo
        case "network", "osc": self = .network
        case "midi", "midi file", "msc": self = .midi
        case "wait": self = .wait
        case "start": self = .start
        case "stop": self = .stop
        case "mic": self = .mic
        case "light": self = .light
        case "script": self = .script
        case "text": self = .text
        case "camera": self = .camera
        case "cue list", "cart": self = .cueList
        default: self = .other
        }
    }

    /// Short label for the lists ("AUD", "FADE", "GRP"…).
    public var short: String {
        switch self {
        case .other: return "CUE"
        case .audio: return "AUD"
        case .video: return "VID"
        case .fade: return "FADE"
        case .group: return "GRP"
        case .memo: return "MEMO"
        case .network: return "NET"
        case .midi: return "MIDI"
        case .wait: return "WAIT"
        case .start: return "STRT"
        case .stop: return "STOP"
        case .mic: return "MIC"
        case .light: return "LGT"
        case .script: return "SCPT"
        case .text: return "TEXT"
        case .camera: return "CAM"
        case .cueList: return "LIST"
        }
    }
}

/// One cue of the chosen cue list (flattened: groups are followed by their cues, one level deeper).
public struct QLabCue: Codable, Equatable, Sendable, Identifiable {
    public var uniqueID: String
    public var number: String
    public var name: String
    public var type: QLabCueType
    /// Seconds (nil: not known, or a cue without a length).
    public var duration: Double?
    public var colorName: String?
    /// 0 at the top of the list, 1 inside a group, …
    public var depth: Int
    public var id: String { uniqueID }
    public init(uniqueID: String, number: String, name: String, type: QLabCueType, duration: Double? = nil,
                colorName: String? = nil, depth: Int = 0) {
        self.uniqueID = uniqueID; self.number = number; self.name = name; self.type = type
        self.duration = duration; self.colorName = colorName; self.depth = depth
    }

    /// "12 雨の音（遠く）" (number and name, either may be empty).
    public var title: String {
        [number, name].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Mac → iPhone `qlabCues`: the chosen cue list, in pieces of at most `chunk` cues.
public struct QLabCueList: Codable, Equatable, Sendable {
    public var workspace: String
    public var listName: String
    /// Index of `cues[0]` in the whole list, and the whole list's length.
    public var offset: Int
    public var total: Int
    public var cues: [QLabCue]
    public init(workspace: String, listName: String, offset: Int, total: Int, cues: [QLabCue]) {
        self.workspace = workspace; self.listName = listName; self.offset = offset; self.total = total; self.cues = cues
    }

    public static let chunk = 200

    /// The whole list cut into messages.
    public static func pieces(workspace: String, listName: String, cues: [QLabCue]) -> [QLabCueList] {
        if cues.isEmpty { return [QLabCueList(workspace: workspace, listName: listName, offset: 0, total: 0, cues: [])] }
        return stride(from: 0, to: cues.count, by: chunk).map {
            QLabCueList(workspace: workspace, listName: listName, offset: $0, total: cues.count,
                        cues: Array(cues[$0..<min(cues.count, $0 + chunk)]))
        }
    }

    /// iPhone: puts a piece into the list collected so far (a piece with offset 0 starts over).
    public static func merge(_ piece: QLabCueList, into list: [QLabCue]) -> [QLabCue] {
        var out = piece.offset == 0 ? [] : list
        if out.count > piece.offset { out.removeSubrange(piece.offset...) }
        guard out.count == piece.offset else { return list }        // a piece is missing: wait for the next full send
        out += piece.cues
        return Array(out.prefix(piece.total))
    }
}

/// A running (or paused) cue with its times.
public struct QLabRunningCue: Codable, Equatable, Sendable, Identifiable {
    public var uniqueID: String
    public var number: String
    public var name: String
    public var type: QLabCueType
    /// actionElapsed (s).
    public var elapsed: Double
    /// currentDuration (s); nil or 0: no length (a loop or a memo).
    public var duration: Double?
    public var paused: Bool
    public var id: String { uniqueID }
    public init(uniqueID: String, number: String, name: String, type: QLabCueType, elapsed: Double, duration: Double?, paused: Bool) {
        self.uniqueID = uniqueID; self.number = number; self.name = name; self.type = type
        self.elapsed = elapsed; self.duration = duration; self.paused = paused
    }

    /// currentDuration − actionElapsed (design 3.1); nil without a length.
    public var left: Double? {
        guard let d = duration, d > 0 else { return nil }
        return max(0, d - elapsed)
    }

    /// 0…1 of the length played.
    public var fraction: Double? {
        guard let d = duration, d > 0 else { return nil }
        return min(1, max(0, elapsed / d))
    }
}

/// The other Mac's QLab, as the main Mac tells the iPhone.
public struct QLabBackupStatus: Codable, Equatable, Sendable {
    /// The other Mac's TwinKeys understands QLab mode (features bit).
    public var supported: Bool
    public var state: QLabConnState
    public var showMode: Bool
    public var cueCount: Int
    /// nil while not known.
    public var sameCues: Bool?
    public var playheadNumber: String?
    public var samePlayhead: Bool?
    public var running: Int
    public init(supported: Bool, state: QLabConnState, showMode: Bool, cueCount: Int, sameCues: Bool?,
                playheadNumber: String?, samePlayhead: Bool?, running: Int) {
        self.supported = supported; self.state = state; self.showMode = showMode; self.cueCount = cueCount
        self.sameCues = sameCues; self.playheadNumber = playheadNumber; self.samePlayhead = samePlayhead; self.running = running
    }
}

/// The last GO (or other QLab command) and where it arrived.
public struct QLabLastCommand: Codable, Equatable, Sendable {
    public var action: QLabAction
    public var number: String?
    public var name: String?
    /// The main Mac's own QLab: "delivered", "noAnswer", …
    public var main: String
    /// The backup: "waiting", "delivered", "corrected", "missing", "noSuchCue", "notLinked", "unsupported", …
    public var backup: String
    public init(action: QLabAction, number: String?, name: String?, main: String, backup: String) {
        self.action = action; self.number = number; self.name = name; self.main = main; self.backup = backup
    }
}

/// Mac → iPhone `qlabStatus` (design 6.3).
public struct QLabStatus: Codable, Equatable, Sendable {
    public var target: QLabTarget
    public var state: QLabConnState
    public var version: String?
    public var workspaceName: String?
    public var listName: String?
    public var permissions: QLabPermissions
    public var showMode: Bool
    public var cueCount: Int
    public var playheadID: String?
    public var playheadNumber: String?
    public var running: [QLabRunningCue]
    public var backup: QLabBackupStatus?
    public var last: QLabLastCommand?
    /// When the Mac made this (s since 1970): the iPhone counts the time left down from it.
    public var stamp: Double
    public init(target: QLabTarget, state: QLabConnState, version: String? = nil, workspaceName: String? = nil,
                listName: String? = nil, permissions: QLabPermissions = [], showMode: Bool = false, cueCount: Int = 0,
                playheadID: String? = nil, playheadNumber: String? = nil, running: [QLabRunningCue] = [],
                backup: QLabBackupStatus? = nil, last: QLabLastCommand? = nil, stamp: Double = 0) {
        self.target = target; self.state = state; self.version = version; self.workspaceName = workspaceName
        self.listName = listName; self.permissions = permissions; self.showMode = showMode; self.cueCount = cueCount
        self.playheadID = playheadID; self.playheadNumber = playheadNumber; self.running = running
        self.backup = backup; self.last = last; self.stamp = stamp
    }

    /// Equal apart from the clock (the Mac sends a new one when something else changed, or the times moved).
    public func sameExceptTimes(_ o: QLabStatus) -> Bool {
        var a = self, b = o
        a.stamp = 0; b.stamp = 0
        a.running = a.running.map { var r = $0; r.elapsed = 0; return r }
        b.running = b.running.map { var r = $0; r.elapsed = 0; return r }
        return a == b
    }
}

/// QLab settings of this Mac (`qlab` in settings.json; design 6.1). The passcode is in the keychain.
public struct QLabSettings: Codable, Equatable, Sendable {
    public var workspaceName: String?
    public var workspaceID: String?
    /// Move the backup's playhead to the main's after every move (default on).
    public var followPlayhead = true
    /// Refuse a GO when the iPhone (or key) saw another "next" than QLab has now (default on).
    public var refuseStaleGo = true
    /// In "QLab only" mode, still send the cue keys' MIDI notes (default off: QLab's Workspace MIDI
    /// would run them twice).
    public var notesInQLabMode = false
    /// QLab's OSC port (53000; tests use another one).
    public var port: UInt16 = 53000

    public init() {}

    enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name", workspaceID = "workspace_id", followPlayhead = "follow_playhead"
        case refuseStaleGo = "refuse_stale_go", notesInQLabMode = "notes_in_qlab_mode", port
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QLabSettings()
        workspaceName = try? c.decodeIfPresent(String.self, forKey: .workspaceName)
        workspaceID = try? c.decodeIfPresent(String.self, forKey: .workspaceID)
        followPlayhead = (try? c.decodeIfPresent(Bool.self, forKey: .followPlayhead)) ?? d.followPlayhead
        refuseStaleGo = (try? c.decodeIfPresent(Bool.self, forKey: .refuseStaleGo)) ?? d.refuseStaleGo
        notesInQLabMode = (try? c.decodeIfPresent(Bool.self, forKey: .notesInQLabMode)) ?? d.notesInQLabMode
        port = (try? c.decodeIfPresent(UInt16.self, forKey: .port)) ?? d.port
    }
}

/// Seconds as "3:20" / "1:02:03" (lengths in the cue list).
public func formatQLabDuration(_ seconds: Double) -> String {
    let s = Int(max(0, seconds).rounded())
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}
