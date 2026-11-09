/// A TwinKeys instance found on the network.
public struct PeerInfo: Identifiable, Equatable, Sendable {
    /// The instance ID (from the Bonjour TXT record). Stable across launches.
    public var id: String
    public var name: String
    public var sends: Bool
    public var receives: Bool
    public init(id: String, name: String, sends: Bool, receives: Bool) {
        self.id = id; self.name = name; self.sends = sends; self.receives = receives
    }

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

    public static func modes(sends: Bool, receives: Bool) -> String {
        (sends ? "s" : "") + (receives ? "r" : "")
    }

    /// Builds a peer from a TXT record. Returns nil for our own instance or a bad record.
    public static func peer(from txt: [String: String], serviceName: String, ownID: String) -> PeerInfo? {
        guard let id = txt[Self.id], !id.isEmpty, id != ownID else { return nil }
        let m = txt[Self.modes] ?? ""
        return PeerInfo(id: id, name: serviceName, sends: m.contains("s"), receives: m.contains("r"))
    }
}
