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

/// One line of the channel table: the channels that carry the same sound on the two Macs.
///
/// Written by Mac, not by role (either Mac can be the main): `channels` is keyed by each Mac's
/// TwinKeys ID (`AppSettings.instanceID`). Before the other Mac is known the key
/// `DeskSettings.otherMacKey` stands for it (and `thisMacKey` for this Mac in rows read from the
/// first 2.4 builds); `DeskSettings.normalize` replaces them.
public struct DeskRow: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: DeskChannelKind
    /// 1-based, as on the console. A missing Mac: not entered yet.
    public var channels: [String: Int]
    /// Level a channel is raised to when levels cannot be read (dB × 100). Default 0 dB.
    public var fixedLevel: Int
    /// The person's own name for the row ("Music L"). May be empty.
    public var name: String

    public init(id: UUID = UUID(), kind: DeskChannelKind = .input, channels: [String: Int],
                fixedLevel: Int = 0, name: String = "") {
        self.id = id; self.kind = kind; self.channels = channels
        self.fixedLevel = fixedLevel; self.name = name
    }

    /// The row as Mac `me` uses it with the other Mac `other`.
    public func route(me: String, other: String) -> DeskRoute {
        DeskRoute(kind: kind, other: channels[other] ?? 0, own: channels[me] ?? 0, fixedLevel: fixedLevel, name: name)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, channels
        case fixedLevel = "fixed_level"
        // The first 2.4 builds wrote the table by role (on the backup Mac).
        case mainChannel = "main_channel"
        case backupChannel = "backup_channel"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(DeskChannelKind.self, forKey: .kind)) ?? .input
        if let ch = try? c.decode([String: Int].self, forKey: .channels) {
            channels = ch
        } else {
            // Role-based rows were only ever used on the receiving Mac, where "main" was the other
            // Mac (also after that Mac had become the main by a takeover): main → the other Mac,
            // backup → this Mac.
            let m = try c.decode(Int.self, forKey: .mainChannel)
            let b = try c.decode(Int.self, forKey: .backupChannel)
            channels = [DeskSettings.otherMacKey: m, DeskSettings.thisMacKey: b]
        }
        fixedLevel = DeskLevel.clamped((try? c.decodeIfPresent(Int.self, forKey: .fixedLevel)) ?? 0)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(channels, forKey: .channels)
        try c.encode(fixedLevel, forKey: .fixedLevel)
        try c.encode(name, forKey: .name)
    }
}

/// A row as one Mac uses it. When the other Mac stops, its channel goes to −∞ and this Mac's
/// channel rises to the level the other one had. The same table works both ways: on the other
/// Mac the two channels swap places.
public struct DeskRoute: Equatable, Hashable, Sendable {
    public var kind: DeskChannelKind
    /// The other Mac's channel (0: not entered).
    public var otherChannel: Int
    /// This Mac's channel (0: not entered).
    public var ownChannel: Int
    /// Level this Mac's channel is raised to when levels cannot be read (dB × 100).
    public var fixedLevel: Int
    public var name: String

    public init(kind: DeskChannelKind = .input, other: Int, own: Int, fixedLevel: Int = 0, name: String = "") {
        self.kind = kind; self.otherChannel = other; self.ownChannel = own; self.fixedLevel = fixedLevel; self.name = name
    }

    public var other: DeskChannel { DeskChannel(kind, otherChannel) }
    public var own: DeskChannel { DeskChannel(kind, ownChannel) }

    /// Problems of a table for `model` (empty: usable). Rows are counted from 1.
    public static func problems(_ routes: [DeskRoute], model: DeskModel) -> [DeskRowProblem] {
        var out: [DeskRowProblem] = []
        var seen: Set<DeskChannel> = []
        var twice: [DeskChannel] = []
        for (i, r) in routes.enumerated() {
            let n = i + 1
            if r.kind == .stereoIn && !model.hasStereoIn {
                out.append(.noStereoIn(row: n))
                continue
            }
            if r.otherChannel == 0 || r.ownChannel == 0 {
                out.append(.channelMissing(row: n))
                continue
            }
            let limit = model.channelLimit(r.kind)
            for ch in [r.own, r.other] where ch.number < 1 || ch.number > limit {
                out.append(.channelOutOfRange(row: n, channel: ch, limit: limit))
            }
            if r.otherChannel == r.ownChannel { out.append(.sameChannel(row: n)) }
            if r.fixedLevel <= DeskLevel.minusInfinity { out.append(.fixedLevelMinusInfinity(row: n)) }
            for ch in Set([r.own, r.other]) {
                if seen.contains(ch), !twice.contains(ch) { twice.append(ch) }
                seen.insert(ch)
            }
        }
        return out + twice.sorted().map { .usedTwice($0) }
    }
}

