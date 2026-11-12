import Foundation

/// How fader writes reach the console.
public enum DeskWritePath: Equatable, Sendable {
    /// RCP `set` over the TCP connection (levels can be read, or a QL that cannot read).
    case rcp
    /// Yamaha's documented OSC over UDP 49900 (DM families, when levels cannot be read).
    case osc
}

/// Why the console cannot be moved now.
public enum DeskNotReady: Equatable, Sendable {
    /// The feature is off.
    case off
    case noRows
    case invalidRows
    /// The faders are moving right now.
    case busy
    /// Already switched (restore first).
    case alreadyMoved
    case nothingToRestore
    case notConnected
    /// Connected, still finding out whether levels can be read.
    case checking
    /// Levels were read, but not updated for 2 s or more.
    case stale
    /// Levels cannot be read and "Raise to set levels" is off.
    case unreadable
}

public enum DeskReadiness: Equatable, Sendable {
    /// `readLevels`: the backup channels go to the levels read from the main channels (false:
    /// to each row's fixed level).
    case ready(DeskWritePath, readLevels: Bool)
    case notReady(DeskNotReady)

    public var isReady: Bool { if case .ready = self { return true }; return false }
}

/// The console line in Settings and the connection row.
public enum DeskStatus: Equatable, Sendable {
    /// First try since starting, no answer yet.
    case connecting
    /// Connected; finding out whether levels can be read (at most 3 s).
    case checking
    /// Connected; the main channels' levels are read and up to date.
    case reading
    /// Connected; levels were read but are not updating.
    case stale
    /// Levels cannot be read: the backup channels go to the fixed levels. `unconfirmed`: the RCP
    /// port refused the connection, so writes go out over OSC with no sign the console is there.
    case fixedLevels(unconfirmed: Bool)
    /// Connected, levels cannot be read, and fixed levels are off: the console is not moved.
    case cannotRead
    case notReachable
}

/// A takeover or restore that did not start, as shown in the window.
public struct DeskRefusal: Equatable, Sendable {
    public var reason: DeskNotReady
    /// The automatic takeover (main Mac silent for 3 s).
    public var automatic: Bool
    public var restore: Bool
    public init(reason: DeskNotReady, automatic: Bool, restore: Bool) {
        self.reason = reason; self.automatic = automatic; self.restore = restore
    }
}

/// A channel that did not end up where it should after a move.
public struct DeskMismatch: Equatable, Hashable, Sendable {
    public enum Problem: Equatable, Hashable, Sendable {
        /// Read back at this level (dB × 100).
        case level(Int)
        /// The console answered ERROR to the write.
        case refused
        /// No answer when reading back.
        case noAnswer
    }
    public var channel: DeskChannel
    public var expected: Int
    public var problem: Problem
    public init(channel: DeskChannel, expected: Int, problem: Problem) {
        self.channel = channel; self.expected = expected; self.problem = problem
    }
}

/// The check after a move.
public enum DeskCheck: Equatable, Sendable {
    /// Moving, or about to read back.
    case waiting
    /// Read back: every channel is within 1 dB of its level (or exactly −∞).
    case ok
    case mismatches([DeskMismatch])
    /// Levels cannot be read (or the writes went over OSC): nothing to compare.
    case notPossible
    /// The connection dropped before every write went out.
    case interrupted
}

/// A takeover or restore, running or finished.
public struct DeskMoveState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case takeover, restore }
    public var kind: Kind
    public var path: DeskWritePath
    public var fade: Double
    public var readLevels: Bool
    public var plan: DeskPlan
    public var startedAt: Double
    public var nextStep = 0
    public var finishedAt: Double?
    public var check: DeskCheck = .waiting
    var refused: Set<DeskChannel> = []
    var verifySentAt: Double?
    /// Parameters asked again after the move, not answered yet, and what they answered.
    var waiting: Set<FaderAddress> = []
    var readBack: [FaderAddress: Int] = [:]

    public var isRunning: Bool { finishedAt == nil }
}

