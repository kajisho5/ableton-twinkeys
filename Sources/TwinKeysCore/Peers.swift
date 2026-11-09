/// A TwinKeys instance found on the network.
public struct PeerInfo: Identifiable, Equatable, Sendable {
    /// The instance ID (from the Bonjour TXT record). Stable across launches.
    public var id: String
    public var name: String
    public var sends: Bool
    public var receives: Bool
    /// Wire protocol version the peer advertises (nil if it did not say).
    public var version: String?
    public init(id: String, name: String, sends: Bool, receives: Bool, version: String? = nil) {
        self.id = id; self.name = name; self.sends = sends; self.receives = receives; self.version = version
    }

    /// False when the peer speaks another protocol version: connecting would never work.
    public var isCompatible: Bool { version == nil || version == String(WireProtocol.version) }

    /// Prefix of placeholder peer IDs for connections made by IP address.
    public static let manualPrefix = "manual:"

    public var modeText: String {
        switch (sends, receives) {
        case (true, true): return "Send + Receive"
        case (true, false): return "Send"
        case (false, true): return "Receive"
        case (false, false): return "Idle"
        }
    }
}

public enum TXTKeys {
    public static let id = "id"
    public static let version = "v"
    public static let modes = "modes"
    /// Random per launch. Our own ID with another boot value means another Mac copied our ID.
    public static let boot = "boot"

    public static func modes(sends: Bool, receives: Bool) -> String {
        (sends ? "s" : "") + (receives ? "r" : "")
    }

    /// Builds a peer from a TXT record. Returns nil for our own instance or a bad record.
    public static func peer(from txt: [String: String], serviceName: String, ownID: String) -> PeerInfo? {
        guard let id = txt[Self.id], !id.isEmpty, id != ownID else { return nil }
        let m = txt[Self.modes] ?? ""
        return PeerInfo(id: id, name: serviceName, sends: m.contains("s"), receives: m.contains("r"), version: txt[Self.version])
    }

    /// True if the record carries our ID but comes from another running instance
    /// (for example a Mac set up from a backup of this one).
    public static func isDuplicateOfUs(_ txt: [String: String], ownID: String, ownBoot: String) -> Bool {
        guard txt[Self.id] == ownID, let b = txt[Self.boot] else { return false }
        return b != ownBoot
    }
}
