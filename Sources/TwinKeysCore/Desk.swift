import Foundation

// 2.4 (experimental): when the main Mac fails, the backup Mac moves the faders of a Yamaha
// console (docs/design-v2.4-ql.md). Only fader levels are ever written: never EQ, dynamics,
// routing, scenes or channel ON.

/// The Yamaha consoles TwinKeys can move faders on. Channel counts from Yamaha's spec pages.
public enum DeskModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case ql1, ql5
    /// DM3 and DM3 Standard (the same channels and commands).
    case dm3
    case dm7
    case dm7Compact = "dm7_compact"
    case dm5
    case dm5Compact = "dm5_compact"

    public var id: String { rawValue }

    /// As in the model menu.
    public var displayName: String {
        switch self {
        case .ql1: return "QL1"
        case .ql5: return "QL5"
        case .dm3: return "DM3 / DM3 Standard"
        case .dm7: return "DM7"
        case .dm7Compact: return "DM7 Compact"
        case .dm5: return "DM5"
        case .dm5Compact: return "DM5 Compact"
        }
    }

    /// Short name for the status line, the connection row and the confirmation ("DM3").
    public var shortName: String { self == .dm3 ? "DM3" : displayName }

    /// Input channels (InCh), numbered from 1 as on the console.
    public var inputChannels: Int {
        switch self {
        case .ql1: return 32
        case .ql5: return 64
        case .dm3: return 16
        case .dm7: return 120
        case .dm7Compact: return 72
        case .dm5: return 60
        case .dm5Compact: return 48
        }
    }

    /// Stereo input channels (ST IN). DM7 and DM5 have none.
    public var stereoInChannels: Int {
        switch self {
        case .ql1, .ql5: return 8
        case .dm3: return 1
        case .dm7, .dm7Compact, .dm5, .dm5Compact: return 0
        }
    }

    public var hasStereoIn: Bool { stereoInChannels > 0 }

    /// Yamaha documents fader writes over OSC (UDP 49900) for the DM families. QL has no OSC.
    public var supportsOSC: Bool {
        switch self {
        case .ql1, .ql5: return false
        case .dm3, .dm7, .dm7Compact, .dm5, .dm5Compact: return true
        }
    }

    /// Reading levels over RCP is reported to work on this family (unofficial reports: QL5, DM7,
    /// DM7 Compact; QL1 and DM3 are expected to behave the same). False: nobody has tried yet (DM5).
    public var readVerified: Bool {
        switch self {
        case .dm5, .dm5Compact: return false
        default: return true
        }
    }

    /// DM3's OSC examples carry a Y index after the channel ("…/Level/1/1"); DM7's and DM5's do not.
    public var oscUsesYIndex: Bool { self == .dm3 }

    /// Highest channel number (1-based) for a kind of channel; 0 when the model has none.
    public func channelLimit(_ kind: DeskChannelKind) -> Int {
        kind == .input ? inputChannels : stereoInChannels
    }
}

public enum DeskChannelKind: String, Codable, CaseIterable, Sendable {
    case input
    case stereoIn = "stereo_in"
}

/// A console channel as people see it: an input channel or a stereo input, numbered from 1.
public struct DeskChannel: Hashable, Codable, Sendable, Comparable {
    public var kind: DeskChannelKind
    public var number: Int
    public init(_ kind: DeskChannelKind, _ number: Int) { self.kind = kind; self.number = number }

    /// The RCP parameters behind it: one for an input channel, L and R for a stereo input
    /// (both halves are always written together).
    public var addresses: [FaderAddress] {
        switch kind {
        case .input: return [FaderAddress(.input, x: number - 1)]
        case .stereoIn: return [FaderAddress(.stereoIn, x: 2 * (number - 1)), FaderAddress(.stereoIn, x: 2 * (number - 1) + 1)]
        }
    }

    public static func < (a: DeskChannel, b: DeskChannel) -> Bool {
        a.kind == b.kind ? a.number < b.number : a.kind == .input
    }
}

