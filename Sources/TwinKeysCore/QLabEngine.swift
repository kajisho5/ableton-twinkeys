import Foundation

/// What a Mac knows about its own QLab (read by the app and the link).
public struct QLabEngineSnapshot: Equatable, Sendable {
    public var transportUp = false
    public var state: QLabConnState = .connecting
    public var version: String?
    public var workspaces: [QLabWorkspaceInfo] = []
    public var workspace: QLabWorkspaceInfo?
    public var permissions: QLabPermissions = []
    public var showMode = false
    public var listName = ""
    /// The cue list shown (the one holding the playhead, else the first).
    public var cues: [QLabCue] = []
    /// Every cue list's cues (numbers are looked up in all of them).
    public var allCues: [QLabCue] = []
    public var playhead: QLabCueRef?
    public var running: [QLabRunningCue] = []
    public var lastGoAt = -100.0
    public init() {}

    public var playheadCue: QLabCue? { playhead.flatMap { p in allCues.first { $0.uniqueID == p.uniqueID } } }
}

/// The QLab side of TwinKeys on one Mac (docs/design-qlab.md 5.2): the connection steps, the reads
/// and the commands, over any byte stream to QLab's TCP port (the app gives it a Network.framework
/// connection to 127.0.0.1:53000; the tests a plain socket to scripts/fake-qlab.py).
///
/// Not thread-safe: call everything on one queue. `send` is called on that queue too.
public final class QLabEngine {
    public struct Config: Equatable, Sendable {
        public var workspaceID: String?
        public var workspaceName: String?
        /// 4 digits, or empty for "No Passcode".
        public var passcode: String
        public init(workspaceID: String? = nil, workspaceName: String? = nil, passcode: String = "") {
            self.workspaceID = workspaceID; self.workspaceName = workspaceName; self.passcode = passcode
        }
    }

    /// SLIP-framed bytes for QLab.
    public var send: ([UInt8]) -> Void = { _ in }
    /// Something shown changed.
    public var onChange: () -> Void = {}
    public var log: (String) -> Void = { _ in }
    /// The workspace was chosen automatically (the app remembers it).
    public var onWorkspaceChosen: (QLabWorkspaceInfo) -> Void = { _ in }

    public private(set) var config: Config
    public private(set) var snapshot = QLabEngineSnapshot()
    private let clock: () -> Double

    private var decoder = SLIPDecoder()
    private var upAt = 0.0
    private var lastHeard = -100.0
    private var lastThump = -100.0
    private var lastWorkspacesAsk = -100.0
    private var lastPlayheadPoll = -100.0
    private var lastRunningPoll = -100.0
    private var pollRunningUntil = -100.0
    private var cueListsDue: Double?
    private var listID: String?
    private var lists: [QLabCueListInfo] = []
    private var durations: [String: Double] = [:]
    private var durationQueue: [String] = []
    private var runningValues: [String: [String: Any]] = [:]
    private var runningOrder: [String] = []
    /// The state to go back to when a stale link is heard again.
    private var liveState: QLabConnState = .ready
    private var probed = false
    private struct Pending { var address: String; var at: Double; var done: (QLabReply?) -> Void }
    private var pending: [Pending] = []

    /// A command without an answer for this long failed ("noAnswer").
    public static let replyTimeout = 1.0
    /// Nothing heard this long while ready: stale (design 5.2).
    public static let staleAfter = 2.0
    /// Running cues are read this often while any run (design 5.2: at most 5 a second).
    public static let runningInterval = 0.2
    public static let playheadInterval = 2.0
    static let durationsPerTick = 5
    /// Keys read for each running cue.
    static let runningKeys = "[\"currentDuration\",\"actionElapsed\",\"isPaused\",\"number\",\"listName\",\"type\"]"

    public init(config: Config, clock: @escaping () -> Double) {
        self.config = config
        self.clock = clock
    }

    // MARK: Inputs

