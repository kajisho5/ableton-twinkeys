import Foundation

/// TwinKeys UDP packet format (big-endian).
///
///     0  'T' 'K'            magic
///     2  version (1)
///     3  type
///     4  session  u32        random per app launch; a new value resets sequence tracking
///     8  seq      u32        increases by 1 per packet
///    12  payload
public enum WireProtocol {
    public static let version: UInt8 = 1
    public static let headerSize = 12
    public static let maxPacketSize = 64
}

public enum PacketBody: Equatable, Sendable {
    case hello(instanceID: UUID, name: String)
    case helloAck(instanceID: UUID, name: String)
    case bye
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case allNotesOff
    case heartbeat(timestampNanos: UInt64)
    case heartbeatAck(timestampNanos: UInt64)

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

extension Packet {
    public func encode() -> [UInt8] {
        var b: [UInt8] = [0x54, 0x4B, WireProtocol.version, body.typeCode]
        b.appendBE(session); b.appendBE(seq)
        switch body {
        case let .hello(id, name), let .helloAck(id, name):
            let u = id.uuid
            b += [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
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
            guard p.count >= 17 else { throw DecodeError.badPayload }
            let id = UUID(uuid: (p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15]))
            let len = Int(p[16])
            guard len <= maxNameBytes, p.count >= 17 + len else { throw DecodeError.badPayload }
            let name = String(decoding: p[17..<(17 + len)], as: UTF8.self)
            body = data[3] == 0x01 ? .hello(instanceID: id, name: name) : .helloAck(instanceID: id, name: name)
        case 0x03: body = .bye
        case 0x10:
            guard p.count >= 3, p[0] < 16, p[1] < 128, p[2] < 128 else { throw DecodeError.badPayload }
            body = .noteOn(channel: p[0], note: p[1], velocity: p[2])
        case 0x11:
            guard p.count >= 2, p[0] < 16, p[1] < 128 else { throw DecodeError.badPayload }
            body = .noteOff(channel: p[0], note: p[1])
        case 0x20: body = .allNotesOff
        case 0x30, 0x31:
            guard p.count >= 8 else { throw DecodeError.badPayload }
            let t = (UInt64(p.readBE32(at: 0)) << 32) | UInt64(p.readBE32(at: 4))
            body = data[3] == 0x30 ? .heartbeat(timestampNanos: t) : .heartbeatAck(timestampNanos: t)
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
    public init() {}

    public mutating func accept(session s: UInt32, seq: UInt32) -> Bool {
        if session != s {
            session = s; last = seq
            return true
        }
        let diff = Int32(bitPattern: seq &- last)
        guard diff > 0 else { return false }
        last = seq
        return true
    }

    public mutating func reset() { session = nil; last = 0 }
}