/// Why a channel table cannot be used with a model. Rows are counted from 1.
public enum DeskRowProblem: Equatable, Hashable, Sendable {
    case channelOutOfRange(row: Int, channel: DeskChannel, limit: Int)
    case noStereoIn(row: Int)
    /// One of the two Macs has no channel in this row yet.
    case channelMissing(row: Int)
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

/// Settings > Console (Yamaha). Stored in settings.json under "desk". Everything but
/// `moveDeskWhenConfirming` is the same on both Macs: a change on one is sent to the other
/// (`DeskShare`), and the newest `revision` wins.
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
    /// When levels cannot be read, raise the channels to each row's fixed level.
    public var useFixedLevels = true
    /// Names of the two Macs (key: TwinKeys ID), for the column titles while the other Mac is away.
    public var macNames: [String: String] = [:]
    /// When the shared settings last changed (wall clock, ms). 0: never changed (never sent over
    /// a newer one).
    public var revision: UInt64 = 0
    /// This Mac only: the last answer to "Also switch the console's faders" in the confirmation
    /// (also used when an iPhone makes this Mac the main).
    public var moveDeskWhenConfirming = true

    public static let fades: [Double] = [0, 0.5, 1, 2]
    public static let maxRows = 64
    /// Stands for the other Mac before it is known.
    public static let otherMacKey = "other-mac"
    /// Stands for this Mac in rows read from the first 2.4 builds (replaced at once on loading).
    public static let thisMacKey = "this-mac"
    /// Longest row name kept (and sent to the other Mac), in UTF-8 bytes.
    public static let maxNameBytes = 40
    /// Longest address sent to the other Mac ("255.255.255.255").
    public static let maxHostBytes = 15

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, model, host, rows, trigger, fade, revision
        case pullMainToMinusInfinity = "pull_main_to_minus_infinity"
        case useFixedLevels = "use_fixed_levels"
        case moveDeskWhenConfirming = "move_desk_when_confirming"
        case macNames = "mac_names"
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
        macNames = (try? c.decodeIfPresent([String: String].self, forKey: .macNames)) ?? [:]
        if let rev = try? c.decodeIfPresent(UInt64.self, forKey: .revision) {
            revision = rev
        } else {
            // Saved before revisions existed: anything set by hand beats a Mac that never set it.
            revision = sameShared(as: d) ? 0 : 1
        }
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

    // MARK: The two Macs

    /// The key the other Mac's channels are stored under: a real TwinKeys ID when one is in the
    /// table, else `otherMacKey`.
    public func otherMac(me: String) -> String {
        var count: [String: Int] = [:]
        for r in rows { for k in r.channels.keys where k != me && k != Self.thisMacKey && k != Self.otherMacKey { count[k, default: 0] += 1 } }
        for k in macNames.keys where k != me && k != Self.thisMacKey && k != Self.otherMacKey { count[k, default: 0] += 0 }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key ?? Self.otherMacKey
    }

    /// The table as Mac `me` uses it with the other Mac `other`.
    public func routes(me: String, other: String) -> [DeskRoute] {
        rows.map { $0.route(me: me, other: other) }
    }

    public func problems(me: String, other: String) -> [DeskRowProblem] {
        DeskRoute.problems(routes(me: me, other: other), model: model)
    }

    /// Keeps only two Macs in the table: `me` and the other Mac (`other`; nil: the one already
    /// in the table). Placeholders become the real IDs. A row keyed by a Mac that is neither (the
    /// other Mac was replaced, or this Mac got a new ID) moves to the free side, the other Mac
    /// first: the table follows the Mac this one is linked to. Names are kept or set.
    public mutating func normalize(me: String, other: String? = nil, myName: String? = nil, otherName: String? = nil) {
        let target = other ?? otherMac(me: me)
        for i in rows.indices {
            let ch = rows[i].channels
            var out: [String: Int] = [:]
            if let v = ch[me] ?? ch[Self.thisMacKey] { out[me] = v }
            if let v = ch[target] { out[target] = v }
            let foreign = ch.filter { $0.key != me && $0.key != target && $0.key != Self.thisMacKey }
                .sorted { ($0.key == Self.otherMacKey ? 0 : 1, $0.key) < ($1.key == Self.otherMacKey ? 0 : 1, $1.key) }
            for (_, v) in foreign {
                if out[target] == nil { out[target] = v } else if out[me] == nil { out[me] = v }
            }
            rows[i].channels = out
        }
        var names: [String: String] = [:]
        if let n = myName ?? macNames[me] ?? macNames[Self.thisMacKey] { names[me] = n }
        if let n = otherName ?? macNames[target] { names[target] = n }
        macNames = names
    }

