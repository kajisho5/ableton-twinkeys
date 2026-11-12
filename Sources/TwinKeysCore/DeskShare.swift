import Foundation

// 2.4: the console settings are the same on both Macs (docs/design-v2.4-ql.md, しくみ 1). A change
// on either Mac is sent to the other over the Macs' encrypted link (packet type 0x22), and the
// newest revision wins. Each Mac also tells the other how its own console link is doing.

/// How a Mac's own console link is doing, as told to the other Mac.
public enum DeskPeerStatus: UInt8, Equatable, Sendable {
    /// The feature is off, no address is set, or the link does not run.
    case off = 0
    case notConnected = 1
    case checking = 2
    case reading = 3
    case stale = 4
    case fixedLevels = 5
    case cannotRead = 6

    /// `status`: the link's status, nil while it does not run.
    public init(_ status: DeskStatus?) {
        switch status {
        case nil: self = .off
        case .connecting?, .notReachable?: self = .notConnected
        case .checking?: self = .checking
        case .reading?: self = .reading
        case .stale?: self = .stale
        // Unconfirmed: the RCP port refused the connection, so it is not connected.
        case let .fixedLevels(unconfirmed)?: self = unconfirmed ? .notConnected : .fixedLevels
        case .cannotRead?: self = .cannotRead
        }
    }

    /// Connected to the console (whether or not levels can be read).
    public var isConnected: Bool {
        switch self {
        case .checking, .reading, .stale, .fixedLevels, .cannotRead: return true
        case .off, .notConnected: return false
        }
    }
}

/// The shared settings without the rows, as sent in the summary.
public struct DeskWireSummary: Equatable, Sendable {
    public var revision: UInt64
    /// `DeskSettings.shareHash` (both Macs compute the same value).
    public var hash: UInt32
    /// bit 0 enabled, bit 1 automatic, bit 2 pull the main channels to −∞, bit 3 raise to set levels.
    public var flags: UInt8
    /// `DeskModel.wireCode`.
    public var model: UInt8
    /// Tenths of a second (0, 5, 10, 20).
    public var fadeTenths: UInt8
    public var rowCount: UInt8
    /// The sender's own console link (`DeskPeerStatus`).
    public var status: UInt8
    /// At most 15 bytes.
    public var host: String
    public init(revision: UInt64, hash: UInt32, flags: UInt8, model: UInt8, fadeTenths: UInt8, rowCount: UInt8, status: UInt8, host: String) {
        self.revision = revision; self.hash = hash; self.flags = flags; self.model = model
        self.fadeTenths = fadeTenths; self.rowCount = rowCount; self.status = status; self.host = host
    }
}

/// One row as sent: the sender's channel and the receiver's (0: not entered).
public struct DeskWireRow: Equatable, Sendable {
    /// 0 input, 1 stereo input.
    public var kind: UInt8
    public var senderChannel: UInt8
    public var receiverChannel: UInt8
    /// dB × 100 (−32768: −∞).
    public var fixedLevel: Int16
    /// At most 40 bytes.
    public var name: String
    public init(kind: UInt8, senderChannel: UInt8, receiverChannel: UInt8, fixedLevel: Int16, name: String) {
        self.kind = kind; self.senderChannel = senderChannel; self.receiverChannel = receiverChannel
        self.fixedLevel = fixedLevel; self.name = name
    }
}

/// Packet type 0x22 (sealed like every packet after the handshake). Payload, big-endian:
///
///     0      kind: 0 summary, 1 row, 2 request
///     summary   1-8 revision u64 · 9-12 hash u32 · 13 flags · 14 model · 15 fade (tenths)
///               · 16 rows · 17 sender's console link · 18 host length n (≤ 15) · 19… host
///     row       1-8 revision u64 · 9 index · 10 kind · 11 sender's channel · 12 receiver's
///               channel · 13-14 fixed level i16 · 15 name length n (≤ 40) · 16… name (UTF-8)
///     request   1-8 revision u64 ("send me the rows of this revision")
///
/// The summary goes with every heartbeat (and at once when the settings or the console link
/// change); the rows go right after a change and when asked for. Older versions drop the
/// unknown type and stay linked.
public enum DeskPacket: Equatable, Sendable {
    case summary(DeskWireSummary)
    case row(revision: UInt64, index: UInt8, DeskWireRow)
    case request(revision: UInt64)

