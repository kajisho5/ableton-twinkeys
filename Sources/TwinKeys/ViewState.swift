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
    /// Live runs an older TwinKeysBridge than the one in this app (restart Live).
    var bridgeNeedsRestart = false
    /// 2.3: this Mac made itself the main; the other Mac (receiving only) has not answered for 3 s.
    var claimsMain = false
    var mainLost = false
    /// 2.1: the other Mac's Live answers (nil: not linked or not told), and how its set differs.
    var backupLiveConnected: Bool?
    var setDiff: SetDiff?
    var bridgeInstalled = false
    var approvedDevices: [ApprovedDevice] = []
    var remoteClients = 0
    var remoteEnabled = true
    /// Connection display: the Apple Watch as this Mac's iPhones report it.
    var remoteWatch: WatchLevel = .absent
    /// The other Mac's iPhones as it told us (nil: not linked, or an older version).
    var peerRemote: RemoteSummary?
    /// Name of the device waiting for Allow / Don't Allow on this Mac.
    var approvalRequest: String?
    /// 2.4 console takeover (experimental): the settings (the same on both Macs), whether the
    /// link runs (feature on and an address set, on both Macs), and its state (nil while it does
    /// not run or the feature is off).
    var deskSettings = DeskSettings()
    var deskActive = false
    var desk: DeskSnapshot?
    /// The table's two Macs: this Mac and the other one (TwinKeys IDs and names; the other Mac's
    /// name is nil until known).
    var deskMeID = DeskSettings.thisMacKey
    var deskOtherID = DeskSettings.otherMacKey
    var deskMeName = ""
    var deskOtherName: String?
    /// The other Mac's own console link as it told us (nil: not linked, or a version without it).
    var peerDesk: DeskPeerStatus?

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
            let live = backupLiveConnected.map { $0 ? t.peerLiveOK : t.peerLiveNo }
            return t.latencyLine(latencyText(latency), live.map { "\(roles)  ·  \($0)" } ?? roles)
        }
    }

    func latencyText(_ ms: Double?) -> String {
        guard let ms else { return t.measuring }
        return ms < 1 ? "<1 ms" : "\(Int(ms.rounded())) ms"
    }

    // MARK: Connection row (docs/design-links.md)

    /// The row under the header: the other Mac, the iPhones and their Apple Watch.
    var linkChips: [LinkChip] {
        var chips = [macChip]
        if let p = phoneChip { chips.append(p) }
        if let w = watchChip { chips.append(w) }
        if let d = deskChip { chips.append(d) }
        return chips
    }

    private var macChip: LinkChip {
        switch link {
        case let .connected(name, ms):
            let live = backupLiveConnected.map { $0 ? t.linkLiveOK : t.linkLiveNo }
            let detail = [live, latencyText(ms)].compactMap { $0 }.joined(separator: " · ")
            return LinkChip(kind: .mac, title: name, detail: detail, tone: backupLiveConnected == false ? .warning : .ok)
        case let .connecting(name, _):
            return LinkChip(kind: .mac, title: name, detail: t.connectingShort, tone: .warning)
        case .notConnected:
            return LinkChip(kind: .mac, title: t.linkOtherMac, detail: t.notConnected, tone: .idle)
        }
    }

    /// The backup (receiving) Mac shows the main Mac's iPhones when it has none of its own.
    private var mainMacPhones: RemoteSummary? {
        guard remoteClients == 0, !sendKeys, let p = peerRemote, p.phones > 0 else { return nil }
        return p
    }

    private var phoneChip: LinkChip? {
        if remoteClients > 0 {
            return LinkChip(kind: .phone, title: t.linkPhones(remoteClients), detail: "TwinKeys Remote", tone: .ok)
        }
        if let p = mainMacPhones {
            return LinkChip(kind: .phone, title: t.linkPhonesOnMain(p.phones), detail: "TwinKeys Remote", tone: .ok)
        }
        // Remote access off (or no pairing code, so nothing can connect): no iPhone chip at all.
        guard remoteEnabled, isPaired else { return nil }
        return LinkChip(kind: .phone, title: t.linkNoPhone, detail: t.linkAccepting, tone: .idle)
    }

    private var watchChip: LinkChip? {
        let level = remoteClients > 0 ? remoteWatch : (mainMacPhones?.watch ?? .absent)
        switch level {
        case .absent: return nil
        case .reachable: return LinkChip(kind: .watch, title: "Apple Watch", detail: t.linkViaPhone, tone: .ok)
        case .notReachable: return LinkChip(kind: .watch, title: "Apple Watch", detail: t.linkWatchNotReachable, tone: .warning)
        }
    }

    /// 2.4: the console, while the feature is on (both Macs connect to it).
    private var deskChip: LinkChip? {
        let d = deskSettings
        guard d.enabled else { return nil }
        let m = d.model.shortName
        func chip(_ connected: Bool, _ detail: String, _ tone: LinkChip.Tone) -> LinkChip {
            LinkChip(kind: .desk, title: t.deskChipTitle(m, connected: connected), detail: detail, tone: tone)
        }
        guard let snap = desk else { return chip(false, t.deskChipNotConnected, .warning) }
        switch snap.status {
        case .reading: return chip(true, t.deskChipReading, .ok)
        case let .fixedLevels(unconfirmed): return chip(!unconfirmed, t.deskChipFixed, .warning)
        case .stale: return chip(true, t.deskChipStale, .warning)
        case .checking: return chip(true, t.deskChipChecking, .idle)
        case .connecting: return chip(false, t.deskChipChecking, .idle)
        case .cannotRead: return chip(true, t.deskChipCannotMove, .warning)
        case .notReachable: return chip(false, t.deskChipNotConnected, .warning)
        }
    }
}

/// One item of the connection row.
struct LinkChip: Equatable, Identifiable {
    enum Kind { case mac, phone, watch, desk }
    enum Tone { case ok, warning, idle }
    var kind: Kind
    var title: String
    var detail: String
    var tone: Tone
    var id: Kind { kind }
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
    /// 2.3: make this Mac the main (after confirming) / give the role back.
    var becomeMain: () -> Void = {}
    var handOverMain: () -> Void = {}
    /// Opens the Settings window (macOS 13; from macOS 14 the window uses SettingsLink).
    var openSettings: () -> Void = {}
    /// 2.4: "Restore the console" (asks first) and closing the console banner.
    var restoreDesk: () -> Void = {}
    var dismissDeskBanner: () -> Void = {}
}

enum AppSheet: Equatable { case pairing, connectByIP, help }
#endif
