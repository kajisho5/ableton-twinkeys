/// When All Notes Off is sent, and where to.
public enum SafetyTrigger: Equatable, Sendable, CaseIterable {
    case panicButton
    case appWillQuit
    case connectionLost
    case manualDisconnect
    case peerSaidBye
    case sendingTurnedOff
    case keyCaptureTurnedOff
}

public struct SafetyPlan: Equatable, Sendable {
    public enum Local: Equatable, Sendable {
        /// Leave this Mac's port alone.
        case none
        /// Turn off only notes that came from the peer.
        case notesFromPeer
        /// Turn off notes played by this Mac's own keys.
        case notesFromKeys
        /// All Notes Off (CC 123 on every channel) plus note-offs for every tracked note.
        case all
    }
    public var local: Local
    /// Tell the connected peer (only if there is one): All Notes Off for `.all`,
    /// the matching note-offs for `.notesFromKeys`.
    public var remote: Bool
}

public enum Safety {
    public static func plan(for trigger: SafetyTrigger, connected: Bool) -> SafetyPlan {
        switch trigger {
        case .panicButton, .appWillQuit, .manualDisconnect:
            return SafetyPlan(local: .all, remote: connected)
        case .sendingTurnedOff, .keyCaptureTurnedOff:
            // Our keys stop producing notes: end the ones they started, on both Macs.
            return SafetyPlan(local: .notesFromKeys, remote: connected)
        case .connectionLost, .peerSaidBye:
            // The peer is gone. Notes it started here must not hang, but notes
            // played on this Mac's own keys keep sounding.
            return SafetyPlan(local: .notesFromPeer, remote: false)
        }
    }
}