/// What the window shows about the last move.
public struct DeskMoveSummary: Equatable, Sendable {
    public var kind: DeskMoveState.Kind
    public var fade: Double
    public var running: Bool
    public var path: DeskWritePath
    public var readLevels: Bool
    public var rows: Int
    public var check: DeskCheck
    public init(kind: DeskMoveState.Kind, fade: Double, running: Bool, path: DeskWritePath, readLevels: Bool, rows: Int, check: DeskCheck) {
        self.kind = kind; self.fade = fade; self.running = running; self.path = path
        self.readLevels = readLevels; self.rows = rows; self.check = check
    }
}

/// Everything the window and Settings show about the console. Plain values.
public struct DeskSnapshot: Equatable, Sendable {
    public var model: DeskModel
    public var status: DeskStatus
    /// For a takeover asked for now, with confirmation.
    public var readiness: DeskReadiness
    /// Last level read for each assigned channel (a stereo input: its L half).
    public var levels: [DeskChannel: Int]
    /// Channels whose level was read less than 2 s ago.
    public var fresh: Set<DeskChannel>
    public var move: DeskMoveSummary?
    public var refusal: DeskRefusal?
    public var canRestore: Bool
    /// A takeover to undo, or a message still shown: keep the link even on the main Mac.
    public var needsLink: Bool

    public init(model: DeskModel, status: DeskStatus, readiness: DeskReadiness, levels: [DeskChannel: Int] = [:],
                fresh: Set<DeskChannel> = [], move: DeskMoveSummary? = nil, refusal: DeskRefusal? = nil,
                canRestore: Bool = false, needsLink: Bool = false) {
        self.model = model; self.status = status; self.readiness = readiness; self.levels = levels
        self.fresh = fresh; self.move = move; self.refusal = refusal; self.canRestore = canRestore; self.needsLink = needsLink
    }
}

/// The console link on the backup Mac, without sockets: the caller feeds it the connection's
/// events, each line from the console and the time, and performs the returned actions.
///
/// - Connect (TCP 49280), send `scpmode keepalive 10000`, read the assigned channels with `get`.
/// - Levels are kept per parameter with the time they were read (answers to `get` and `set`,
///   and NOTIFY when the console or another client moves a fader). A level is fresh for 2 s.
///   The main channels are read again every second (so they stay fresh even when the console
///   sends no NOTIFY), every assigned channel every 5 s.
/// - Reading works once an `OK get` arrives. It does not when the first answer is
///   `ERROR get UnknownAddress` / `InvalidArgument`, or no `OK get` arrives within 3 s.
/// - `devstatus runmode` every 5 s; nothing at all from the console for 12 s: the link is down,
///   reconnect after 1, 2, 4, 5, 5… s.
/// - Moves (takeover, restore) are sent step by step from `tick`; afterwards the touched channels
///   are read back and compared (1 dB, or exactly −∞).
public struct DeskLink: Sendable {
    public enum Connection: Equatable, Sendable {
        case stopped
        case connecting(attempt: Int, since: Double)
        /// `failures` tries failed; the next one is at `retryAt`.
        case waiting(failures: Int, retryAt: Double)
        case up(since: Double)
    }

    public enum Reading: Equatable, Sendable { case unknown, ok, unsupported }

    public enum Action: Equatable, Sendable {
        /// Open the TCP connection to the console (settings.host, port 49280).
        case open
        /// Close it.
        case close
        /// One RCP line (ends in "\n").
        case send(String)
        /// One OSC datagram to UDP 49900.
        case sendOSC([UInt8])
        case log(String)
    }

    public struct Level: Equatable, Sendable {
        public var value: Int
        public var at: Double
    }

    private struct Pending: Equatable, Sendable {
        var isSet: Bool
        var address: FaderAddress
        var sentAt: Double
    }

    public static let freshFor = 2.0
    public static let mainPollInterval = 1.0
    public static let fullPollInterval = 5.0
    public static let pingInterval = 5.0
    public static let silenceTimeout = 12.0
    public static let readCheckTimeout = 3.0
    public static let connectTimeout = 5.0
    public static let pendingTimeout = 3.0
    /// Read back this long after the last write, and give the answers this long.
    public static let verifyDelay = 0.3
    public static let verifyTimeout = 2.0
    /// 1 dB.
    public static let tolerance = 100
    static let unreadableCodes: Set<String> = ["UnknownAddress", "InvalidArgument"]