    /// The TCP connection to QLab is up: ask for the workspaces.
    public func transportConnected() {
        let now = clock()
        decoder.reset()
        snapshot = QLabEngineSnapshot()
        snapshot.transportUp = true
        snapshot.state = .connecting
        upAt = now; lastHeard = -100; probed = false
        lists = []; listID = nil; durations = [:]; durationQueue = []; runningValues = [:]; runningOrder = []
        request(OSCMessage(QLabOSCAddress.version)) { [weak self] r in
            if let v = r?.string { self?.snapshot.version = v; self?.onChange() }
        }
        askWorkspaces(now)
        onChange()
    }

    /// The TCP connection is gone (QLab quit, or never there).
    public func transportClosed() {
        failPending()
        let was = snapshot
        snapshot = QLabEngineSnapshot()
        snapshot.state = .connecting
        snapshot.version = was.version
        lists = []; listID = nil; runningValues = [:]; runningOrder = []
        if was != snapshot { onChange() }
    }

    /// Settings changed (workspace chosen, passcode typed). Connects again with them.
    public func setConfig(_ c: Config) {
        guard c != config else { return }
        config = c
        guard snapshot.transportUp else { return }
        // A wrong passcode is only tried again when the person changes it (QLab makes each wrong try wait longer).
        snapshot.workspace = nil
        snapshot.state = .connecting
        failPending()
        askWorkspaces(clock())
        onChange()
    }

    public func received(_ bytes: [UInt8]) {
        for p in decoder.feed(bytes) {
            guard let m = OSCMessage.decode(p) else { continue }
            heard()
            if let r = QLabReply(m) { handleReply(r) } else if let u = QLabUpdate(m) { handleUpdate(u, m) }
        }
    }

    /// Call every ~0.1 s.
    public func tick() {
        let now = clock()
        // Commands without an answer.
        let late = pending.filter { now - $0.at >= Self.replyTimeout }
        if !late.isEmpty {
            pending.removeAll { now - $0.at >= Self.replyTimeout }
            for p in late { p.done(nil) }
        }
        guard snapshot.transportUp else { return }
        switch snapshot.state {
        case .connecting, .noAnswer, .noWorkspace:
            if now - lastWorkspacesAsk >= 2 { askWorkspaces(now) }
            if snapshot.state == .connecting, now - upAt >= Self.staleAfter, lastHeard < upAt {
                set(.noAnswer)
                log("QLab: no answer on its OSC port (is OSC Access on?)")
            }
        case .ready, .viewOnly, .stale:
            guard let ws = snapshot.workspace?.uniqueID else { return }
            if now - lastHeard >= 1, now - lastThump >= 1 {
                lastThump = now
                request(OSCMessage(QLabOSCAddress.thump(ws))) { _ in }
            }
            if snapshot.state != .stale, now - lastHeard > Self.staleAfter {
                liveState = snapshot.state
                set(.stale)
            }
            if now - lastPlayheadPoll >= Self.playheadInterval { pollPlayhead(ws, now) }
            if let due = cueListsDue, now >= due { cueListsDue = nil; readCueLists(ws) }
            if (!runningOrder.isEmpty || now < pollRunningUntil), now - lastRunningPoll >= Self.runningInterval {
                pollRunning(ws, now)
            }
            for _ in 0..<Self.durationsPerTick {
                guard !durationQueue.isEmpty else { break }
                readDuration(ws, durationQueue.removeFirst())
            }
        default:
            break
        }
    }

    /// Runs a command on this Mac's QLab. `asBackup`: forwarded by the main Mac (GO follows its number).
    public func run(_ cmd: QLabCommand, asBackup: Bool, done: @escaping (QLabResultCode) -> Void) {
        guard let ws = snapshot.workspace?.uniqueID, snapshot.state.canControl else {
            switch snapshot.state {
            case .badPasscode, .needsPasscode: done(.badPasscode)
            case .viewOnly: done(.denied)
            default: done(.notConnected)
            }
            return
        }
        switch QLabPlanner.plan(cmd, workspace: ws, cues: snapshot.allCues, playhead: snapshot.playhead, asBackup: asBackup) {
        case let .refuse(code):
            done(code)
        case let .send(msgs, code):
            let now = clock()
            if cmd.action.starts { snapshot.lastGoAt = now }
            // GO, Panic and the playhead buttons change what runs: read the running cues soon.
            pollRunningUntil = now + 3
            lastPlayheadPoll = now - Self.playheadInterval + 0.3
            var left = msgs.count, result = code
            for m in msgs {
                request(m) { r in
                    if let r {
                        if r.status == "denied" { result = .denied } else if r.status == "error", result.ran { result = .noSuchCue }
                    } else if result.ran {
                        result = .noAnswer
                    }
                    left -= 1
                    if left == 0 { done(result) }
                }
            }
        }
    }

