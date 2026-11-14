import Foundation

/// QLab mode on one Mac (docs/design-qlab.md 5.3, 5.4): a command from a cue key or the iPhone runs
/// on this Mac's QLab and, at the same moment, goes to the backup over the link; the backup runs what
/// the main Mac sends it and follows the main Mac's playhead. The QLab itself is behind `runLocal`
/// and `snapshot` (QLabEngine on its own queue in the app; a fake in the tests).
///
/// Thread-safe. Never call it with the Conductor's lock held (hooks hand the work to another queue).
public final class QLabDriver: @unchecked Sendable {
    /// What happened to a command, for the iPhone's `result` and the Mac's screen.
    public struct Outcome: Equatable, Sendable {
        /// It ran on this Mac's QLab.
        public var ok: Bool
        /// Why not (nil when it ran): "qlab_next_changed", "qlab_notConnected", "qlab_noAnswer", …
        public var error: String?
        /// "delivered", "corrected", "missing", "noSuchCue", "notLinked", "unsupported", "notSent", …
        public var backup: String
        public init(ok: Bool, error: String?, backup: String) { self.ok = ok; self.error = error; self.backup = backup }
    }

    private let lock = NSLock()
    private let conductor: Conductor
    private let clock: () -> Double
    private let runLocal: (QLabCommand, Bool, @escaping (QLabResultCode) -> Void) -> Void
    private let snapshot: () -> QLabEngineSnapshot
    private let followLocal: (String?) -> Void
    private var settings: QLabSettings
    private var target: QLabTarget
    private var goGuard = QLabGoGuard()
    private struct Waiting {
        var cmd: QLabCommand
        var forward: Conductor.QLabForward
        var local: QLabResultCode?
        var startedAt: Double
        var done: (Outcome) -> Void
    }
    private var waiting: [Int: Waiting] = [:]
    private var nextID = 0
    private var last: QLabLastCommand?
    public var log: (String) -> Void = { _ in }
    /// The last command changed (main thread work: hand it on).
    public var onLastChanged: () -> Void = {}

    /// A command is settled when the backup has answered, or after this long.
    public static let settleLimit = 1.2

    /// `runLocal(cmd, asBackup, done)`: run on this Mac's QLab. `followLocal(number)`: move this
    /// Mac's playhead to the main Mac's cue (QLabEngine.follow).
    public init(conductor: Conductor, settings: QLabSettings, target: QLabTarget, clock: @escaping () -> Double,
                snapshot: @escaping () -> QLabEngineSnapshot,
                runLocal: @escaping (QLabCommand, Bool, @escaping (QLabResultCode) -> Void) -> Void,
                followLocal: @escaping (String?) -> Void) {
        self.conductor = conductor; self.settings = settings; self.target = target; self.clock = clock
        self.snapshot = snapshot; self.runLocal = runLocal; self.followLocal = followLocal
    }

    public func setSettings(_ s: QLabSettings, target t: QLabTarget) {
        lock.lock(); settings = s; target = t; lock.unlock()
    }

    public var currentTarget: QLabTarget { lock.lock(); defer { lock.unlock() }; return target }

    public var lastCommand: QLabLastCommand? { lock.lock(); defer { lock.unlock() }; return last }

    /// Backup side: wire the Conductor's hooks to this Mac's QLab. Call once.
    public func attach() {
        conductor.onQLabCommandRun = { [weak self] cmd, answer in
            guard let self else { answer(.notConnected); return }
            // Under the Conductor's lock: only hand on (runLocal goes to the QLab's own queue).
            guard self.qlabOn else { answer(.notConnected); return }
            self.runLocal(cmd, true, answer)
        }
        conductor.onPeerQLabState = { [weak self] st, iAmMain in
            guard let self, !iAmMain, st.follow, self.followOn else { return }
            self.followLocal(st.playhead)
        }
    }

    private var qlabOn: Bool { lock.lock(); defer { lock.unlock() }; return target.drivesQLab }
    private var followOn: Bool { lock.lock(); defer { lock.unlock() }; return target.drivesQLab && settings.followPlayhead }