/// One RCP fader parameter: `MIXER:Current/InCh/Fader/Level x 0`, or one half of a stereo input
/// (`MIXER:Current/StInCh/Fader/Level x 0`, x = 2n for L and 2n+1 for R, n from 0).
public struct FaderAddress: Hashable, Sendable {
    public var kind: DeskChannelKind
    /// X as RCP counts it (from 0).
    public var x: Int
    public init(_ kind: DeskChannelKind, x: Int) { self.kind = kind; self.x = x }

    /// The channel this parameter belongs to.
    public var channel: DeskChannel {
        kind == .input ? DeskChannel(.input, x + 1) : DeskChannel(.stereoIn, x / 2 + 1)
    }
}

/// Fader levels as Yamaha's commands carry them: dB × 100, −32768 for −∞.
public enum DeskLevel {
    public static let minusInfinity = -32768
    /// −138 dB, the lowest finite level.
    public static let lowest = -13800
    /// +10 dB.
    public static let highest = 1000

    /// −∞ stays −∞; anything else is kept between −138 dB and +10 dB.
    public static func clamped(_ v: Int) -> Int {
        if v <= minusInfinity { return minusInfinity }
        return min(highest, max(lowest, v))
    }

    /// "-6.0 dB", "+2.5 dB", "0.0 dB", "-∞ dB".
    public static func text(_ v: Int) -> String {
        v <= minusInfinity ? "-∞ dB" : number(v) + " dB"
    }

    /// The number alone, one decimal ("-6.0", "+10.0"); "-∞" for −∞.
    public static func number(_ v: Int) -> String {
        if v <= minusInfinity { return "-∞" }
        let tenths = Int((Double(v) / 10).rounded())
        let sign = tenths < 0 ? "-" : tenths > 0 ? "+" : ""
        let a = abs(tenths)
        return "\(sign)\(a / 10).\(a % 10)"
    }

    /// Reads a typed level in dB ("-6", "-6.0 dB", "−6,5", "+3", "-inf", "-∞").
    /// Returns dB × 100, clamped, or nil when it is not a number.
    public static func parse(_ raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        s = s.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: ",", with: ".")
        if s.hasSuffix("db") { s = String(s.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        if ["-inf", "-∞", "inf", "∞"].contains(s) { return minusInfinity }
        guard !s.isEmpty, let d = Double(s), d.isFinite else { return nil }
        return clamped(Int((d * 100).rounded()))
    }
}

/// How far up a fader is (0 at the bottom, 1 at the top), so fades move evenly along the fader
/// instead of evenly in dB (which would spend most of the time near the bottom).
///
/// Piecewise linear, close to a console's fader scale:
///   +10 … −10 dB → 1.0 … 0.6
///   −10 … −40 dB → 0.6 … 0.2
///   −40 … −138 dB → 0.2 … 0.0
///   −∞ → 0
/// Levels from positions are rounded to whole dB × 100 and never leave −138 … +10 dB, except −∞
/// (position 0).
public enum FaderTaper {
    private static let points: [(level: Double, position: Double)] = [(1000, 1.0), (-1000, 0.6), (-4000, 0.2), (-13800, 0.0)]

    public static func position(_ level: Int) -> Double {
        if level <= DeskLevel.minusInfinity { return 0 }
        let v = Double(DeskLevel.clamped(level))
        for i in 0..<(points.count - 1) {
            let hi = points[i], lo = points[i + 1]
            if v >= lo.level {
                return lo.position + (v - lo.level) / (hi.level - lo.level) * (hi.position - lo.position)
            }
        }
        return 0
    }

    public static func level(atPosition p: Double) -> Int {
        guard p.isFinite, p > 0 else { return DeskLevel.minusInfinity }
        if p >= 1 { return DeskLevel.highest }
        for i in 0..<(points.count - 1) {
            let hi = points[i], lo = points[i + 1]
            if p >= lo.position {
                let v = lo.level + (p - lo.position) / (hi.position - lo.position) * (hi.level - lo.level)
                return DeskLevel.clamped(Int(v.rounded()))
            }
        }
        return DeskLevel.minusInfinity
    }

