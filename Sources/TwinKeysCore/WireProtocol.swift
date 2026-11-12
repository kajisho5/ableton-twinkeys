import Foundation

/// TwinKeys UDP packet format (big-endian).
///
///     0  'T' 'K'            magic
///     2  version (2: authenticated and encrypted, see SecureChannel)
///     3  type
///     4  session  u32        random per app launch; a new value resets sequence tracking
///     8  seq      u32        increases by 1 per packet
///    12  payload
public enum WireProtocol {
    public static let version: UInt8 = 2
    public static let headerSize = 12
    public static let maxPacketSize = 128
}

public enum PacketBody: Equatable, Sendable {
    /// `nonce`: the sender's 16-byte per-launch value (part of the link keys).
    case hello(instanceID: UUID, nonce: [UInt8], name: String)
    case helloAck(instanceID: UUID, nonce: [UInt8], name: String)
    case bye
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case allNotesOff
    case heartbeat(timestampNanos: UInt64)
    case heartbeatAck(timestampNanos: UInt64)
    /// Notes the sender's keys are still holding. Sent with each heartbeat so the
    /// receiver's automatic note-off only fires when a note-off was really lost.
    case held(channel: UInt8, notes: [UInt8])
    /// Since 1.0.0: what the sender understands (bit 0: cue delivery check; bit 1: the sender
    /// has just (re)connected and starts counting cues from zero). Sent with each
    /// heartbeat. Older versions drop unknown packet types, so they simply never send it.
    /// `epoch` (1.0.1+): the sender's link counter; when it changes, the sender reconnected.
    case features(flags: UInt8, epoch: UInt8? = nil)
    /// Since 1.0.0: "your note-on with this sequence number arrived".
    case noteAck(seq: UInt32)
    /// Since 1.0.0: the name of a cue key, so the other Mac can show it ("↓", "Next scene").
    case cueName(channel: UInt8, note: UInt8, label: String, memo: String)
    /// Since 1.0.0: a cue sent again because no noteAck came. `originalSeq` is the sequence
    /// number of the first note-on: the receiver plays it only if that one never arrived.
    /// `released`: the key is already up, so the note ends right away.
    case cueResend(originalSeq: UInt32, channel: UInt8, note: UInt8, velocity: UInt8, released: Bool)
    /// Since 1.0.2: the sender's count for the cue whose note-on had sequence number `seq`, so
    /// both Macs always show the same number (the main Mac's).
    case cueCount(seq: UInt32, count: UInt32)
    /// Since 2.0: a Live command from the iPhone, forwarded by the main Mac. `id` is per sender
    /// session; a resend carries the same id and is run only once.
    case liveCommand(id: UInt32, LiveCommand)
    /// Since 2.0: the backup ran (or already had run) the Live command with this id.
    case liveAck(id: UInt32)
    /// Since 2.0.1: whether the sender's Live answers (TwinKeysBridge). Sent with each heartbeat.
    case liveStatus(connected: Bool)
    /// Since 2.1: the sender's Live set in short (track and scene counts, hash of all names).
    case setSummary(tracks: UInt16, scenes: UInt16, hash: UInt32)
    /// Since 2.1: one track or scene name of the sender's set (sent a few at a time).
    case setItem(kind: UInt8, index: UInt16, name: String)
    /// Since 2.2: what the backup's Live did with Live command `id` (0 ran, 1 Live refused it,
    /// 2 Live did not answer). Sent after the liveAck, once the backup's Live has answered.
    case liveResult(id: UInt32, code: UInt8)

    var typeCode: UInt8 {
        switch self {
        case .hello: return 0x01
        case .helloAck: return 0x02
        case .bye: return 0x03
        case .noteOn: return 0x10
        case .noteOff: return 0x11
        case .allNotesOff: return 0x20
        case .heartbeat: return 0x30
        case .heartbeatAck: return 0x31
        case .held: return 0x12
        case .features: return 0x13
        case .noteAck: return 0x14
        case .cueName: return 0x15
        case .cueResend: return 0x16
        case .cueCount: return 0x17
        case .liveCommand: return 0x18
        case .liveAck: return 0x19
        case .liveStatus: return 0x1A
        case .setSummary: return 0x1B
        case .setItem: return 0x1C
        case .liveResult: return 0x1D
        }
    }
}

