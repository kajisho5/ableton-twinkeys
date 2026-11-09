#if os(macOS)
import Foundation
import TwinKeysCore

enum PermissionState: Equatable { case granted, denied, unknown }

enum LocalNetworkState: Equatable {
    /// Browsing, nothing found yet.
    case searching
    /// At least one other TwinKeys is visible, so access works.
    case peersVisible
    /// macOS refused local network access (System Settings > Privacy & Security > Local Network).
    case denied
}

enum LinkStatus: Equatable {
    case notConnected
    case connecting(name: String, attempt: Int)
    case connected(name: String, latencyMs: Double?)
}

/// Everything the window shows. Plain values, so the UI can also be rendered
/// from sample data (screenshots) without any hardware.
struct ViewState: Equatable {
    var link: LinkStatus = .notConnected
    var linkedPeerID: String?
    var peers: [PeerInfo] = []
    var sendKeys = true
    var receiveNotes = true
    var keyCapture = true
    var inputMonitoring: PermissionState = .unknown
    var localNetwork: LocalNetworkState = .searching
    var octave = 3
    var velocity = 100
    var heldNotes: [UInt8] = []
    var midiPortReady = true
    var problems: [String] = []

    var canToggleConnection: Bool { linkedPeerID != nil || peers.count == 1 }
    var connectMenuTitle: String {
        if linkedPeerID != nil { return "Disconnect" }
        if peers.count == 1 { return "Connect to \(peers[0].name)" }
        return "Connect"
    }

    var keyCaptureActive: Bool { keyCapture && sendKeys && inputMonitoring == .granted }

    var headline: String {
        switch link {
        case .notConnected: return "Not connected"
        case let .connecting(name, _): return "Connecting to \(name)…"
        case let .connected(name, _): return "Connected to \(name)"
        }
    }

    var detail: String {
        let roles: String
        switch (sendKeys, receiveNotes) {
        case (true, true): roles = "Sending and receiving"
        case (true, false): roles = "Sending"
        case (false, true): roles = "Receiving"
        case (false, false): roles = "Sending and receiving are off"
        }
        switch link {
        case .notConnected:
            return peers.isEmpty ? "Searching for TwinKeys…" : "Choose a Mac below and click Connect"
        case let .connecting(_, attempt):
            return attempt > 1 ? "No answer yet, retrying (attempt \(attempt))" : "Waiting for an answer…"
        case let .connected(_, latency):
            return "Latency \(Self.latencyText(latency))  ·  \(roles)"
        }
    }

    static func latencyText(_ ms: Double?) -> String {
        guard let ms else { return "measuring…" }
        return ms < 1 ? "<1 ms" : "\(Int(ms.rounded())) ms"
    }
}

/// What the window can ask the app to do.
struct ViewActions {
    var connect: (String) -> Void = { _ in }
    var disconnect: () -> Void = {}
    var panic: () -> Void = {}
    var setSendKeys: (Bool) -> Void = { _ in }
    var setReceiveNotes: (Bool) -> Void = { _ in }
    var setKeyCapture: (Bool) -> Void = { _ in }
    var openInputMonitoringSettings: () -> Void = {}
    var openLocalNetworkSettings: () -> Void = {}
    var recheckPermissions: () -> Void = {}
}
#endif