    /// Main Mac: a cue key with a QLab action went down.
    public func key(_ k: CueKey) {
        guard let c = k.qlabAction?.command(expect: nil) else { return }
        command(c) { [weak self] o in
            if !o.ok { self?.log("QLab: key \(k.label) (\(c.action.name)) not run: \(o.error ?? "?")") }
        }
    }

    /// Runs `cmd` here and on the backup. `done` is called once, when both have answered (or not in time).
    public func command(_ cmd: QLabCommand, done: @escaping (Outcome) -> Void) {
        let snap = snapshot()
        lock.lock()
        let now = clock()
        guard target.drivesQLab else { lock.unlock(); done(Outcome(ok: false, error: "qlab_off", backup: "notSent")); return }
        guard cmd.isValid else { lock.unlock(); done(Outcome(ok: false, error: "invalid", backup: "notSent")); return }
        // Design 10 / approved point 3: if this Mac's QLab cannot run it, a GO or a playhead move goes
        // nowhere (one Mac alone would drift). Panic and Stop still go to the backup.
        let stops = [.panic, .hardStop, .pause].contains(cmd.action)
        if !snap.state.canControl && !stops {
            let why: String
            switch snap.state {
            case .viewOnly: why = "qlab_denied"
            case .badPasscode, .needsPasscode: why = "qlab_badPasscode"
            default: why = "qlab_notConnected"
            }
            lock.unlock()
            log("QLab: \(cmd.action.name) not sent (this Mac's QLab: \(snap.state))")
            done(Outcome(ok: false, error: why, backup: "notSent"))
            return
        }
        switch QLabPlanner.mainCheck(cmd, playhead: snap.playhead, refuseStale: settings.refuseStaleGo, guardState: &goGuard, now: now) {
        case .doublePress:
            lock.unlock()
            done(Outcome(ok: false, error: "qlab_double", backup: "notSent"))
            return
        case let .nextChanged(n):
            lock.unlock()
            log("QLab: GO not sent: the next cue is \(n ?? "none") now, not \(cmd.expect ?? "?")")
            done(Outcome(ok: false, error: "qlab_next_changed", backup: "notSent"))
            return
        case .ok:
            break
        }
        // The backup follows the main Mac's cue number (design 5.3-3): the GO carries what stands by here.
        var forwarded = cmd
        if cmd.action == .go {
            let n = snap.playhead?.number ?? ""
            forwarded.expect = n.isEmpty || n.utf8.count > QLabCommand.maxNumberBytes ? nil : n
        }
        nextID += 1
        let id = nextID
        let cue: QLabCue? = {
            switch cmd.action {
            case .go: return snap.playheadCue
            case .goCue, .setPlayhead: return snap.allCues.first { $0.number == cmd.cueNumber }
            default: return nil
            }
        }()
        last = QLabLastCommand(action: cmd.action, number: cue?.number ?? cmd.cueNumber, name: cue?.name, main: "waiting", backup: "waiting")
        lock.unlock()
        // Both at the same moment: the backup first (its packet is on the way while this QLab works).
        let forward = conductor.forwardQLab(forwarded)
        lock.lock()
        waiting[id] = Waiting(cmd: cmd, forward: forward, local: nil, startedAt: now, done: done)
        lock.unlock()
        onLastChanged()
        runLocal(cmd, false) { [weak self] code in self?.localDone(id, code) }
    }

    private func localDone(_ id: Int, _ code: QLabResultCode) {
        lock.lock()
        waiting[id]?.local = code
        lock.unlock()
        settle()
    }

    /// Call every ~0.1 s (and it is called when this Mac's QLab answers).
    public func tick() { settle() }

