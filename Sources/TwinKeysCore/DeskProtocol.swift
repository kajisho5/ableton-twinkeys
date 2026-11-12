import Foundation

/// Yamaha's console remote protocol (RCP) on TCP 49280: plain ASCII lines ending in LF, no
/// handshake. Only fader levels are read and written.
///
///     get MIXER:Current/InCh/Fader/Level 3 0          → OK get MIXER:Current/InCh/Fader/Level 3 0 -1000
///     set MIXER:Current/InCh/Fader/Level 3 0 -500     → OK set … 3 0 -500 "-5.00"   (or OKm: adjusted)
///     (the console, or another client, moved it)      → NOTIFY set … 3 0 -500 "-5.00"
///     (refused)                                       → ERROR get UnknownAddress
///
/// Writing (`set`) is in Yamaha's own script example for QL/CL. Reading (`get`, NOTIFY) is not
/// documented by Yamaha; it is reported to work on QL5, DM7 and DM7 Compact.
public enum DeskRCP {
    public static let port: UInt16 = 49280
    public static let inputLevel = "MIXER:Current/InCh/Fader/Level"
    public static let stereoInLevel = "MIXER:Current/StInCh/Fader/Level"

    /// Sent once after connecting, so the console keeps the connection open (errors are ignored).
    public static let keepalive = "scpmode keepalive 10000\n"
    /// A short question sent every 5 s: any answer shows the link is alive.
    public static let ping = "devstatus runmode\n"

    public static func parameter(_ kind: DeskChannelKind) -> String {
        kind == .input ? inputLevel : stereoInLevel
    }

    public static func get(_ a: FaderAddress) -> String {
        "get \(parameter(a.kind)) \(a.x) 0\n"
    }

    public static func set(_ a: FaderAddress, _ value: Int) -> String {
        "set \(parameter(a.kind)) \(a.x) 0 \(DeskLevel.clamped(value))\n"
    }

    /// Reads one line from the console. Extra spaces, a CR before the LF and quoted text after
    /// the value are ignored; anything not understood is `.unknown`.
    public static func parse(_ line: String) -> DeskRCPMessage {
        let tokens = tokenize(line)
        guard let head = tokens.first else { return .unknown(line) }
        switch head {
        case "ERROR":
            let command = tokens.count > 1 ? tokens[1] : ""
            // "ERROR <command> <code>"; take the first plain word after the command.
            let code = tokens.dropFirst(2).first { t in !t.isEmpty && t.allSatisfy { $0.isLetter && $0.isASCII } } ?? ""
            return .error(command: command, code: code)
        case "OK", "OKm", "NOTIFY":
            let command = tokens.count > 1 ? tokens[1] : ""
            if let level = level(tokens, head: head, command: command) { return level }
            return head == "NOTIFY" ? .notify : .ok(command: command)
        default:
            return .unknown(line)
        }
    }

    private static func level(_ t: [String], head: String, command: String) -> DeskRCPMessage? {
        guard command == "get" || command == "set", t.count >= 6 else { return nil }
        let kind: DeskChannelKind
        switch t[2] {
        case inputLevel: kind = .input
        case stereoInLevel: kind = .stereoIn
        default: return nil
        }
        guard let x = Int(t[3]), x >= 0, x < 1000, let y = Int(t[4]), y == 0, let v = Int(t[5]) else { return nil }
        let source: DeskRCPMessage.Source
        switch (head, command) {
        case ("NOTIFY", _): source = .notify
        case (_, "get"): source = .get
        case ("OKm", _): source = .setAdjusted
        default: source = .set
        }
        return .level(FaderAddress(kind, x: x), value: DeskLevel.clamped(v), source: source)
    }

    /// Splits on spaces and tabs; text in double quotes is one token (quotes removed).
    static func tokenize(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        var inToken = false
        for ch in line {
            if quoted {
                if ch == "\"" { quoted = false; out.append(current); current = ""; inToken = false }
                else { current.append(ch) }
            } else if ch == "\"" {
                if inToken { out.append(current); current = "" }
                quoted = true; inToken = true
            } else if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
                if inToken { out.append(current); current = ""; inToken = false }
            } else {
                current.append(ch); inToken = true
            }
        }
        if inToken || quoted { out.append(current) }
        return out
    }
}

/// One line from the console, as far as TwinKeys cares.
public enum DeskRCPMessage: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Answer to our `get`.
        case get
        /// Answer to our `set` (the value the console took).
        case set
        /// `OKm`: the console took the `set` but changed the value (for example clamped it).
        case setAdjusted
        /// The console or another client changed it.
        case notify
    }
    case level(FaderAddress, value: Int, source: Source)
    case error(command: String, code: String)
    /// Any other `OK` / `OKm` line (keepalive, devstatus, other parameters).
    case ok(command: String)
    /// A NOTIFY about something other than an input fader level.
    case notify
    case unknown(String)
}

/// Open Sound Control 1.0 messages (only what Yamaha's fader commands need: one int32).
public enum DeskOSC {
    /// Null-terminated, padded with nulls to a multiple of 4 bytes.
    public static func string(_ s: String) -> [UInt8] {
        var b = Array(s.utf8)
        b.append(0)
        while b.count % 4 != 0 { b.append(0) }
        return b
    }

    /// `address` with one int32 argument (type tag ",i", big-endian value).
    public static func message(_ address: String, int32 value: Int32) -> [UInt8] {
        let v = UInt32(bitPattern: value)
        return string(address) + string(",i") + [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }
}

/// Yamaha's documented fader writes over OSC (UDP 49900), for the DM families: the way to move
/// faders when levels cannot be read. There is no way to read over OSC. QL has no OSC.
///
///     DM7 / DM5:  /yosc:req/set/MIXER:Current/InCh/Fader/Level/<ch>        ,i <level>
///     DM3:        /yosc:req/set/MIXER:Current/InCh/Fader/Level/<ch>/1      ,i <level>
///                 /yosc:req/set/MIXER:Current/StInCh/Fader/Level/<half>/1  ,i <level>   (L = 1, R = 2)
public enum DeskYamahaOSC {
    public static let port: UInt16 = 49900

    /// The OSC addresses for one channel (both halves of a stereo input). Empty when the model
    /// has no OSC or no such channel.
    public static func addresses(_ ch: DeskChannel, model: DeskModel) -> [String] {
        guard model.supportsOSC, ch.number >= 1, ch.number <= model.channelLimit(ch.kind) else { return [] }
        let y = model.oscUsesYIndex ? "/1" : ""
        switch ch.kind {
        case .input:
            return ["/yosc:req/set/\(DeskRCP.inputLevel)/\(ch.number)\(y)"]
        case .stereoIn:
            return ch.addresses.map { "/yosc:req/set/\(DeskRCP.stereoInLevel)/\($0.x + 1)\(y)" }
        }
    }

    public static func messages(_ ch: DeskChannel, value: Int, model: DeskModel) -> [[UInt8]] {
        addresses(ch, model: model).map { DeskOSC.message($0, int32: Int32(DeskLevel.clamped(value))) }
    }
}