    public private(set) var settings: DeskSettings
    public private(set) var connection: Connection = .stopped
    public private(set) var reading: Reading = .unknown
    public private(set) var levels: [FaderAddress: Level] = [:]
    public private(set) var takeover: DeskTakeoverRecord?
    public private(set) var move: DeskMoveState?
    public private(set) var refusal: DeskRefusal?
    public private(set) var lastHeard = -Double.infinity
    /// The last failed try was refused (the console's address answered, but not on the RCP port).
    public private(set) var refusedLastTime = false
    private var everUp = false
    private var lastPing = -Double.infinity
    private var nextMainPoll = 0.0
    private var nextFullPoll = 0.0
    private var pending: [Pending] = []

    public init(settings: DeskSettings) { self.settings = settings }

    /// Retry delay after `failures` failed tries: 1, 2, 4, 5, 5… seconds.
    public static func retryDelay(failures: Int) -> Double {
        min(5, Double(1 << min(max(failures - 1, 0), 4)))
    }

    // MARK: Inputs

    public mutating func start(now: Double) -> [Action] {
        connection = .connecting(attempt: 1, since: now)
        everUp = false
        refusedLastTime = false
        reading = .unknown
        pending.removeAll()
        return [.open, .log("connecting to \(settings.model.shortName) at \(settings.host)")]
    }

    public mutating func stop() -> [Action] {
        let was = connection
        connection = .stopped
        pending.removeAll()
        return was == .stopped ? [] : [.close]
    }

    /// "Check connection": connect again now.
    public mutating func restart(now: Double) -> [Action] {
        if let m = move, m.isRunning, m.path == .rcp { return [] }
        levels.removeAll()
        return [.close] + start(now: now)
    }

    /// New settings. Another console (address or model) starts over and forgets the takeover.
    public mutating func configure(_ s: DeskSettings, now: Double) -> [Action] {
        let old = settings
        settings = s
        guard s.enabled, s.hasValidHost else { return stop() }
        if old.host != s.host || old.model != s.model || connection == .stopped {
            takeover = nil
            if let m = move, m.isRunning { move = nil }
            return restart(now: now)
        }
        if old.rows != s.rows {
            // New channels are read at once.
            nextMainPoll = now
            nextFullPoll = now
        }
        return []
    }

    /// The TCP connection is ready.
    public mutating func connected(now: Double) -> [Action] {
        guard case .connecting = connection else { return [] }
        connection = .up(since: now)
        everUp = true
        refusedLastTime = false
        lastHeard = now
        lastPing = now
        reading = .unknown
        pending.removeAll()
        nextMainPoll = now + Self.mainPollInterval
        nextFullPoll = now + Self.fullPollInterval
        var a: [Action] = [.log("connected to \(settings.model.shortName) at \(settings.host)"), .send(DeskRCP.keepalive)]
        a += gets(allAddresses, now: now)
        return a
    }

    /// The TCP connection failed, closed or never opened. `refused`: the address answered but
    /// nothing listens on the RCP port.
    public mutating func connectionFailed(now: Double, refused: Bool) -> [Action] {
        var a: [Action] = [.close]
        let failures: Int
        switch connection {
        case .stopped, .waiting: return []
        case let .connecting(attempt, _): failures = attempt
        case .up:
            failures = 1
            a.append(.log("connection to the console lost; reconnecting"))
        }
        if var m = move, m.isRunning, m.path == .rcp {
            m.finishedAt = now
            m.check = .interrupted
            move = m
            a.append(.log("the move stopped: the connection dropped before every level was sent"))
        }
        refusedLastTime = refused
        pending.removeAll()
        connection = .waiting(failures: failures, retryAt: now + Self.retryDelay(failures: failures))
        return a
    }