    public func normalized(me: String, other: String? = nil) -> DeskSettings {
        var c = self
        c.normalize(me: me, other: other)
        return c
    }

    // MARK: Sharing

    /// The same shared settings (everything the other Mac gets; row IDs, names of the Macs,
    /// the revision and `moveDeskWhenConfirming` do not count).
    public func sameShared(as o: DeskSettings) -> Bool {
        guard enabled == o.enabled, model == o.model, host == o.host, trigger == o.trigger, fade == o.fade,
              pullMainToMinusInfinity == o.pullMainToMinusInfinity, useFixedLevels == o.useFixedLevels,
              rows.count == o.rows.count else { return false }
        return zip(rows, o.rows).allSatisfy { a, b in
            a.kind == b.kind && a.channels == b.channels && a.fixedLevel == b.fixedLevel && a.name == b.name
        }
    }

    /// A change made on this Mac: newer than anything before (wall clock in ms, as role claims).
    public mutating func markChanged(nowMillis: UInt64) {
        revision = max(nowMillis, revision + 1)
    }

    /// FNV-1a over the shared settings as both Macs see them (the two Macs' channels in the
    /// order of their IDs, names and the address cut as they are sent), so both get the same value.
    public func shareHash(me: String, peer: String) -> UInt32 {
        let n = normalized(me: me, other: peer)
        let (lo, hi) = me < peer ? (me, peer) : (peer, me)
        var h: UInt32 = 2_166_136_261
        func add(_ bytes: some Sequence<UInt8>) { for b in bytes { h = (h ^ UInt32(b)) &* 16_777_619 } }
        add([n.flags, n.model.wireCode, n.fadeTenths])
        add(truncatedUTF8(n.host, max: Self.maxHostBytes)); add([0x1F])
        for r in n.rows {
            let f = UInt16(bitPattern: Int16(clamping: r.fixedLevel))
            add([r.kind == .input ? 0 : 1, UInt8(clamping: r.channels[lo] ?? 0), UInt8(clamping: r.channels[hi] ?? 0),
                 UInt8(f >> 8), UInt8(f & 0xFF)])
            add(truncatedUTF8(r.name, max: Self.maxNameBytes)); add([0x1F])
        }
        return h
    }

    /// bit 0 enabled, bit 1 automatic, bit 2 pull the main channels to −∞, bit 3 raise to set levels.
    var flags: UInt8 {
        (enabled ? 1 : 0) | (trigger == .automatic ? 2 : 0) | (pullMainToMinusInfinity ? 4 : 0) | (useFixedLevels ? 8 : 0)
    }

    var fadeTenths: UInt8 { UInt8(clamping: Int((fade * 10).rounded())) }

    /// A new row on the first free channels (this Mac, then the next free one for the other Mac).
    public func newRow(me: String, other: String) -> DeskRow? {
        guard rows.count < Self.maxRows else { return nil }
        let kind: DeskChannelKind = .input
        let used = Set(rows.filter { $0.kind == kind }.flatMap { [$0.channels[me], $0.channels[other]].compactMap { $0 } })
        let limit = model.channelLimit(kind)
        let free = (1...max(1, limit)).filter { !used.contains($0) }
        guard free.count >= 2 else { return nil }
        return DeskRow(kind: kind, channels: [me: free[0], other: free[1]])
    }
}

extension DeskModel {
    /// The model's number in packets between the Macs (never reordered).
    public var wireCode: UInt8 {
        switch self {
        case .ql1: return 0
        case .ql5: return 1
        case .dm3: return 2
        case .dm7: return 3
        case .dm7Compact: return 4
        case .dm5: return 5
        case .dm5Compact: return 6
        }
    }

    public init?(wireCode: UInt8) {
        guard let m = DeskModel.allCases.first(where: { $0.wireCode == wireCode }) else { return nil }
        self = m
    }
}