    func encoded() -> [UInt8] {
        var b: [UInt8] = []
        switch self {
        case let .summary(s):
            b.append(0); b.appendBE(s.revision); b.appendBE(s.hash)
            let host = Array(truncatedUTF8(s.host, max: DeskSettings.maxHostBytes))
            b += [s.flags, s.model, s.fadeTenths, s.rowCount, s.status, UInt8(host.count)] + host
        case let .row(rev, index, r):
            b.append(1); b.appendBE(rev)
            let f = UInt16(bitPattern: r.fixedLevel)
            let name = Array(truncatedUTF8(r.name, max: DeskSettings.maxNameBytes))
            b += [index, r.kind, r.senderChannel, r.receiverChannel, UInt8(f >> 8), UInt8(f & 0xFF), UInt8(name.count)] + name
        case let .request(rev):
            b.append(2); b.appendBE(rev)
        }
        return b
    }

    static func decode(_ p: [UInt8]) -> DeskPacket? {
        guard p.count >= 9 else { return nil }
        let rev = (UInt64(p.readBE32(at: 1)) << 32) | UInt64(p.readBE32(at: 5))
        switch p[0] {
        case 0:
            guard p.count >= 19 else { return nil }
            let n = Int(p[18])
            guard n <= DeskSettings.maxHostBytes, p.count >= 19 + n, p[16] <= DeskSettings.maxRows else { return nil }
            return .summary(DeskWireSummary(revision: rev, hash: p.readBE32(at: 9), flags: p[13], model: p[14], fadeTenths: p[15],
                                            rowCount: p[16], status: p[17], host: String(decoding: p[19..<(19 + n)], as: UTF8.self)))
        case 1:
            guard p.count >= 16, p[10] <= 1 else { return nil }
            let n = Int(p[15])
            guard n <= DeskSettings.maxNameBytes, p.count >= 16 + n else { return nil }
            let f = Int16(bitPattern: UInt16(p[13]) << 8 | UInt16(p[14]))
            return .row(revision: rev, index: p[9], DeskWireRow(kind: p[10], senderChannel: p[11], receiverChannel: p[12], fixedLevel: f,
                                                               name: String(decoding: p[16..<(16 + n)], as: UTF8.self)))
        case 2:
            return .request(revision: rev)
        default:
            return nil
        }
    }
}

/// The sharing of the console settings with the other Mac, without sockets (the Conductor sends
/// what this returns, under its lock).
///
/// - Each Mac sends its summary with every heartbeat. A summary with a newer revision (ties: the
///   higher TwinKeys ID) and other content starts collecting that revision's rows; when all have
///   arrived and their hash matches, the settings are taken over. A missing row is asked for
///   again (at most once a second). Revision 0 (never set) is never taken over.
/// - Taking settings over does not change their revision, so nothing is sent back and forth.
public struct DeskShare: Sendable {
    public private(set) var local = DeskSettings()
    public private(set) var localStatus: DeskPeerStatus = .off
    /// The other Mac's console link as it last told us (nil: not told since the link came up).
    public private(set) var peerStatus: DeskPeerStatus?
    private var incoming: Incoming?
    private var lastRequestAt = -Double.infinity
    public static let requestInterval = 1.0

    private struct Incoming: Equatable, Sendable {
        var revision: UInt64
        var summary: DeskWireSummary?
        var rows: [Int: DeskWireRow] = [:]
    }

    public init() {}

    /// This Mac's settings. True when the shared part changed (send it now).
    public mutating func setLocal(_ s: DeskSettings) -> Bool {
        let changed = s.revision != local.revision || !s.sameShared(as: local)
        local = s
        return changed
    }

    /// This Mac's console link. True when it changed (send the summary now).
    public mutating func setStatus(_ st: DeskPeerStatus) -> Bool {
        guard st != localStatus else { return false }
        localStatus = st
        return true
    }

    /// The link to the other Mac came up or went down: what it told is forgotten.
    public mutating func linkChanged() {
        peerStatus = nil
        incoming = nil
        lastRequestAt = -.infinity
    }

    public func summary(me: String, peer: String) -> DeskPacket {
        let n = local.normalized(me: me, other: peer)
        return .summary(DeskWireSummary(revision: n.revision, hash: n.shareHash(me: me, peer: peer), flags: n.flags,
                                        model: n.model.wireCode, fadeTenths: n.fadeTenths,
                                        rowCount: UInt8(clamping: n.rows.count), status: localStatus.rawValue, host: n.host))
    }

    public func rows(me: String, peer: String) -> [DeskPacket] {
        let n = local.normalized(me: me, other: peer)
        return n.rows.prefix(DeskSettings.maxRows).enumerated().map { i, r in
            .row(revision: n.revision, index: UInt8(i), DeskWireRow(
                kind: r.kind == .input ? 0 : 1, senderChannel: UInt8(clamping: r.channels[me] ?? 0),
                receiverChannel: UInt8(clamping: r.channels[peer] ?? 0), fixedLevel: Int16(clamping: r.fixedLevel),
                name: String(decoding: Array(truncatedUTF8(r.name, max: DeskSettings.maxNameBytes)), as: UTF8.self)))
        }
    }

