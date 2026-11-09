import CryptoKit
import Foundation
import Network
import Security
import SwiftUI
import TwinKeysCore
import UIKit

/// Everything the TwinKeys Remote screens show, and the connection to the main Mac.
@MainActor
final class RemoteModel: ObservableObject {
    enum Phase: Equatable {
        case needsCode
        case searching
        case connecting(String)
        case waitingForApproval(code: String)
        case connected(String)
        case denied
        case failed(String)
    }

    struct FoundMac: Identifiable, Equatable {
        let id: String          // Bonjour service name
        let endpoint: NWEndpoint
        static func == (a: FoundMac, b: FoundMac) -> Bool { a.id == b.id }
    }

    @Published var phase: Phase = .needsCode
    @Published var live = LiveState()
    @Published var status: RemoteStatus?
    @Published var macs: [FoundMac] = []
    @Published var pairingCode: String = ""
    /// Show lock: only playback, scenes, clips, cues and All Notes Off work.
    @Published var locked = false
    /// iPhone never moves a fader above 0 dB (Live's volume 0.85).
    @Published var capAtZeroDB = true { didSet { UserDefaults.standard.set(capAtZeroDB, forKey: "capAtZeroDB") } }
    @Published var followSelection = true { didSet { UserDefaults.standard.set(followSelection, forKey: "followSelection") } }
    @Published var lastResult: String?
    @Published var lastBackup: String?