    /// One line from the console (without the LF).
    public mutating func received(line: String, now: Double) -> [Action] {
        guard case .up = connection else { return [] }
        lastHeard = now
        var a: [Action] = []
        switch DeskRCP.parse(line) {
        case let .level(addr, value, source):
            levels[addr] = Level(value: value, at: now)
            switch source {
            case .get:
                let p = removePending(isSet: false, address: addr)
                noteReadBack(p, value: value)
                if reading != .ok {
                    // Also a late answer after "cannot be read" was decided (a slow console).
                    reading = .ok
                    a.append(.log("fader levels can be read"))
                }
            case .set, .setAdjusted:
                _ = removePending(isSet: true, address: addr)
            case .notify:
                break
            }
            a += checkVerification(now: now)
        case let .error(command, code):
            if command == "get" {
                let p = popPending(isSet: false)
                noteReadBack(p, value: nil)
                if reading == .unknown, Self.unreadableCodes.contains(code) {
                    reading = .unsupported
                    pending.removeAll { !$0.isSet }
                    a.append(.log("fader levels cannot be read (ERROR get \(code))"))
                } else if reading == .ok, Self.unreadableCodes.contains(code), let p {
                    levels.removeValue(forKey: p.address)
                    a.append(.log("\(p.address.channel) cannot be read (ERROR get \(code))"))
                }
            } else if command == "set" {
                let p = popPending(isSet: true)
                if let p, var m = move { m.refused.insert(p.address.channel); move = m }
                a.append(.log("the console refused a level (ERROR set \(code))"))
            }
        case .ok, .notify, .unknown:
            break
        }
        return a
    }

    /// Call every 20-50 ms.
    public mutating func tick(now: Double) -> [Action] {
        var a: [Action] = []
        switch connection {
        case .stopped:
            break
        case let .connecting(attempt, since):
            if now - since >= Self.connectTimeout {
                a += connectionFailed(now: now, refused: false)
                if attempt == 1 { a.append(.log("no answer from \(settings.host)")) }
            }
        case let .waiting(failures, retryAt):
            if now >= retryAt {
                connection = .connecting(attempt: failures + 1, since: now)
                a.append(.open)
            }
        case let .up(since):
            if now - lastHeard >= Self.silenceTimeout {
                a += connectionFailed(now: now, refused: false)
                break
            }
            if reading == .unknown, now - since >= Self.readCheckTimeout {
                reading = .unsupported
                pending.removeAll { !$0.isSet }
                a.append(.log("fader levels cannot be read (no answer to get within 3 s)"))
            }
            if now - lastPing >= Self.pingInterval {
                lastPing = now
                a.append(.send(DeskRCP.ping))
            }
            pending.removeAll { now - $0.sentAt >= Self.pendingTimeout }
            if reading != .unsupported {
                if now >= nextFullPoll {
                    nextFullPoll = now + Self.fullPollInterval
                    nextMainPoll = now + Self.mainPollInterval
                    a += gets(allAddresses, now: now)
                } else if now >= nextMainPoll {
                    nextMainPoll = now + Self.mainPollInterval
                    a += gets(mainAddresses, now: now)
                }
            }
        }
        a += runMove(now: now)
        a += checkVerification(now: now)
        return a
    }

    /// Switches the console now, if it can be: the main Mac stopped. `automatic`: started by
    /// the 3 s silence, which never moves a console it cannot confirm is there.
    public mutating func startTakeover(now: Double, automatic: Bool) -> (DeskReadiness, [Action]) {
        let r = readiness(now: now, automatic: automatic)
        guard case let .ready(path, readLevels) = r else {
            if case let .notReady(why) = r, ![.off, .alreadyMoved, .busy].contains(why) {
                refusal = DeskRefusal(reason: why, automatic: automatic, restore: false)
            }
            return (r, [.log("console not moved (\(automatic ? "automatic, " : "")\(r))")])
        }
        let rows = settings.rows
        var mainLevels: [DeskChannel: Int]?
        if readLevels {
            var m: [DeskChannel: Int] = [:]
            for row in rows { m[row.main] = channelLevel(row.main)?.value }
            mainLevels = m
        }
        var backupLevels: [DeskChannel: Int]?
        if reading == .ok {
            var b: [DeskChannel: Int] = [:]
            for row in rows { b[row.backup] = channelLevel(row.backup)?.value }
            backupLevels = b
        }
        let record: DeskTakeoverRecord
        do {
            record = try DeskPlanner.takeover(rows: rows, model: settings.model, mainLevels: mainLevels, backupLevels: backupLevels,
                                              fade: settings.fade, pullMainToMinusInfinity: settings.pullMainToMinusInfinity)
        } catch {
            refusal = DeskRefusal(reason: .invalidRows, automatic: automatic, restore: false)
            return (.notReady(.invalidRows), [.log("console not moved: \(error)")])
        }
        takeover = record
        var a: [Action] = [.log("switching the console: \(rows.count) row(s), fade \(record.fade) s, \(readLevels ? "levels read" : "fixed levels"), \(path == .rcp ? "RCP" : "OSC")\(automatic ? " (automatic)" : "")")]
        a += begin(.takeover, plan: record.plan, path: path, readLevels: readLevels, fade: record.fade, now: now)
        return (r, a)
    }