    /// Backup: move the playhead to the main Mac's cue number, when it differs (design 3.3-2).
    @discardableResult
    public func follow(mainNumber: String?) -> Bool {
        guard let ws = snapshot.workspace?.uniqueID, snapshot.state.canControl,
              let m = QLabPlanner.follow(mainNumber: mainNumber, playhead: snapshot.playhead, cues: snapshot.allCues,
                                         workspace: ws, lastGoAt: snapshot.lastGoAt, now: clock()) else { return false }
        request(m) { _ in }
        lastPlayheadPoll = clock() - Self.playheadInterval + 0.3
        return true
    }

    // MARK: Steps

    private func askWorkspaces(_ now: Double) {
        lastWorkspacesAsk = now
        request(OSCMessage(QLabOSCAddress.workspaces)) { [weak self] r in
            guard let self, let r, r.status == "ok" else { return }
            self.gotWorkspaces(QLabParse.workspaces(r.data))
        }
    }

    private func gotWorkspaces(_ list: [QLabWorkspaceInfo]) {
        snapshot.workspaces = list
        guard [.connecting, .noAnswer, .noWorkspace, .choosingWorkspace].contains(snapshot.state) else { onChange(); return }
        if list.isEmpty { set(.noWorkspace); return }
        let chosen = list.first { $0.uniqueID == config.workspaceID }
            ?? list.first { config.workspaceName != nil && $0.displayName == config.workspaceName }
            ?? (list.count == 1 ? list[0] : nil)
        guard let ws = chosen else { set(.choosingWorkspace); return }
        if ws.uniqueID != config.workspaceID || ws.displayName != config.workspaceName {
            config.workspaceID = ws.uniqueID; config.workspaceName = ws.displayName
            onWorkspaceChosen(ws)
        }
        authorize(ws)
    }

    private func authorize(_ ws: QLabWorkspaceInfo) {
        snapshot.workspace = ws
        set(.authorizing)
        let args: [OSCArgument] = config.passcode.isEmpty ? [] : [.string(config.passcode)]
        request(OSCMessage(QLabOSCAddress.connect(ws.uniqueID), args)) { [weak self] r in
            guard let self, self.snapshot.workspace?.uniqueID == ws.uniqueID, self.snapshot.state == .authorizing else { return }
            guard let r else { return }        // no answer: tick() asks again from the start
            let answer = r.string ?? (r.status == "ok" ? "ok" : r.status)
            if answer.hasPrefix("ok") {
                self.connected(ws, permissions: Self.permissions(answer))
            } else if answer == "badpass" || r.status == "denied" {
                self.log(self.config.passcode.isEmpty ? "QLab: \(ws.displayName) needs a passcode" : "QLab: wrong passcode for \(ws.displayName)")
                self.set(self.config.passcode.isEmpty ? .needsPasscode : .badPasscode)
            } else {
                // "error": the workspace is gone. Look again.
                self.snapshot.workspace = nil
                self.set(.connecting)
            }
        }
    }

    /// QLab 5 may answer `ok` or `ok:view|control` (design 12-3): the list, when given, is used.
    static func permissions(_ answer: String) -> QLabPermissions? {
        guard let colon = answer.firstIndex(of: ":") else { return nil }
        var p: QLabPermissions = []
        for part in answer[answer.index(after: colon)...].split(whereSeparator: { "|,".contains($0) }) {
            switch part.trimmingCharacters(in: .whitespaces).lowercased() {
            case "view": p.insert(.view)
            case "edit": p.insert(.edit)
            case "control": p.insert(.control)
            default: break
            }
        }
        return p
    }