    static let zeroDB = 0.85

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var session: RemoteSession?
    private var nextID = 0
    private var chosenMac: String?
    private var pingTimer: Timer?
    private let queue = DispatchQueue(label: "TwinKeysRemote.net")
    let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        capAtZeroDB = UserDefaults.standard.object(forKey: "capAtZeroDB") as? Bool ?? true
        followSelection = UserDefaults.standard.object(forKey: "followSelection") as? Bool ?? true
        if demo { loadDemo(); return }
        if let code = Keychain.load("pairingCode"), Pairing.normalize(code) != nil {
            pairingCode = code
            phase = .searching
        }
    }

    // MARK: Pairing and discovery

    func savePairingCode(_ raw: String) -> Bool {
        guard let n = Pairing.normalize(raw) else { return false }
        pairingCode = Pairing.formatted(n)
        Keychain.save("pairingCode", pairingCode)
        disconnect()
        phase = .searching
        startBrowsing()
        return true
    }

    func startBrowsing() {
        guard !demo, browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: RemoteProtocol.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let list = results.compactMap { r -> FoundMac? in
                if case let .service(name, _, _, _) = r.endpoint { return FoundMac(id: name, endpoint: r.endpoint) }
                return nil
            }.sorted { $0.id < $1.id }
            Task { @MainActor in self?.macs = list; self?.autoConnect() }
        }
        b.start(queue: queue)
        browser = b
    }

    /// Reconnect to the Mac used last time as soon as it is seen.
    private func autoConnect() {
        guard connection == nil, case .searching = phase,
              let last = UserDefaults.standard.string(forKey: "lastMac"),
              let mac = macs.first(where: { $0.id == last }) else { return }
        connect(mac)
    }

    func connect(_ mac: FoundMac) {
        guard let secret = PairingSecret(code: pairingCode) else { phase = .needsCode; return }
        disconnect()
        chosenMac = mac.id
        UserDefaults.standard.set(mac.id, forKey: "lastMac")
        phase = .connecting(mac.id)
        let s = RemoteSession(clientWith: secret, deviceKey: Self.deviceKey())
        session = s
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { tcp.noDelay = true }
        let c = NWConnection(to: mac.endpoint, using: params)
        connection = c
        c.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                switch st {
                case .ready:
                    c.send(content: Data(s.clientHello(deviceID: Self.deviceID(), deviceName: UIDevice.current.name)), completion: .idempotent)
                case let .failed(e):
                    self.fail("\(e)")
                case .cancelled:
                    break
                default: break
                }
            }
        }
        c.start(queue: queue)
        receive(c, s)
    }

    func disconnect() {
        connection?.cancel(); connection = nil; session = nil
        pingTimer?.invalidate(); pingTimer = nil
    }

    /// Forget the Mac and search again (or after the main Mac failed: pick the backup).
    func chooseAnotherMac() {
        UserDefaults.standard.removeObject(forKey: "lastMac")
        disconnect()
        phase = pairingCode.isEmpty ? .needsCode : .searching
        startBrowsing()
    }

    private func fail(_ why: String) {
        disconnect()
        phase = .failed(why)
        // Try again in a moment (the Mac may be restarting).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, case .failed = self.phase else { return }
            self.phase = .searching
            self.autoConnect()
        }
    }

    private nonisolated func receive(_ c: NWConnection, _ s: RemoteSession) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    let events = try s.receive(Array(data))
                    Task { @MainActor in for e in events { self.handle(e, c, s) } }
                } catch {
                    Task { @MainActor in self.fail(error is RemoteError && (error as! RemoteError) == .wrongPairingCode ? "code" : "\(error)") }
                    return
                }
            }
            if complete || error != nil {
                Task { @MainActor in if self.connection === c { self.fail("closed") } }
                return
            }
            self.receive(c, s)
        }
    }

    private func handle(_ e: RemoteSession.Event, _ c: NWConnection, _ s: RemoteSession) {
        guard connection === c else { return }
        switch e {
        case let .serverHello(_, code):
            // First sealed message proves our device key; the Mac then checks the approval.
            send(.ping(Date().timeIntervalSince1970))
            phase = .waitingForApproval(code: code)
        case .clientHello:
            fail("unexpected")
        case let .message(m):
            switch m {
            case let .waitingForApproval(code): phase = .waitingForApproval(code: code)
            case let .welcome(name):
                phase = .connected(name)
                UIApplication.shared.isIdleTimerDisabled = true    // keep the screen on during a show
                pingTimer?.invalidate()
                pingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.send(.ping(Date().timeIntervalSince1970)) }
                }
            case .denied: phase = .denied; disconnect()
            case let .update(u):
                live.apply(u)
            case let .status(st): status = st
            case let .result(_, ok, err, backup):
                lastResult = ok ? nil : (err ?? "error")
                lastBackup = backup
            default: break
            }
        }
    }

    private func send(_ m: RemoteMessage) {
        guard let s = session, let c = connection, let bytes = try? s.seal(m) else { return }
        c.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    // MARK: Actions (respect the show lock)

    var isConnected: Bool { if case .connected = phase { return true }; return demo }

    func run(_ cmd: LiveCommand) {
        guard !locked || cmd.allowedWhileLocked else { return }
        var cmd = cmd
        if capAtZeroDB, case let .setVolume(t, v) = cmd { cmd = .setVolume(track: t, value: min(v, Self.zeroDB)) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if demo { applyDemo(cmd); return }
        nextID += 1
        send(.command(id: nextID, cmd))
    }

    func cue(_ keycode: UInt16) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        nextID += 1
        send(.cue(id: nextID, keycode: keycode))
    }

    func allNotesOff() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        nextID += 1
        send(.allNotesOff(id: nextID))
    }

    // MARK: Device identity (kept on this device only)

    static func deviceID() -> String {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }

    static func deviceKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = Keychain.loadData("deviceKey"), let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) { return k }
        let k = Curve25519.KeyAgreement.PrivateKey()
        Keychain.saveData("deviceKey", k.rawRepresentation)
        return k
    }

    // MARK: Demo (screenshots and previews; fictional names)

    private func loadDemo() {
        pairingCode = "K7MQ2-WX9TP"
        phase = .connected("Main Stage Mac")
        var s = LiveState()
        s.song.tempo = 124; s.song.playing = true; s.song.beat = "17.3.1"; s.song.selectedScene = 2
        let names = ["オープニング", "SE 拍手", "M1 イントロ", "M1 本編", "暗転", "M2 イントロ", "M2 本編", "エンディング"]
        let colors = ["#E0533D", "#F0A030", "#3FA34D", "#2F7FD8", "#8E5CD6", "#D64F9A", "#E0533D", "#F0A030"]
        s.scenes = names.enumerated().map { LiveScene(index: $0.offset, name: $0.element, color: colors[$0.offset], playing: $0.offset == 2) }
        let tn = ["Music", "SE", "Amb", "Click", "Pad", "FX"]
        s.tracks = tn.enumerated().map { LiveTrack(index: $0.offset, name: $0.element, color: colors[$0.offset], volume: [0.78, 0.7, 0.6, 0, 0.66, 0.5][$0.offset], mute: $0.offset == 3, playingSlot: [2, -1, 2, -1, -1, -1][$0.offset]) }
        s.clips = tn.indices.map { t in names.indices.map { sc in
            let has = (sc * 3 + t) % 4 != 3
            return LiveClip(scene: sc, hasClip: has, name: has ? ["Intro", "Applause", "Pad", "Count", "Pad 2", "Riser"][t] : "", color: colors[t],
                            isPlaying: has && sc == 2 && (t == 0 || t == 2), lengthBeats: 64)
        } }
        s.progress = [0: [36, 64], 2: [12, 64]]
        s.meters = [0: [0.6, 0.62], 1: [0.4, 0.42], 2: [0.3, 0.3], 4: [0.5, 0.5], 5: [0.2, 0.25]]
        s.masterMeter = [0.7, 0.7]
        live = s
        status = RemoteStatus(mainName: "Main Stage Mac", mainLiveConnected: true, backupName: "Backup Stage Mac", backupLinked: true,
                              backupLiveConnected: true, latencyMs: 2,
                              lastCue: .init(label: "↓", memo: "次のシーン", count: 12, delivery: "delivered"),
                              cueKeys: [(0x7E, "↑", "前のシーン"), (0x7D, "↓", "次のシーン"), (0x7B, "←", ""), (0x7C, "→", ""),
                                        (0x31, "Space", "再生"), (0x24, "Return", "選んだシーン"), (0x35, "Esc", "停止"), (0x00, "A", "SE 拍手"), (0x0B, "B", "SE 歓声")]
                                .map { .init(keycode: $0.0, label: $0.1, memo: $0.2) })
    }

    private func applyDemo(_ cmd: LiveCommand) {
        switch cmd {
        case let .setVolume(t, v) where t >= 0 && t < live.tracks.count: live.tracks[t].volume = v
        case let .setVolume(-1, v): live.master.volume = v
        case let .setMute(t, on) where t < live.tracks.count: live.tracks[t].mute = on
        case let .setSolo(t, on) where t < live.tracks.count: live.tracks[t].solo = on
        case .play: live.song.playing = true
        case .stop: live.song.playing = false
        default: break
        }
    }
}

/// Small keychain helper (pairing code and the device key never go to UserDefaults).
enum Keychain {
    static func save(_ key: String, _ value: String) { saveData(key, Data(value.utf8)) }
    static func load(_ key: String) -> String? { loadData(key).flatMap { String(data: $0, encoding: .utf8) } }

    static func saveData(_ key: String, _ data: Data) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TwinKeysRemote", kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadData(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TwinKeysRemote",
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
}