    /// The level `fraction` (0…1) of the way from `from` to `to`, moving evenly in fader position.
    /// The ends are exact: 0 gives `from`, 1 gives `to`.
    public static func interpolate(from: Int, to: Int, fraction f: Double) -> Int {
        if f >= 1 { return DeskLevel.clamped(to) }
        if f <= 0 { return DeskLevel.clamped(from) }
        let p0 = position(from), p1 = position(to)
        return level(atPosition: p0 + (p1 - p0) * f)
    }
}

/// One line of the channel table: the main Mac's channel and the backup Mac's channel that
/// carry the same sound.
public struct DeskRow: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: DeskChannelKind
    /// 1-based, as on the console.
    public var mainChannel: Int
    public var backupChannel: Int
    /// Level the backup channel is raised to when levels cannot be read (dB × 100). Default 0 dB.
    public var fixedLevel: Int
    /// The person's own name for the row ("Music L"). May be empty.
    public var name: String

    public init(id: UUID = UUID(), kind: DeskChannelKind = .input, mainChannel: Int, backupChannel: Int,
                fixedLevel: Int = 0, name: String = "") {
        self.id = id; self.kind = kind; self.mainChannel = mainChannel; self.backupChannel = backupChannel
        self.fixedLevel = fixedLevel; self.name = name
    }

    public var main: DeskChannel { DeskChannel(kind, mainChannel) }
    public var backup: DeskChannel { DeskChannel(kind, backupChannel) }

    enum CodingKeys: String, CodingKey {
        case id, kind, name
        case mainChannel = "main_channel"
        case backupChannel = "backup_channel"
        case fixedLevel = "fixed_level"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(DeskChannelKind.self, forKey: .kind)) ?? .input
        mainChannel = try c.decode(Int.self, forKey: .mainChannel)
        backupChannel = try c.decode(Int.self, forKey: .backupChannel)
        fixedLevel = DeskLevel.clamped((try? c.decodeIfPresent(Int.self, forKey: .fixedLevel)) ?? 0)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

/// Why a channel table cannot be used with a model. Rows are counted from 1.
public enum DeskRowProblem: Equatable, Hashable, Sendable {
    case channelOutOfRange(row: Int, channel: DeskChannel, limit: Int)
    case noStereoIn(row: Int)
    case sameChannel(row: Int)
    case usedTwice(DeskChannel)
    case fixedLevelMinusInfinity(row: Int)
}

/// How the takeover starts.
public enum DeskTrigger: String, Codable, CaseIterable, Sendable {
    /// With "Make this Mac the main" (on the Mac, or from an iPhone). The default.
    case confirm
    /// By itself when the main Mac has not answered for 3 seconds.
    case automatic
}

/// Settings > Console (Yamaha). Stored in settings.json under "desk".
public struct DeskSettings: Codable, Equatable, Sendable {
    /// The experimental feature is on. Off until the person turns it on.
    public var enabled = false
    public var model: DeskModel = .ql5
    /// The console's "For Mixer Control" IPv4 address.
    public var host = ""
    public var rows: [DeskRow] = []
    public var trigger: DeskTrigger = .confirm
    /// Seconds; one of `fades`.
    public var fade: Double = 0.5
    public var pullMainToMinusInfinity = true
    /// When levels cannot be read, raise the backup channels to each row's fixed level.
    public var useFixedLevels = true
    /// The last answer to "Also switch the console's faders" in the confirmation (also used when
    /// an iPhone makes this Mac the main).
    public var moveDeskWhenConfirming = true