    /// "Restore the console": undoes the last takeover with the same fade.
    public mutating func startRestore(now: Double) -> (DeskReadiness, [Action]) {
        let r = restoreReadiness(now: now)
        guard case let .ready(path, readLevels) = r, let record = takeover else {
            if case let .notReady(why) = r, why != .busy { refusal = DeskRefusal(reason: why, automatic: false, restore: true) }
            return (r, [.log("console not restored (\(r))")])
        }
        var current: [DeskChannel: Int]?
        if reading == .ok {
            var c: [DeskChannel: Int] = [:]
            for ch in record.plan.channels { c[ch] = channelLevel(ch)?.value }
            current = c
        }
        let plan = DeskPlanner.restore(record, current: current)
        var a: [Action] = [.log("restoring the console: \(record.rows.count) row(s), fade \(record.fade) s, \(path == .rcp ? "RCP" : "OSC")")]
        a += begin(.restore, plan: plan, path: path, readLevels: readLevels, fade: record.fade, now: now)
        return (r, a)
    }

    /// The window's banner was closed.
    public mutating func dismiss() {
        if let m = move, !m.isRunning, m.check != .waiting { move = nil }
        refusal = nil
    }

    // MARK: State

    /// The level of a channel (a stereo input: its L half) and when it was read.
    public func channelLevel(_ ch: DeskChannel) -> Level? {
        guard let first = ch.addresses.first else { return nil }
        return levels[first]
    }

    /// Every parameter of the channel was read less than 2 s ago.
    public func isFresh(_ ch: DeskChannel, now: Double) -> Bool {
        ch.addresses.allSatisfy { a in levels[a].map { now - $0.at < Self.freshFor } ?? false }
    }

    public func status(now: Double) -> DeskStatus {
        switch connection {
        case .up:
            switch reading {
            case .unknown: return .checking
            case .ok: return validMainChannels.allSatisfy { isFresh($0, now: now) } ? .reading : .stale
            case .unsupported: return settings.useFixedLevels ? .fixedLevels(unconfirmed: false) : .cannotRead
            }
        case let .connecting(attempt, _) where attempt == 1 && !refusedLastTime:
            return .connecting
        case .stopped:
            return .notReachable
        case .connecting, .waiting:
            if refusedLastTime, settings.model.supportsOSC, settings.useFixedLevels { return .fixedLevels(unconfirmed: true) }
            return .notReachable
        }
    }

    /// Whether a takeover could start now, and how.
    public func readiness(now: Double, automatic: Bool) -> DeskReadiness {
        if !settings.enabled { return .notReady(.off) }
        if settings.rows.isEmpty { return .notReady(.noRows) }
        if !settings.problems.isEmpty { return .notReady(.invalidRows) }
        if move?.isRunning == true { return .notReady(.busy) }
        if takeover != nil { return .notReady(.alreadyMoved) }
        switch status(now: now) {
        case .reading: return .ready(.rcp, readLevels: true)
        case .stale: return .notReady(.stale)
        case .checking: return .notReady(.checking)
        case .connecting, .notReachable: return .notReady(.notConnected)
        case .cannotRead: return .notReady(.unreadable)
        case let .fixedLevels(unconfirmed):
            if automatic && unconfirmed { return .notReady(.notConnected) }
            return .ready(settings.model.supportsOSC ? .osc : .rcp, readLevels: false)
        }
    }