    private func connected(_ ws: QLabWorkspaceInfo, permissions: QLabPermissions?) {
        let id = ws.uniqueID
        log("QLab: connected to \(ws.displayName)")
        request(OSCMessage(QLabOSCAddress.alwaysReply(id), [.int(1)])) { _ in }
        request(OSCMessage(QLabOSCAddress.updates(id), [.int(1)])) { _ in }
        if let permissions {
            probed = true
            snapshot.permissions = permissions
            set(permissions.contains(.control) ? .ready : .viewOnly)
        } else {
            // Not told: assume view and control until the probe (design 5.2) says otherwise.
            snapshot.permissions = [.view, .control]
            set(.ready)
        }
        liveState = snapshot.state
        readCueLists(id)
        pollPlayhead(id, clock())
    }

    /// Design 5.2: a harmless "control" command (the playhead to where it is) shows whether GO is allowed.
    private func probeControl(_ ws: String) {
        guard !probed, let p = snapshot.playhead else { return }
        probed = true
        request(OSCMessage(QLabOSCAddress.playheadID(ws, p.uniqueID))) { [weak self] r in
            guard let self, let r, r.status == "denied" else { return }
            self.snapshot.permissions = [.view]
            self.liveState = .viewOnly
            if self.snapshot.state.canControl { self.set(.viewOnly) }
            self.log("QLab: the passcode can view but not control")
        }
    }

    private func readCueLists(_ ws: String) {
        request(OSCMessage(QLabOSCAddress.cueLists(ws))) { [weak self] r in
            guard let self, let r, r.status == "ok" else { return }
            self.lists = QLabParse.cueLists(r.data)
            let known = Set(self.lists.flatMap { $0.cues.map(\.uniqueID) })
            self.durations = self.durations.filter { known.contains($0.key) }
            self.durationQueue = self.lists.flatMap(\.cues).filter {
                $0.duration == nil && self.durations[$0.uniqueID] == nil && ![.group, .memo, .cueList].contains($0.type)
            }.map(\.uniqueID)
            self.rebuildCues()
        }
    }

    private func readDuration(_ ws: String, _ uid: String) {
        request(OSCMessage(QLabOSCAddress.valuesForKeys(ws, uid), [.string("[\"currentDuration\"]")])) { [weak self] r in
            guard let self, let d = (r?.data as? [String: Any]).flatMap({ QLabParse.number($0["currentDuration"]) }) else { return }
            self.durations[uid] = d
            if self.durationQueue.isEmpty || self.durations.count % 20 == 0 { self.rebuildCues() }
        }
    }

    private func pollPlayhead(_ ws: String, _ now: Double) {
        lastPlayheadPoll = now
        request(OSCMessage(QLabOSCAddress.playheadUniqueID(ws))) { [weak self] r in
            guard let self, let r, r.status == "ok" else { return }
            let id = r.string ?? ""
            self.setPlayhead(id.isEmpty || id == "none" ? nil : id)
            self.probeControl(ws)
        }
        request(OSCMessage(QLabOSCAddress.showMode(ws))) { [weak self] r in
            guard let self, let r, r.status == "ok", let on = QLabParse.bool(r.data) else { return }
            if on != self.snapshot.showMode { self.snapshot.showMode = on; self.onChange() }
        }
    }

    private func pollRunning(_ ws: String, _ now: Double) {
        lastRunningPoll = now
        request(OSCMessage(QLabOSCAddress.runningOrPaused(ws))) { [weak self] r in
            guard let self, let r, r.status == "ok" else { return }
            let ids = QLabParse.cueIDs(r.data)
            self.runningOrder = ids
            self.runningValues = self.runningValues.filter { ids.contains($0.key) }
            for id in ids {
                self.request(OSCMessage(QLabOSCAddress.valuesForKeys(ws, id), [.string(Self.runningKeys)])) { [weak self] r in
                    guard let self, let d = r?.data as? [String: Any], self.runningOrder.contains(id) else { return }
                    self.runningValues[id] = d
                    self.rebuildRunning()
                }
            }
            self.rebuildRunning()
        }
    }

