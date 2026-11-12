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
    public var rows: [DeskRoute]
    public var fade: Double
    /// The other Mac's channels were pulled to −∞.
    public var pulledOther: Bool
    /// The levels were read from the console (false: each row's fixed level was used).
    public var levelsWereRead: Bool
    /// The other Mac's channels before: read, or the row's fixed level when levels could not be read.
    public var otherBefore: [DeskChannel: Int]
    /// This Mac's channels before, when they were read (missing: assumed down, −∞).
    public var ownBefore: [DeskChannel: Int]
    public var plan: DeskPlan
}

public enum DeskPlanError: Error, Equatable, Sendable {
    case noRows
    case invalidRows([DeskRowProblem])
    /// Levels are read, but this channel of the other Mac has none.
    case missingLevel(DeskChannel)
}

/// Builds the fader moves for a takeover and for undoing it. Pure: the caller sends the writes.
///
/// A takeover always runs on the Mac that is still running: the other Mac (the main) stopped.
/// Its channels go to −∞; this Mac's channels rise to the level the other Mac's had.
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

    /// Raises each of this Mac's channels to the level the other Mac's channel had (or to the
    /// row's fixed level when `otherLevels` is nil: levels could not be read) and, with
    /// `pullOtherToMinusInfinity`, pulls the other Mac's channels to −∞ at the same time.
    ///
    /// `ownLevels`: this Mac's channels now, when read (a missing one is assumed to be down at
    /// −∞, so it rises from the bottom). An other-Mac channel whose level is not known (not read)
    /// is not faded: it goes to −∞ at the end of the fade.
    public static func takeover(rows: [DeskRoute], model: DeskModel, otherLevels: [DeskChannel: Int]?,
                                ownLevels: [DeskChannel: Int]?, fade seconds: Double,
                                pullOtherToMinusInfinity: Bool) throws -> DeskTakeoverRecord {
        guard !rows.isEmpty else { throw DeskPlanError.noRows }
        let problems = DeskRoute.problems(rows, model: model)
        guard problems.isEmpty else { throw DeskPlanError.invalidRows(problems) }
        var moves: [DeskMove] = []
        var otherBefore: [DeskChannel: Int] = [:]
        var ownBefore: [DeskChannel: Int] = [:]
        for r in rows {
            let target: Int
            if let otherLevels {
                guard let v = otherLevels[r.other] else { throw DeskPlanError.missingLevel(r.other) }
                target = DeskLevel.clamped(v)
            } else {
                target = DeskLevel.clamped(r.fixedLevel)
            }
            otherBefore[r.other] = target
            let ownNow = ownLevels?[r.own].map(DeskLevel.clamped)
            if let b = ownNow { ownBefore[r.own] = b }
            moves.append(DeskMove(r.own, from: ownNow ?? DeskLevel.minusInfinity, to: target))
            if pullOtherToMinusInfinity {
                moves.append(DeskMove(r.other, from: otherLevels == nil ? nil : target, to: DeskLevel.minusInfinity))
            }
        }
        let fade = DeskSettings.nearestFade(seconds)
        return DeskTakeoverRecord(rows: rows, fade: fade, pulledOther: pullOtherToMinusInfinity,
                                  levelsWereRead: otherLevels != nil, otherBefore: otherBefore,
                                  ownBefore: ownBefore, plan: Self.fade(moves, over: fade))
    }

    /// Undoes a takeover with the same fade: this Mac's channels back to their level before (−∞
    /// when it was not read), the other Mac's channels (if they were pulled) back to theirs (the
    /// fixed level when levels could not be read). `current`: levels read now (the fades start
    /// from them); without one a channel starts from where the takeover left it.
    public static func restore(_ record: DeskTakeoverRecord, current: [DeskChannel: Int]?) -> DeskPlan {
        let after = record.plan.targets
        var moves: [DeskMove] = []
        for r in record.rows {
            let ownFrom = current?[r.own] ?? after[r.own]
            moves.append(DeskMove(r.own, from: ownFrom, to: record.ownBefore[r.own] ?? DeskLevel.minusInfinity))
            if record.pulledOther {
                let otherFrom = current?[r.other] ?? after[r.other]
                moves.append(DeskMove(r.other, from: otherFrom, to: record.otherBefore[r.other] ?? DeskLevel.clamped(r.fixedLevel)))
            }
        }
        return fade(moves, over: record.fade)
    }
}