    public func restoreReadiness(now: Double) -> DeskReadiness {
        if takeover == nil { return .notReady(.nothingToRestore) }
        if move?.isRunning == true { return .notReady(.busy) }
        if case .up = connection {
            if reading == .ok { return .ready(.rcp, readLevels: true) }
            return .ready(settings.model.supportsOSC ? .osc : .rcp, readLevels: false)
        }
        if refusedLastTime, settings.model.supportsOSC { return .ready(.osc, readLevels: false) }
        return .notReady(.notConnected)
    }

    public func snapshot(now: Double) -> DeskSnapshot {
        var lv: [DeskChannel: Int] = [:]
        var fresh: Set<DeskChannel> = []
        for r in settings.rows {
            for ch in [r.main, r.backup] {
                if let l = channelLevel(ch) { lv[ch] = l.value }
                if isFresh(ch, now: now) { fresh.insert(ch) }
            }
        }
        let summary = move.map { m in
            DeskMoveSummary(kind: m.kind, fade: m.fade, running: m.isRunning, path: m.path, readLevels: m.readLevels,
                            rows: takeover?.rows.count ?? settings.rows.count, check: m.check)
        }
        return DeskSnapshot(model: settings.model, status: status(now: now), readiness: readiness(now: now, automatic: false),
                            levels: lv, fresh: fresh, move: summary, refusal: refusal,
                            canRestore: takeover != nil && move?.isRunning != true,
                            needsLink: takeover != nil || move != nil || refusal != nil)
    }

    // MARK: Internals

    /// Rows' channels the model has (out-of-range numbers are never sent).
    private var validRows: [DeskRow] {
        settings.rows.filter { r in
            let limit = settings.model.channelLimit(r.kind)
            return (1...max(1, limit)).contains(r.mainChannel) && (1...max(1, limit)).contains(r.backupChannel) && limit > 0
        }
    }

    private var validMainChannels: [DeskChannel] { validRows.map(\.main) }

    private var mainAddresses: [FaderAddress] {
        let a = validRows.flatMap(\.main.addresses)
        return a.isEmpty ? [FaderAddress(.input, x: 0)] : a
    }

    /// Main channels first, input channels before stereo inputs (the first answer decides
    /// whether levels can be read, and every model has input channels).
    private var allAddresses: [FaderAddress] {
        var seen = Set<FaderAddress>()
        let all = (mainAddresses + validRows.flatMap(\.backup.addresses)).filter { seen.insert($0).inserted }
        return all.filter { $0.kind == .input } + all.filter { $0.kind == .stereoIn }
    }

    private mutating func gets(_ addresses: [FaderAddress], now: Double) -> [Action] {
        var a: [Action] = []
        for addr in addresses where !pending.contains(where: { !$0.isSet && $0.address == addr }) {
            pending.append(Pending(isSet: false, address: addr, sentAt: now))
            a.append(.send(DeskRCP.get(addr)))
        }
        return a
    }

    @discardableResult
    private mutating func removePending(isSet: Bool, address: FaderAddress) -> Pending? {
        guard let i = pending.firstIndex(where: { $0.isSet == isSet && $0.address == address }) else { return nil }
        return pending.remove(at: i)
    }

    /// An answer to a `get` asked after the move (an older poll's answer does not count).
    private mutating func noteReadBack(_ p: Pending?, value: Int?) {
        guard let p, var m = move, let sent = m.verifySentAt, p.sentAt >= sent, m.waiting.contains(p.address) else { return }
        m.waiting.remove(p.address)
        if let value { m.readBack[p.address] = value }
        move = m
    }

    /// Answers come in the order the questions went out: an ERROR answers the oldest one.
    private mutating func popPending(isSet: Bool) -> Pending? {
        guard let i = pending.firstIndex(where: { $0.isSet == isSet }) else { return nil }
        return pending.remove(at: i)
    }

