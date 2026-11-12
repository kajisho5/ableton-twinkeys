import Foundation

/// One fader level to write.
public struct DeskWrite: Equatable, Hashable, Sendable {
    public var channel: DeskChannel
    /// dB × 100 (−32768: −∞).
    public var value: Int
    public init(_ channel: DeskChannel, _ value: Int) { self.channel = channel; self.value = value }
}

/// Writes due `at` seconds after the move starts.
public struct DeskStep: Equatable, Sendable {
    public var at: Double
    public var writes: [DeskWrite]
    public init(at: Double, writes: [DeskWrite]) { self.at = at; self.writes = writes }
}

/// A timed list of fader writes. The last step holds the final level of every channel.
public struct DeskPlan: Equatable, Sendable {
    public var steps: [DeskStep]
    public init(steps: [DeskStep]) { self.steps = steps }

    public var duration: Double { steps.last?.at ?? 0 }

    /// Where each channel ends up.
    public var targets: [DeskChannel: Int] {
        var t: [DeskChannel: Int] = [:]
        for s in steps { for w in s.writes { t[w.channel] = w.value } }
        return t
    }

    public var channels: [DeskChannel] { targets.keys.sorted() }
}

/// One fader going from one level to another. `from == nil`: where it is now is not known, so
/// it is not faded: it gets its level once, at the end.
public struct DeskMove: Equatable, Sendable {
    public var channel: DeskChannel
    public var from: Int?
    public var to: Int
    public init(_ channel: DeskChannel, from: Int?, to: Int) { self.channel = channel; self.from = from; self.to = to }
}

/// What a takeover did, kept for "Restore the console".
public struct DeskTakeoverRecord: Equatable, Sendable {
    public var rows: [DeskRow]
    public var fade: Double
    public var pulledMain: Bool
    /// The levels were read from the console (false: each row's fixed level was used).
    public var levelsWereRead: Bool
    /// Main channels before: read, or the row's fixed level when levels could not be read.
    public var mainBefore: [DeskChannel: Int]
    /// Backup channels before, when they were read (missing: assumed down, −∞).
    public var backupBefore: [DeskChannel: Int]
    public var plan: DeskPlan
}

public enum DeskPlanError: Error, Equatable, Sendable {
    case noRows
    case invalidRows([DeskRowProblem])
    /// Levels are read, but this main channel has none.
    case missingLevel(DeskChannel)
}

/// Builds the fader moves for a takeover and for undoing it. Pure: the caller sends the writes.
public enum DeskPlanner {
    /// A write every 50 ms during a fade.
    public static let stepInterval = 0.05

    /// Fades every move together over `seconds` (0: all at once), evenly in fader position
    /// (`FaderTaper`). A step only carries the channels whose level changes; the last step
    /// carries every channel's final level.
    public static func fade(_ moves: [DeskMove], over seconds: Double) -> DeskPlan {
        guard !moves.isEmpty else { return DeskPlan(steps: []) }
        let s = seconds.isFinite ? max(0, seconds) : 0
        let n = max(1, Int((s / stepInterval).rounded()))
        var last: [DeskChannel: Int] = [:]
        for m in moves { if let f = m.from { last[m.channel] = DeskLevel.clamped(f) } }
        var steps: [DeskStep] = []
        for k in 1...n {
            let f = Double(k) / Double(n)
            var writes: [DeskWrite] = []
            for m in moves {
                let v: Int
                if k == n { v = DeskLevel.clamped(m.to) }
                else if let from = m.from { v = FaderTaper.interpolate(from: from, to: m.to, fraction: f) }
                else { continue }
                if k == n || last[m.channel] != v { writes.append(DeskWrite(m.channel, v)) }
                last[m.channel] = v
            }
            if !writes.isEmpty { steps.append(DeskStep(at: s * Double(k) / Double(n), writes: writes)) }
        }
        return DeskPlan(steps: steps)
    }

    /// Raises each backup channel to the level its main channel had (or to the row's fixed level
    /// when `mainLevels` is nil: levels could not be read) and, with `pullMainToMinusInfinity`,
    /// pulls the main channels to −∞ at the same time.
    ///
    /// `backupLevels`: the backup channels' levels now, when read (a missing one is assumed to be
    /// down at −∞, so it rises from the bottom). A main channel whose level is not known (not
    /// read) is not faded: it goes to −∞ at the end of the fade.
    public static func takeover(rows: [DeskRow], model: DeskModel, mainLevels: [DeskChannel: Int]?,
                                backupLevels: [DeskChannel: Int]?, fade seconds: Double,
                                pullMainToMinusInfinity: Bool) throws -> DeskTakeoverRecord {
        guard !rows.isEmpty else { throw DeskPlanError.noRows }
        let problems = DeskSettings.problems(rows: rows, model: model)
        guard problems.isEmpty else { throw DeskPlanError.invalidRows(problems) }
        var moves: [DeskMove] = []
        var mainBefore: [DeskChannel: Int] = [:]
        var backupBefore: [DeskChannel: Int] = [:]
        for r in rows {
            let target: Int
            if let mainLevels {
                guard let v = mainLevels[r.main] else { throw DeskPlanError.missingLevel(r.main) }
                target = DeskLevel.clamped(v)
            } else {
                target = DeskLevel.clamped(r.fixedLevel)
            }
            mainBefore[r.main] = target
            let backupNow = backupLevels?[r.backup].map(DeskLevel.clamped)
            if let b = backupNow { backupBefore[r.backup] = b }
            moves.append(DeskMove(r.backup, from: backupNow ?? DeskLevel.minusInfinity, to: target))
            if pullMainToMinusInfinity {
                moves.append(DeskMove(r.main, from: mainLevels == nil ? nil : target, to: DeskLevel.minusInfinity))
            }
        }
        let fade = DeskSettings.nearestFade(seconds)
        return DeskTakeoverRecord(rows: rows, fade: fade, pulledMain: pullMainToMinusInfinity,
                                  levelsWereRead: mainLevels != nil, mainBefore: mainBefore,
                                  backupBefore: backupBefore, plan: Self.fade(moves, over: fade))
    }

    /// Undoes a takeover with the same fade: backup channels back to their level before (−∞ when
    /// it was not read), main channels (if they were pulled) back to theirs (the fixed level when
    /// levels could not be read). `current`: levels read now (the fades start from them);
    /// without one a channel starts from where the takeover left it.
    public static func restore(_ record: DeskTakeoverRecord, current: [DeskChannel: Int]?) -> DeskPlan {
        let after = record.plan.targets
        var moves: [DeskMove] = []
        for r in record.rows {
            let backupFrom = current?[r.backup] ?? after[r.backup]
            moves.append(DeskMove(r.backup, from: backupFrom, to: record.backupBefore[r.backup] ?? DeskLevel.minusInfinity))
            if record.pulledMain {
                let mainFrom = current?[r.main] ?? after[r.main]
                moves.append(DeskMove(r.main, from: mainFrom, to: record.mainBefore[r.main] ?? DeskLevel.clamped(r.fixedLevel)))
            }
        }
        return fade(moves, over: record.fade)
    }
}