public struct Packet: Equatable, Sendable {
    public var session: UInt32
    public var seq: UInt32
    public var body: PacketBody
    public init(session: UInt32, seq: UInt32, body: PacketBody) {
        self.session = session; self.seq = seq; self.body = body
    }
}

public enum DecodeError: Error, Equatable {
    case tooShort, badMagic, unsupportedVersion(UInt8), unknownType(UInt8), badPayload
}

/// Maximum bytes of a peer name carried in hello packets.
let maxNameBytes = 32
/// Maximum notes listed in one held packet.
let maxHeldNotes = 32

extension Packet {
    public func encode() -> [UInt8] {
        var b: [UInt8] = [0x54, 0x4B, WireProtocol.version, body.typeCode]
        b.appendBE(session); b.appendBE(seq)
        switch body {
        case let .hello(id, nonce, name), let .helloAck(id, nonce, name):
            let u = id.uuid
            b += [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
            b += Array((nonce + [UInt8](repeating: 0, count: 16)).prefix(16))
            let nameBytes = Array(truncatedUTF8(name, max: maxNameBytes))
            b.append(UInt8(nameBytes.count)); b += nameBytes
        case .bye, .allNotesOff:
            break
        case let .noteOn(ch, note, vel):
            b += [ch & 0x0F, note & 0x7F, vel & 0x7F]
        case let .noteOff(ch, note):
            b += [ch & 0x0F, note & 0x7F]
        case let .heartbeat(t), let .heartbeatAck(t):
            b.appendBE(t)
        case let .held(ch, notes):
            let list = Array(notes.prefix(maxHeldNotes))
            b += [ch & 0x0F, UInt8(list.count)] + list.map { $0 & 0x7F }
        case let .features(flags, epoch):
            b.append(flags)
            if let epoch { b.append(epoch) }
        case let .noteAck(s):
            b.appendBE(s)
        case let .cueName(ch, note, label, memo):
            let l = Array(truncatedUTF8(label, max: CueKey.maxLabelBytes))
            let m = Array(truncatedUTF8(memo, max: CueKey.maxMemoBytes))
            b += [ch & 0x0F, note & 0x7F, UInt8(l.count)] + l + [UInt8(m.count)] + m
        case let .cueResend(orig, ch, note, vel, released):
            b.appendBE(orig)
            b += [ch & 0x0F, note & 0x7F, vel & 0x7F, released ? 1 : 0]
        case let .cueCount(s, n):
            b.appendBE(s); b.appendBE(n)
        case let .liveCommand(id, c):
            b.appendBE(id); b += c.encoded()
        case let .liveAck(id):
            b.appendBE(id)
        case let .liveStatus(on):
            b.append(on ? 1 : 0)
        case let .setSummary(t, s, h):
            b += [UInt8(t >> 8), UInt8(t & 0xFF), UInt8(s >> 8), UInt8(s & 0xFF)]
            b.appendBE(h)
        case let .setItem(kind, index, name):
            let n = Array(truncatedUTF8(name, max: SetSummary.maxNameBytes))
            b += [kind, UInt8(index >> 8), UInt8(index & 0xFF), UInt8(n.count)] + n
        case let .liveResult(id, code):
            b.appendBE(id); b.append(code)
        }
        return b
    }

    public static func decode(_ data: [UInt8]) throws -> Packet {
        guard data.count >= WireProtocol.headerSize else { throw DecodeError.tooShort }
        guard data[0] == 0x54, data[1] == 0x4B else { throw DecodeError.badMagic }
        guard data[2] == WireProtocol.version else { throw DecodeError.unsupportedVersion(data[2]) }
        let session = data.readBE32(at: 4), seq = data.readBE32(at: 8)
        let p = Array(data[WireProtocol.headerSize...])
        let body: PacketBody
        switch data[3] {
        case 0x01, 0x02:
            guard p.count >= 33 else { throw DecodeError.badPayload }
            let id = UUID(uuid: (p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15]))
            let nonce = Array(p[16..<32])
            let len = Int(p[32])
            guard len <= maxNameBytes, p.count >= 33 + len else { throw DecodeError.badPayload }
            let name = String(decoding: p[33..<(33 + len)], as: UTF8.self)
            body = data[3] == 0x01 ? .hello(instanceID: id, nonce: nonce, name: name) : .helloAck(instanceID: id, nonce: nonce, name: name)
        case 0x03: body = .bye
        case 0x10:
            guard p.count >= 3, p[0] < 16, p[1] < 128, p[2] < 128 else { throw DecodeError.badPayload }
            body = .noteOn(channel: p[0], note: p[1], velocity: p[2])
        case 0x11:
            guard p.count >= 2, p[0] < 16, p[1] < 128 else { throw DecodeError.badPayload }
            body = .noteOff(channel: p[0], note: p[1])
        case 0x20: body = .allNotesOff
        case 0x12:
            guard p.count >= 2, p[0] < 16, Int(p[1]) <= maxHeldNotes, p.count >= 2 + Int(p[1]) else { throw DecodeError.badPayload }
            let notes = Array(p[2..<(2 + Int(p[1]))])
            guard notes.allSatisfy({ $0 < 128 }) else { throw DecodeError.badPayload }
            body = .held(channel: p[0], notes: notes)
        case 0x30, 0x31:
            guard p.count >= 8 else { throw DecodeError.badPayload }
            let t = (UInt64(p.readBE32(at: 0)) << 32) | UInt64(p.readBE32(at: 4))
            body = data[3] == 0x30 ? .heartbeat(timestampNanos: t) : .heartbeatAck(timestampNanos: t)
        case 0x13:
            guard p.count >= 1 else { throw DecodeError.badPayload }
            body = .features(flags: p[0], epoch: p.count >= 2 ? p[1] : nil)
        case 0x14:
            guard p.count >= 4 else { throw DecodeError.badPayload }
            body = .noteAck(seq: p.readBE32(at: 0))
        case 0x15:
            guard p.count >= 4, p[0] < 16, p[1] < 128 else { throw DecodeError.badPayload }
            let ll = Int(p[2])
            guard ll <= CueKey.maxLabelBytes, p.count >= 4 + ll else { throw DecodeError.badPayload }
            let ml = Int(p[3 + ll])
            guard ml <= CueKey.maxMemoBytes, p.count >= 4 + ll + ml else { throw DecodeError.badPayload }
            body = .cueName(channel: p[0], note: p[1],
                            label: String(decoding: p[3..<(3 + ll)], as: UTF8.self),
                            memo: String(decoding: p[(4 + ll)..<(4 + ll + ml)], as: UTF8.self))
        case 0x16:
            guard p.count >= 8, p[4] < 16, p[5] < 128, p[6] < 128 else { throw DecodeError.badPayload }
            body = .cueResend(originalSeq: p.readBE32(at: 0), channel: p[4], note: p[5], velocity: p[6], released: p[7] != 0)
        case 0x17:
            guard p.count >= 8 else { throw DecodeError.badPayload }
            body = .cueCount(seq: p.readBE32(at: 0), count: p.readBE32(at: 4))
        case 0x18:
            guard p.count >= 5, let c = LiveCommand.decode(Array(p[4...])) else { throw DecodeError.badPayload }
            body = .liveCommand(id: p.readBE32(at: 0), c)
        case 0x19:
            guard p.count >= 4 else { throw DecodeError.badPayload }
            body = .liveAck(id: p.readBE32(at: 0))
        case 0x1A:
            guard p.count >= 1 else { throw DecodeError.badPayload }
            body = .liveStatus(connected: p[0] != 0)
        case 0x1B:
            guard p.count >= 8 else { throw DecodeError.badPayload }
            body = .setSummary(tracks: UInt16(p[0]) << 8 | UInt16(p[1]), scenes: UInt16(p[2]) << 8 | UInt16(p[3]), hash: p.readBE32(at: 4))
        case 0x1C:
            guard p.count >= 4, p[0] <= 1 else { throw DecodeError.badPayload }
            let len = Int(p[3])
            guard len <= SetSummary.maxNameBytes, p.count >= 4 + len else { throw DecodeError.badPayload }
            body = .setItem(kind: p[0], index: UInt16(p[1]) << 8 | UInt16(p[2]), name: String(decoding: p[4..<(4 + len)], as: UTF8.self))
        case 0x1D:
            guard p.count >= 5 else { throw DecodeError.badPayload }
            body = .liveResult(id: p.readBE32(at: 0), code: p[4])
        default: throw DecodeError.unknownType(data[3])
        }
        return Packet(session: session, seq: seq, body: body)
    }
}