    /// (revision, ID) of `a` is newer than that of `b`.
    static func isNewer(_ a: (UInt64, String), than b: (UInt64, String)) -> Bool {
        a.0 != b.0 ? a.0 > b.0 : a.1 > b.1
    }

    /// A desk packet from the linked Mac `peer`. Returns settings to take over (already this
    /// object's `local`; this Mac's `moveDeskWhenConfirming` kept) and packets to send back.
    public mutating func received(_ p: DeskPacket, me: String, peer: String, myName: String, peerName: String,
                                  now: Double) -> (adopt: DeskSettings?, send: [DeskPacket]) {
        switch p {
        case let .summary(s):
            peerStatus = DeskPeerStatus(rawValue: s.status) ?? .notConnected
            guard wants(s.revision, hash: s.hash, me: me, peer: peer) else {
                if incoming?.revision ?? 0 <= local.revision { incoming = nil }
                return (nil, [])
            }
            // A revision first heard of now: its rows are on their way (they are sent right after
            // a change and when the link comes up). Still missing at the next summary: ask.
            let firstHeard = incoming?.revision != s.revision
            if firstHeard { incoming = Incoming(revision: s.revision) }
            incoming?.summary = s
            if let adopted = assemble(me: me, peer: peer, myName: myName, peerName: peerName) { return (adopted, []) }
            return (nil, firstHeard ? [] : request(s.revision, now: now))
        case let .row(rev, index, r):
            guard rev > local.revision || (rev == local.revision && peer > me) else { return (nil, []) }
            if incoming?.revision != rev {
                // Rows of a revision newer than the one being collected start over (the summary follows).
                guard rev > (incoming?.revision ?? 0) else { return (nil, []) }
                incoming = Incoming(revision: rev)
            }
            incoming?.rows[Int(index)] = r
            if let adopted = assemble(me: me, peer: peer, myName: myName, peerName: peerName) { return (adopted, []) }
            return (nil, [])
        case let .request(rev):
            // Only the revision asked for; otherwise the summary tells what this Mac has now.
            return (nil, rev == local.revision ? [summary(me: me, peer: peer)] + rows(me: me, peer: peer) : [summary(me: me, peer: peer)])
        }
    }

    private func wants(_ revision: UInt64, hash: UInt32, me: String, peer: String) -> Bool {
        revision > 0 && Self.isNewer((revision, peer), than: (local.revision, me)) && hash != local.shareHash(me: me, peer: peer)
    }

    private mutating func request(_ revision: UInt64, now: Double) -> [DeskPacket] {
        guard now - lastRequestAt >= Self.requestInterval else { return [] }
        lastRequestAt = now
        return [.request(revision: revision)]
    }

    /// All rows of the summary are here: the settings, if their hash matches.
    private mutating func assemble(me: String, peer: String, myName: String, peerName: String) -> DeskSettings? {
        guard let inc = incoming, let s = inc.summary, (0..<Int(s.rowCount)).allSatisfy({ inc.rows[$0] != nil }),
              let model = DeskModel(wireCode: s.model) else { return nil }
        var d = DeskSettings()
        d.enabled = s.flags & 1 != 0
        d.trigger = s.flags & 2 != 0 ? .automatic : .confirm
        d.pullMainToMinusInfinity = s.flags & 4 != 0
        d.useFixedLevels = s.flags & 8 != 0
        d.model = model
        d.fade = DeskSettings.nearestFade(Double(s.fadeTenths) / 10)
        d.host = s.host
        // Kept where the old row had the same place, so the window's fields stay put.
        d.rows = (0..<Int(s.rowCount)).compactMap { i -> DeskRow? in
            guard let r = inc.rows[i] else { return nil }
            var ch: [String: Int] = [:]
            if r.senderChannel > 0 { ch[peer] = Int(r.senderChannel) }
            if r.receiverChannel > 0 { ch[me] = Int(r.receiverChannel) }
            let id = i < local.rows.count ? local.rows[i].id : UUID()
            return DeskRow(id: id, kind: r.kind == 0 ? .input : .stereoIn, channels: ch,
                           fixedLevel: DeskLevel.clamped(Int(r.fixedLevel)), name: r.name)
        }
        d.macNames = [me: myName, peer: peerName]
        d.revision = s.revision
        d.moveDeskWhenConfirming = local.moveDeskWhenConfirming
        guard d.shareHash(me: me, peer: peer) == s.hash else {
            incoming = nil              // something is off: ask again with the next summary
            return nil
        }
        incoming = nil
        local = d
        return d
    }
}
