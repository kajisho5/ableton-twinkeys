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
    @Published var locked = false { didSet { if locked != oldValue, isConnected, !demo { send(.lock(locked)) } } }
    /// iPhone never moves a fader above 0 dB (Live's volume 0.85).
    @Published var capAtZeroDB = true { didSet { UserDefaults.standard.set(capAtZeroDB, forKey: "capAtZeroDB") } }
    @Published var followSelection = true { didSet { UserDefaults.standard.set(followSelection, forKey: "followSelection") } }
    @Published var lastResult: String? {
        didSet {
            guard lastResult != nil else { return }
            let shown = lastResult
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.lastResult == shown { self?.lastResult = nil }
            }
        }
    }
    @Published var lastBackup: String?

    static let zeroDB = 0.85

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var session: RemoteSession?
    private var nextID = 0
    private var chosenMac: String?
    private var pingTimer: Timer?
    /// When anything last arrived from the Mac (a dead Wi-Fi link gives no error for minutes).
    private var lastHeard = Date()
    /// Continuous controls (faders, tempo): the last value sent and when, plus the newest one waiting.
    private var lastContinuous: [String: (value: Double, at: Date)] = [:]
    private var pendingContinuous: [String: LiveCommand] = [:]
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
        b.stateUpdateHandler = { [weak self] st in
            guard case .failed = st else { return }
            Task { @MainActor in
                guard let self, self.browser === b else { return }
                b.cancel(); self.browser = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startBrowsing() }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    /// Back from the background: look again and check that the link still answers.
    func appBecameActive() {
        guard !demo else { return }
        startBrowsing()
        switch phase {
        case .connected: send(.ping(Date().timeIntervalSince1970))
        case .searching: autoConnect()
        default: break
        }
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
                    self.lastHeard = Date()
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
        // A Mac that is listed but cannot be reached leaves the connection waiting forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.connection === c, case .connecting = self.phase else { return }
            self.fail("timeout")
        }
    }

    func disconnect() {
        connection?.cancel(); connection = nil; session = nil
        pingTimer?.invalidate(); pingTimer = nil
        pendingContinuous = [:]; lastContinuous = [:]
        UIApplication.shared.isIdleTimerDisabled = false
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
        // A wrong pairing code does not fix itself: wait until a new code is saved.
        if why == "code" { return }
        // Try again in a moment (the Mac may be restarting).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, case .failed = self.phase else { return }
            self.phase = .searching
            self.startBrowsing()
            self.autoConnect()
        }
    }

    private nonisolated func receive(_ c: NWConnection, _ s: RemoteSession) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    let events = try s.receive(Array(data))
                    // DispatchQueue.main keeps the order of arrival (separate Tasks may not).
                    DispatchQueue.main.async { MainActor.assumeIsolated { for e in events { self.handle(e, c, s) } } }
                } catch {
                    let why = (error as? RemoteError) == .wrongPairingCode ? "code" : "\(error)"
                    DispatchQueue.main.async { MainActor.assumeIsolated { if self.connection === c { self.fail(why) } } }
                    return
                }
            }
            if complete || error != nil {
                DispatchQueue.main.async { MainActor.assumeIsolated { if self.connection === c { self.fail("closed") } } }
                return
            }
            self.receive(c, s)
        }
    }

    private func handle(_ e: RemoteSession.Event, _ c: NWConnection, _ s: RemoteSession) {
        guard connection === c else { return }
        lastHeard = Date()
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
                send(.lock(locked))
                pingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        // Nothing heard for 7 s (pings are answered every 2 s): the link is gone.
                        if Date().timeIntervalSince(self.lastHeard) > 7 { self.fail("timeout"); return }
                        self.send(.ping(Date().timeIntervalSince1970))
                    }
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
        if demo { applyDemo(cmd); return }
        if let (key, value) = Self.continuousKey(cmd) {
            // Faders move at 60–120 Hz: send at most 20 per second per control, and never the same value twice.
            if let last = lastContinuous[key], abs(last.value - value) < 0.001 { return }
            let wait = 0.05 - Date().timeIntervalSince(lastContinuous[key]?.at ?? .distantPast)
            if wait > 0 {
                let first = pendingContinuous[key] == nil
                pendingContinuous[key] = cmd
                if first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                        guard let self, let c = self.pendingContinuous.removeValue(forKey: key) else { return }
                        self.sendContinuous(c, key, value: Self.continuousKey(c)?.1 ?? value)
                    }
                }
                return
            }
            sendContinuous(cmd, key, value: value)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        nextID += 1
        send(.command(id: nextID, cmd))
    }

    private func sendContinuous(_ cmd: LiveCommand, _ key: String, value: Double) {
        lastContinuous[key] = (value, Date())
        nextID += 1
        send(.command(id: nextID, cmd))
    }

    private static func continuousKey(_ cmd: LiveCommand) -> (String, Double)? {
        switch cmd {
        case let .setVolume(t, v): return ("v\(t)", v)
        case let .setPan(t, v): return ("p\(t)", v)
        case let .setSend(t, k, v): return ("send\(k)/\(t)", v)
        case let .setTempo(b): return ("tempo", b)
        default: return nil
        }
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
        let (raw, status) = Keychain.loadDataStatus("deviceKey")
        if let raw, let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) { return k }
        let k = Curve25519.KeyAgreement.PrivateKey()
        // Replace the stored key only when there is none: a passing Keychain error must not
        // throw away the key the Mac already allowed (the iPhone would need approval again).
        if status == errSecItemNotFound { Keychain.saveData("deviceKey", k.rawRepresentation) }
        return k
    }

    // MARK: Demo (screenshots and previews; fictional names)

    private func loadDemo() {
        pairingCode = "K7MQ2-WX9TP"
        phase = .connected("Main Stage Mac")
        var s = LiveState()
        s.song.tempo = 124; s.song.playing = true; s.song.beat = "17.3.1"; s.song.selectedScene = 3
        let names = ["オープニング", "SE 拍手", "M1 イントロ", "M1 本編", "暗転", "M2 イントロ", "M2 本編", "エンディング"]
        let colors = ["#E0533D", "#F0A030", "#3FA34D", "#2F7FD8", "#8E5CD6", "#D64F9A", "#E0533D", "#F0A030"]
        s.scenes = names.enumerated().map { LiveScene(index: $0.offset, name: $0.element, color: colors[$0.offset], playing: $0.offset == 2) }
        let tn = ["Music", "SE", "Amb", "Click", "Pad", "FX"]
        // Two return tracks: every track has Send A and Send B.
        let sends: [[Double]] = [[0.45, 0.2], [0.3, 0], [0.6, 0.35], [0, 0], [0.7, 0.5], [0.25, 0.8]]
        s.tracks = tn.enumerated().map { LiveTrack(index: $0.offset, name: $0.element, color: colors[$0.offset], volume: [0.78, 0.7, 0.6, 0, 0.66, 0.5][$0.offset], mute: $0.offset == 3, playingSlot: [2, -1, 2, -1, -1, -1][$0.offset], sends: sends[$0.offset]) }
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
                                .map { .init(keycode: $0.0, label: $0.1, memo: $0.2) },
                              // `-setdiff` shows the warning for a different backup set (screenshots).
                              setDiff: ProcessInfo.processInfo.arguments.contains("-setdiff")
                                ? SetDiff(mainTracks: 6, backupTracks: 5, mainScenes: 8, backupScenes: 8, differences: 2,
                                          rows: [.init(kind: "track", index: 5, main: "FX", backup: nil),
                                                 .init(kind: "scene", index: 6, main: "M2 本編", backup: "M2 本編 v2")],
                                          complete: true)
                                : nil)
    }

    private func applyDemo(_ cmd: LiveCommand) {
        switch cmd {
        case let .setVolume(t, v) where t >= 0 && t < live.tracks.count: live.tracks[t].volume = v
        case let .setVolume(-1, v): live.master.volume = v
        case let .setSend(t, k, v) where t >= 0 && t < live.tracks.count && k >= 0 && k < live.tracks[t].sends.count: live.tracks[t].sends[k] = v
        case let .setMute(t, on) where t < live.tracks.count: live.tracks[t].mute = on
        case let .setSolo(t, on) where t < live.tracks.count: live.tracks[t].solo = on
        case .play: live.song.playing = true
        case .stop: live.song.playing = false
        case let .selectScene(i) where i >= 0 && i < live.scenes.count: live.song.selectedScene = i
        case let .fireScene(i) where i >= 0 && i < live.scenes.count:
            for k in live.scenes.indices { live.scenes[k].playing = k == i }
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

    static func loadData(_ key: String) -> Data? { loadDataStatus(key).0 }

    static func loadDataStatus(_ key: String) -> (Data?, OSStatus) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TwinKeysRemote",
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        return (st == errSecSuccess ? out as? Data : nil, st)
    }
}