/// Cuts a string to at most `max` UTF-8 bytes without splitting a character.
func truncatedUTF8(_ s: String, max: Int) -> String.UTF8View {
    var out = ""
    for ch in s {
        if out.utf8.count + String(ch).utf8.count > max { break }
        out.append(ch)
    }
    return out.utf8
}

extension Array where Element == UInt8 {
    mutating func appendBE(_ v: UInt32) { append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
    mutating func appendBE(_ v: UInt64) { appendBE(UInt32(v >> 32)); appendBE(UInt32(v & 0xFFFF_FFFF)) }
    func readBE32(at i: Int) -> UInt32 {
        (UInt32(self[i]) << 24) | (UInt32(self[i + 1]) << 16) | (UInt32(self[i + 2]) << 8) | UInt32(self[i + 3])
    }
}

/// Drops duplicated and reordered packets from one peer.
/// Accepts a packet only if its sequence number is newer than the last accepted one
/// (serial-number arithmetic, so wrap-around at 2^32 is handled).
/// A different session value means the peer restarted: tracking starts over.
public struct SequenceFilter: Sendable {
    private var session: UInt32?
    private var last: UInt32 = 0
    /// Bit i set: sequence number `last - 1 - i` was already accepted (late arrivals, see `allowLate`).
    private var seen: UInt64 = 0
    /// Sessions the peer used before (it restarted since). Late packets from them are dropped.
    private var retired: [UInt32] = []
    public init() {}

