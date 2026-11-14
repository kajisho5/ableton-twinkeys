import Foundation

// QLab mode (docs/design-qlab.md 2.1, 2.2): the small part of OSC 1.0 that TwinKeys needs to talk
// to QLab, and SLIP (RFC 1055) framing for OSC over TCP (OSC 1.1: a SLIP END byte at both ends of
// every packet). Hand-written so there is no new dependency; tested on Linux.

/// One OSC argument. Only the types QLab's replies and TwinKeys' commands use.
public enum OSCArgument: Equatable, Sendable {
    case string(String)
    case int(Int32)
    case float(Float)
    /// OSC 1.1 `T` / `F` (no bytes in the argument data).
    case bool(Bool)
    case blob([UInt8])

    var tag: UInt8 {
        switch self {
        case .string: return UInt8(ascii: "s")
        case .int: return UInt8(ascii: "i")
        case .float: return UInt8(ascii: "f")
        case let .bool(b): return UInt8(ascii: b ? "T" : "F")
        case .blob: return UInt8(ascii: "b")
        }
    }

    public var stringValue: String? { if case let .string(s) = self { return s }; return nil }
}

/// One OSC message (address pattern and arguments).
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [OSCArgument]
    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address; self.arguments = arguments
    }

    /// The OSC packet bytes (big-endian, every part padded to 4 bytes).
    public func encoded() -> [UInt8] {
        var out = OSC.paddedString(address)
        out += OSC.paddedString("," + String(decoding: arguments.map(\.tag), as: UTF8.self))
        for a in arguments {
            switch a {
            case let .string(s): out += OSC.paddedString(s)
            case let .int(i): out += OSC.be32(UInt32(bitPattern: i))
            case let .float(f): out += OSC.be32(f.bitPattern)
            case .bool: break
            case let .blob(b):
                out += OSC.be32(UInt32(b.count)) + b
                out += [UInt8](repeating: 0, count: (4 - b.count % 4) % 4)
            }
        }
        return out
    }

    /// Reads one OSC message. nil for anything malformed, a bundle, or an argument type it does
    /// not know (then the rest cannot be read safely).
    public static func decode(_ bytes: [UInt8]) -> OSCMessage? {
        var i = 0
        guard let address = OSC.readString(bytes, &i), address.hasPrefix("/") else { return nil }
        // OSC 1.0 allows a message without a type tag string: no arguments.
        if i >= bytes.count { return OSCMessage(address) }
        guard let tags = OSC.readString(bytes, &i), tags.hasPrefix(",") else { return nil }
        var args: [OSCArgument] = []
        for t in tags.utf8.dropFirst() {
            switch t {
            case UInt8(ascii: "s"), UInt8(ascii: "S"):
                guard let s = OSC.readString(bytes, &i) else { return nil }
                args.append(.string(s))
            case UInt8(ascii: "i"):
                guard i + 4 <= bytes.count else { return nil }
                args.append(.int(Int32(bitPattern: OSC.read32(bytes, i)))); i += 4
            case UInt8(ascii: "f"):
                guard i + 4 <= bytes.count else { return nil }
                args.append(.float(Float(bitPattern: OSC.read32(bytes, i)))); i += 4
            case UInt8(ascii: "d"):
                // A 64-bit double: kept as a float (TwinKeys only reads seconds).
                guard i + 8 <= bytes.count else { return nil }
                let v = (UInt64(OSC.read32(bytes, i)) << 32) | UInt64(OSC.read32(bytes, i + 4))
                args.append(.float(Float(Double(bitPattern: v)))); i += 8
            case UInt8(ascii: "h"):
                guard i + 8 <= bytes.count else { return nil }
                let v = (UInt64(OSC.read32(bytes, i)) << 32) | UInt64(OSC.read32(bytes, i + 4))
                args.append(.int(Int32(truncatingIfNeeded: Int64(bitPattern: v)))); i += 8
            case UInt8(ascii: "T"): args.append(.bool(true))
            case UInt8(ascii: "F"): args.append(.bool(false))
            case UInt8(ascii: "N"), UInt8(ascii: "I"): break
            case UInt8(ascii: "b"):
                guard i + 4 <= bytes.count else { return nil }
                let n = Int(OSC.read32(bytes, i)); i += 4
                guard n >= 0, n <= bytes.count - i else { return nil }
                args.append(.blob(Array(bytes[i..<(i + n)])))
                i += n + (4 - n % 4) % 4
            default:
                return nil
            }
        }
        return OSCMessage(address, args)
    }
}

enum OSC {
    /// A string, its NUL terminator and 0–3 more NULs (always at least one NUL).
    static func paddedString(_ s: String) -> [UInt8] {
        var b = Array(s.utf8)
        b.append(0)
        while b.count % 4 != 0 { b.append(0) }
        return b
    }

    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    static func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }

    /// Reads a NUL-terminated, 4-byte aligned string at `i` and moves `i` past its padding.
    static func readString(_ b: [UInt8], _ i: inout Int) -> String? {
        guard i < b.count, let end = b[i...].firstIndex(of: 0) else { return nil }
        let s = String(decoding: b[i..<end], as: UTF8.self)
        let next = end + 1 + (4 - (end + 1 - i) % 4) % 4
        guard next <= b.count else { return nil }
        i = next
        return s
    }
}

/// SLIP framing (RFC 1055) as OSC 1.1 uses it over TCP: END (0xC0) before and after each packet,
/// END and ESC (0xDB) inside escaped as ESC ESC_END (0xDC) and ESC ESC_ESC (0xDD).
public enum SLIP {
    public static let end: UInt8 = 0xC0
    public static let esc: UInt8 = 0xDB
    public static let escEnd: UInt8 = 0xDC
    public static let escEsc: UInt8 = 0xDD

    public static func encode(_ packet: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [end]
        out.reserveCapacity(packet.count + 8)
        for b in packet {
            switch b {
            case end: out += [esc, escEnd]
            case esc: out += [esc, escEsc]
            default: out.append(b)
            }
        }
        out.append(end)
        return out
    }
}

/// Collects SLIP packets from a TCP stream that arrives in pieces of any size.
public struct SLIPDecoder: Sendable {
    /// A packet bigger than this is dropped (a broken stream must not fill the memory). QLab's
    /// biggest reply, the cue lists of a large workspace, is a few MB.
    public static let maxPacket = 16 << 20
    private var current: [UInt8] = []
    private var escaping = false
    private var overflow = false
    public init() {}

    /// Feed bytes; returns the packets completed by them (empty packets between two ENDs are skipped).
    public mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for b in bytes {
            if b == SLIP.end {
                if !current.isEmpty, !overflow { out.append(current) }
                current.removeAll(keepingCapacity: true); escaping = false; overflow = false
                continue
            }
            var v = b
            if escaping {
                escaping = false
                switch b {
                case SLIP.escEnd: v = SLIP.end
                case SLIP.escEsc: v = SLIP.esc
                default: v = b            // a protocol violation: keep the byte (RFC 1055 does the same)
                }
            } else if b == SLIP.esc {
                escaping = true
                continue
            }
            if current.count >= Self.maxPacket { overflow = true; continue }
            current.append(v)
        }
        return out
    }

    public mutating func reset() { current.removeAll(); escaping = false; overflow = false }
}