    public static let fades: [Double] = [0, 0.5, 1, 2]
    public static let maxRows = 64

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, model, host, rows, trigger, fade
        case pullMainToMinusInfinity = "pull_main_to_minus_infinity"
        case useFixedLevels = "use_fixed_levels"
        case moveDeskWhenConfirming = "move_desk_when_confirming"
    }

    /// Missing or unreadable keys fall back to defaults; one bad row drops only that row.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeskSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        model = (try? c.decodeIfPresent(DeskModel.self, forKey: .model)) ?? d.model
        host = ((try? c.decodeIfPresent(String.self, forKey: .host)) ?? d.host).trimmingCharacters(in: .whitespaces)
        let r = (try? c.decodeIfPresent([Lenient<DeskRow>].self, forKey: .rows)) ?? []
        rows = Array(r.compactMap(\.value).prefix(Self.maxRows))
        trigger = (try? c.decodeIfPresent(DeskTrigger.self, forKey: .trigger)) ?? d.trigger
        fade = Self.nearestFade((try? c.decodeIfPresent(Double.self, forKey: .fade)) ?? d.fade)
        pullMainToMinusInfinity = (try? c.decodeIfPresent(Bool.self, forKey: .pullMainToMinusInfinity)) ?? d.pullMainToMinusInfinity
        useFixedLevels = (try? c.decodeIfPresent(Bool.self, forKey: .useFixedLevels)) ?? d.useFixedLevels
        moveDeskWhenConfirming = (try? c.decodeIfPresent(Bool.self, forKey: .moveDeskWhenConfirming)) ?? d.moveDeskWhenConfirming
    }

    /// One of the offered fade times (0, 0.5, 1, 2 s).
    public static func nearestFade(_ s: Double) -> Double {
        guard s.isFinite else { return 0.5 }
        return fades.min { abs($0 - s) < abs($1 - s) } ?? 0.5
    }

    /// A dotted IPv4 address ("192.168.0.128").
    public static func isValidHost(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            p.count >= 1 && p.count <= 3 && p.allSatisfy(\.isASCII) && p.allSatisfy(\.isNumber) && (Int(p) ?? 256) <= 255
        }
    }

    public var hasValidHost: Bool { Self.isValidHost(host) }

    /// Problems of the channel table for `model` (empty: usable).
    public static func problems(rows: [DeskRow], model: DeskModel) -> [DeskRowProblem] {
        var out: [DeskRowProblem] = []
        var seen: [DeskChannel: Int] = [:]
        var twice: [DeskChannel] = []
        for (i, r) in rows.enumerated() {
            let n = i + 1
            let limit = model.channelLimit(r.kind)
            if r.kind == .stereoIn && !model.hasStereoIn {
                out.append(.noStereoIn(row: n))
                continue
            }
            for ch in [r.main, r.backup] where ch.number < 1 || ch.number > limit {
                out.append(.channelOutOfRange(row: n, channel: ch, limit: limit))
            }
            if r.mainChannel == r.backupChannel { out.append(.sameChannel(row: n)) }
            if r.fixedLevel <= DeskLevel.minusInfinity { out.append(.fixedLevelMinusInfinity(row: n)) }
            for ch in Set([r.main, r.backup]) {
                if seen[ch] != nil, !twice.contains(ch) { twice.append(ch) }
                seen[ch] = n
            }
        }
        return out + twice.sorted().map { .usedTwice($0) }
    }

    public var problems: [DeskRowProblem] { Self.problems(rows: rows, model: model) }

    /// A new row on the first free channels (main, then the next free one for the backup).
    public func newRow() -> DeskRow? {
        guard rows.count < Self.maxRows else { return nil }
        let kind: DeskChannelKind = .input
        let used = Set(rows.filter { $0.kind == kind }.flatMap { [$0.mainChannel, $0.backupChannel] })
        let limit = model.channelLimit(kind)
        let free = (1...max(1, limit)).filter { !used.contains($0) }
        guard free.count >= 2 else { return nil }
        return DeskRow(kind: kind, mainChannel: free[0], backupChannel: free[1])
    }
}