    /// `allowLate`: a packet that arrives after a newer one (reordered on the network) is still
    /// accepted once, if it is among the last 64. Used for packets whose order does not matter
    /// (heartbeats, held lists, names); never for notes, where a late note-off could end a newer note.
    public mutating func accept(session s: UInt32, seq: UInt32, allowLate: Bool = false) -> Bool {
        if session != s {
            if retired.contains(s) { return false }
            if let old = session {
                retired.append(old)
                if retired.count > 8 { retired.removeFirst() }
            }
            session = s; last = seq; seen = 0
            return true
        }
        let diff = Int32(bitPattern: seq &- last)
        if diff > 0 {
            seen = diff >= 64 ? 0 : (seen << UInt64(diff)) | (UInt64(1) << UInt64(diff - 1))
            last = seq
            return true
        }
        guard allowLate, diff < 0, diff >= -64 else { return false }
        let bit = UInt64(1) << UInt64(-diff - 1)
        if seen & bit != 0 { return false }
        seen |= bit
        return true
    }

    public mutating func reset() { session = nil; last = 0; seen = 0; retired.removeAll() }

    /// The peer used this session before and restarted since.
    public func isRetired(_ s: UInt32) -> Bool { retired.contains(s) }

    /// The session value currently accepted (the peer's running instance).
    public var currentSession: UInt32? { session }
}