    private func settle() {
        let now = clock()
        var finished: [(Waiting, Outcome)] = []
        lock.lock()
        for (id, w) in waiting {
            guard let local = w.local else {
                if now - w.startedAt > Self.settleLimit + QLabEngine.replyTimeout {
                    waiting[id] = nil
                    finished.append((w, Outcome(ok: false, error: "qlab_noAnswer", backup: backupText(w, now: now, final: true))))
                }
                continue
            }
            let b = backupText(w, now: now, final: false)
            guard b != "waiting" || now - w.startedAt > Self.settleLimit else { continue }
            waiting[id] = nil
            let o = Outcome(ok: local.ran, error: local.ran ? nil : "qlab_" + local.name, backup: b == "waiting" ? "missing" : b)
            finished.append((w, o))
        }
        if let l = last, let f = finished.last {
            last = QLabLastCommand(action: l.action, number: l.number, name: l.name,
                                   main: f.1.ok ? "delivered" : (f.1.error ?? "error"), backup: f.1.backup)
        }
        lock.unlock()
        if !finished.isEmpty { onLastChanged() }
        for (w, o) in finished { w.done(o) }
    }

    private func backupText(_ w: Waiting, now: Double, final: Bool) -> String {
        switch w.forward {
        case .notLinked: return "notLinked"
        case .unsupported: return "unsupported"
        case let .sent(id):
            let d = conductor.qlabDelivery(id)
            return d == "unknown" ? "missing" : d
        }
    }

    // MARK: State for the other Mac and the iPhone

    /// Tell the other Mac this Mac's QLab (with each change; the Conductor repeats it with each heartbeat).
    public func publish(_ snap: QLabEngineSnapshot, keys: [CueKey]) {
        lock.lock()
        let t = target, s = settings
        lock.unlock()
        guard t.drivesQLab else { conductor.setLocalQLab(nil, cues: nil); return }
        let summary = QLabCueSummary(snap.cues)
        let st = QLabLinkState(state: snap.state, permissions: snap.permissions, showMode: snap.showMode,
                               follow: s.followPlayhead && conductor.sendsKeys, target: t, running: snap.running.count,
                               cueCount: snap.cues.count, listHash: summary.hash,
                               keysHash: QLabLinkState.keysHash(target: t, keys: keys),
                               playhead: snap.playhead.flatMap { $0.number.isEmpty || $0.number.utf8.count > QLabCommand.maxNumberBytes ? nil : $0.number })
        conductor.setLocalQLab(st, cues: summary)
    }

    /// The other Mac's QLab for the iPhone and the Mac's screen.
    public func backupStatus(_ snap: QLabEngineSnapshot) -> QLabBackupStatus? {
        guard let understands = conductor.peerUnderstandsQLab else { return nil }
        guard understands else {
            return QLabBackupStatus(supported: false, state: .off, showMode: false, cueCount: 0, sameCues: nil,
                                    playheadNumber: nil, samePlayhead: nil, running: 0)
        }
        guard let p = conductor.peerQLabStatus else {
            return QLabBackupStatus(supported: true, state: .off, showMode: false, cueCount: 0, sameCues: nil,
                                    playheadNumber: nil, samePlayhead: nil, running: 0)
        }
        let mine = QLabCueSummary(snap.cues)
        return QLabBackupStatus(supported: true, state: p.state, showMode: p.showMode, cueCount: p.cueCount,
                                sameCues: snap.cues.isEmpty ? nil : (p.listHash == mine.hash && p.cueCount == mine.items.count),
                                playheadNumber: p.playhead,
                                samePlayhead: snap.playhead == nil && p.playhead == nil ? true : p.playhead == snap.playhead?.number,
                                running: p.running)
    }

    public func status(_ snap: QLabEngineSnapshot, stamp: Double) -> QLabStatus {
        lock.lock(); let t = target; let l = last; lock.unlock()
        return QLabStatus(target: t, state: t.drivesQLab ? snap.state : .off, version: snap.version,
                          workspaceName: snap.workspace?.displayName, listName: snap.listName, permissions: snap.permissions,
                          showMode: snap.showMode, cueCount: snap.cues.count, playheadID: snap.playhead?.uniqueID,
                          playheadNumber: snap.playhead?.number, running: snap.running, backup: backupStatus(snap),
                          last: l, stamp: stamp)
    }
}