    private mutating func begin(_ kind: DeskMoveState.Kind, plan: DeskPlan, path: DeskWritePath, readLevels: Bool,
                                fade: Double, now: Double) -> [Action] {
        move = DeskMoveState(kind: kind, path: path, fade: fade, readLevels: readLevels, plan: plan, startedAt: now)
        refusal = nil
        return runMove(now: now)
    }

    /// Sends the steps that are due; after the last one, plans the read-back.
    private mutating func runMove(now: Double) -> [Action] {
        guard var m = move, m.isRunning else { return [] }
        var a: [Action] = []
        while m.nextStep < m.plan.steps.count, m.startedAt + m.plan.steps[m.nextStep].at <= now + 1e-9 {
            a += writes(m.plan.steps[m.nextStep].writes, path: m.path, now: now)
            m.nextStep += 1
        }
        if m.nextStep >= m.plan.steps.count {
            m.finishedAt = now
            if m.path == .osc { m.check = .notPossible }
            if m.kind == .restore { takeover = nil }
            a.append(.log(m.kind == .takeover ? "console switched" : "console restored"))
        }
        move = m
        return a
    }

    private mutating func writes(_ ws: [DeskWrite], path: DeskWritePath, now: Double) -> [Action] {
        var a: [Action] = []
        for w in ws {
            switch path {
            case .rcp:
                for addr in w.channel.addresses {
                    pending.append(Pending(isSet: true, address: addr, sentAt: now))
                    a.append(.send(DeskRCP.set(addr, w.value)))
                }
            case .osc:
                a += DeskYamahaOSC.messages(w.channel, value: w.value, model: settings.model).map { .sendOSC($0) }
            }
        }
        return a
    }

    /// After an RCP move: read the touched channels back and compare.
    private mutating func checkVerification(now: Double) -> [Action] {
        guard var m = move, let done = m.finishedAt, m.check == .waiting, m.path == .rcp else { return [] }
        guard let sent = m.verifySentAt else {
            guard now >= done + Self.verifyDelay else { return [] }
            guard reading == .ok, case .up = connection else {
                // Nothing to read back: only the console's refusals are known.
                m.check = m.refused.isEmpty ? .notPossible
                    : .mismatches(m.refused.sorted().map { DeskMismatch(channel: $0, expected: m.plan.targets[$0] ?? 0, problem: .refused) })
                move = m
                return []
            }
            let addrs = m.plan.channels.flatMap(\.addresses)
            m.verifySentAt = now
            m.waiting = Set(addrs)
            move = m
            // Asked again even when a poll is on its way: only answers to these count.
            var a: [Action] = []
            for addr in addrs {
                pending.append(Pending(isSet: false, address: addr, sentAt: now))
                a.append(.send(DeskRCP.get(addr)))
            }
            return a
        }
        guard m.waiting.isEmpty || now - sent >= Self.verifyTimeout else { return [] }
        let targets = m.plan.targets
        var mismatches: [DeskMismatch] = []
        for ch in targets.keys.sorted() {
            let expected = targets[ch] ?? 0
            var problem: DeskMismatch.Problem?
            for addr in ch.addresses {
                guard let v = m.readBack[addr] else { problem = m.refused.contains(ch) ? .refused : .noAnswer; break }
                if !Self.matches(v, expected) { problem = .level(v); break }
            }
            if let problem { mismatches.append(DeskMismatch(channel: ch, expected: expected, problem: problem)) }
        }
        m.check = mismatches.isEmpty ? .ok : .mismatches(mismatches)
        move = m
        return [.log(mismatches.isEmpty ? "read back: every level as planned" : "read back: \(mismatches.count) channel(s) differ")]
    }

    /// Within 1 dB, or both exactly −∞.
    public static func matches(_ actual: Int, _ expected: Int) -> Bool {
        let inf = DeskLevel.minusInfinity
        if expected <= inf || actual <= inf { return expected <= inf && actual <= inf }
        return abs(actual - expected) <= tolerance
    }
}

extension DeskChannel: CustomStringConvertible {
    public var description: String { kind == .input ? "Ch \(number)" : "ST IN \(number)" }
}