    private func rebuildRunning() {
        let byID = Dictionary(snapshot.allCues.map { ($0.uniqueID, $0) }, uniquingKeysWith: { a, _ in a })
        // Newest first (QLab lists them in start order).
        let list = runningOrder.reversed().compactMap { id -> QLabRunningCue? in
            let v = runningValues[id] ?? [:]
            let c = byID[id]
            return QLabRunningCue(uniqueID: id, number: (v["number"] as? String) ?? c?.number ?? "",
                                  name: (v["listName"] as? String) ?? c?.name ?? "",
                                  type: (v["type"] as? String).map(QLabCueType.init(qlab:)) ?? c?.type ?? .other,
                                  elapsed: QLabParse.number(v["actionElapsed"]) ?? 0,
                                  duration: QLabParse.number(v["currentDuration"]) ?? c?.duration,
                                  paused: QLabParse.bool(v["isPaused"]) ?? false)
        }
        if list != snapshot.running { snapshot.running = list; onChange() }
    }

    private func rebuildCues() {
        let shown = lists.first { $0.uniqueID == listID } ?? lists.first
        func withDurations(_ cues: [QLabCue]) -> [QLabCue] {
            cues.map { c in var c = c; if c.duration == nil { c.duration = durations[c.uniqueID] }; return c }
        }
        let all = withDurations(lists.flatMap(\.cues))
        let cues = withDurations(shown?.cues ?? [])
        let name = shown?.name ?? ""
        guard all != snapshot.allCues || cues != snapshot.cues || name != snapshot.listName else { return }
        snapshot.allCues = all; snapshot.cues = cues; snapshot.listName = name
        if let p = snapshot.playhead { setPlayhead(p.uniqueID, force: true) }
        onChange()
    }

    private func setPlayhead(_ id: String?, force: Bool = false) {
        let ref = id.map { i in QLabCueRef(uniqueID: i, number: snapshot.allCues.first { $0.uniqueID == i }?.number ?? "") }
        guard force || ref != snapshot.playhead else { return }
        if ref != snapshot.playhead { snapshot.playhead = ref; onChange() }
    }

    // MARK: Messages from QLab

    private func heard() {
        lastHeard = clock()
        if snapshot.state == .stale { set(liveState) }
        if snapshot.state == .noAnswer { set(.connecting) }
    }

    private func handleReply(_ r: QLabReply) {
        guard let i = pending.firstIndex(where: { $0.address == r.address }) else { return }
        let p = pending.remove(at: i)
        p.done(r)
    }

    private func handleUpdate(_ u: QLabUpdate, _ m: OSCMessage) {
        let now = clock()
        guard let ws = snapshot.workspace?.uniqueID else { return }
        switch u {
        case let .workspace(w) where w == ws:
            cueListsDue = now + 0.3
        case let .cue(w, _) where w == ws:
            pollRunningUntil = max(pollRunningUntil, now + 2)
        case let .playbackPosition(w, list, cue) where w == ws:
            if listID != list { listID = list; rebuildCues() }
            setPlayhead(cue)
            pollRunningUntil = max(pollRunningUntil, now + 2)
        case let .disconnect(w) where w == ws:
            log("QLab: the workspace closed")
            failPending()
            snapshot.workspace = nil; snapshot.cues = []; snapshot.allCues = []; snapshot.playhead = nil; snapshot.running = []
            lists = []; listID = nil
            set(.connecting)
            askWorkspaces(now)
        default:
            break
        }
    }

    // MARK: Inside

    private func request(_ m: OSCMessage, done: @escaping (QLabReply?) -> Void) {
        pending.append(Pending(address: m.address, at: clock(), done: done))
        if pending.count > 512 { pending.removeFirst().done(nil) }
        send(SLIP.encode(m.encoded()))
    }

    private func failPending() {
        let p = pending
        pending = []
        for x in p { x.done(nil) }
    }

    private func set(_ s: QLabConnState) {
        guard s != snapshot.state else { return }
        snapshot.state = s
        onChange()
    }
}
