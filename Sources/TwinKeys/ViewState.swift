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
    var heldNotes: [UInt8] = []
    var midiPortReady = true
    var problems: [AppProblem] = []
    var language: AppLanguage = .system
    /// macOS Secure Input is on (a password field has focus): key events are hidden.
    var secureInput = false
    /// Pairing code is set and in use.
    var isPaired = false
    /// The code shown in Settings ("K7MQ2-WX9TP"), nil if none.
    var pairingCode: String?
    var mismatchedPeers: Set<String> = []
    var listenPort: UInt16?
    var localAddresses: [String] = []
    var lastManualAddress = ""
    var sheet: AppSheet?
    /// The last cue sent (main) or received (backup).
    var lastCue: CueStatus?
    var cueKeys: [CueKey] = CueKey.defaults
    var blockCueKeys = true
    /// The key tap can keep cue keys from other apps right now.
    var cueKeysBlocked = false
    var accessibility: PermissionState = .unknown
    var update: UpdateState = .idle
    var appVersion = ""
    var autoUpdate = true
    /// Live on this Mac answers through the Bridge.
    var liveConnected = false
    var bridgeInstalled = false
    var approvedDevices: [ApprovedDevice] = []
    var remoteClients = 0
    var remoteEnabled = true

    var t: Strings { Strings(language) }

    var canToggleConnection: Bool { linkedPeerID != nil || (isPaired && peers.count == 1 && peers[0].isCompatible) }
    var connectMenuTitle: String {
        if linkedPeerID != nil { return t.disconnect }
        if peers.count == 1 { return t.connectTo(peers[0].name) }
        return t.connect
    }

    var keyCaptureActive: Bool { keyCapture && sendKeys && inputMonitoring == .granted }

    /// Cue keys are set to stay away from other apps but still reach them (no Accessibility).
    var cueKeysLeaking: Bool { blockCueKeys && !cueKeys.isEmpty && keyCaptureActive && !cueKeysBlocked }

    /// "Restart Now" is offered only while not connected: never during a show.
    var canRestartForUpdate: Bool {
        if case .ready = update, linkedPeerID == nil { return true }
        return false
    }

    var headline: String {
        switch link {
        case .notConnected: return t.notConnected
        case let .connecting(name, _): return t.connecting(name)
        case let .connected(name, _): return t.connected(name)
        }
    }

    var detail: String {
        let roles: String
        switch (sendKeys, receiveNotes) {
        case (true, true): roles = t.sendingAndReceiving
        case (true, false): roles = t.sending
        case (false, true): roles = t.receiving
        case (false, false): roles = t.bothOff
        }
        switch link {
        case .notConnected:
            if !isPaired { return t.needsPairingDetail }
            return peers.isEmpty ? t.searching : t.chooseMac
        case let .connecting(_, attempt):
            return attempt > 1 ? t.retrying(attempt) : t.waitingForAnswer
        case let .connected(_, latency):
            return t.latencyLine(latencyText(latency), roles)
        }
    }

    func latencyText(_ ms: Double?) -> String {
        guard let ms else { return t.measuring }
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
    var setSheet: (AppSheet?) -> Void = { _ in }
    var makeNewPairingCode: () -> Void = {}
    /// Returns false if the code is not valid.
    var savePairingCode: (String) -> Bool = { _ in false }
    var copyPairingCode: () -> Void = {}
    /// Returns false if the address is not valid.
    var connectByAddress: (String) -> Bool = { _ in false }
    var openAccessibilitySettings: () -> Void = {}
    var restartForUpdate: () -> Void = {}
    var openReleasePage: () -> Void = {}
}

enum AppSheet: Equatable { case pairing, connectByIP, help, approveDevice(name: String, code: String) }
#endif
