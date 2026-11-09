/// When All Notes Off is sent, and where to.
public enum SafetyTrigger: Equatable, Sendable {
    case panicButton
    case appWillQuit
    case connectionLost
    case manualDisconnect
    case peerSaidBye
    case sendingTurnedOff
    case keyCaptureTurnedOff
}

public struct SafetyPlan: Equatable, Sendable {
    /// Send All Notes Off to this Mac's virtual port.
    public var local: Bool
    /// Send All Notes Off to the connected peer (only if there is one).
    public var remote: Bool
}

public enum Safety {
    public static func plan(for trigger: SafetyTrigger, connected: Bool) -> SafetyPlan {
        switch trigger {
        case .panicButton, .appWillQuit, .manualDisconnect, .sendingTurnedOff, .keyCaptureTurnedOff:
            // Notes played by our keys may be sounding on both Macs.
            return SafetyPlan(local: true, remote: connected)
        case .connectionLost, .peerSaidBye:
            // The peer cannot be reached (or is leaving); its own side cleans up itself.
            return SafetyPlan(local: true, remote: false)
        }
    }
}
