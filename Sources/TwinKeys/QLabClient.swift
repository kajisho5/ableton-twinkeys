#if os(macOS)
import Foundation
import Network
import Security
import TwinKeysCore

/// QLab mode (docs/design-qlab.md 5.1, 5.2): this Mac's QLab over OSC on TCP 127.0.0.1:53000 (SLIP).
/// The connection steps, reads and commands are QLabEngine (TwinKeysCore, tested against
/// scripts/fake-qlab.py); this class only gives it the TCP connection, retried every 1 s, then up
/// to every 5 s, while QLab is not open. Like LiveBridgeClient, it talks to this Mac only.
final class QLabClient {
    let queue = DispatchQueue(label: "TwinKeys.qlab", qos: .userInitiated)
    private var engine: QLabEngine!
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var running = false
    private var port: UInt16 = 53000
    private var retryDelay = 1.0
    /// Snapshot copy for other threads.
    private let lock = NSLock()
    private var current = QLabEngineSnapshot()

    var onLog: ((String) -> Void)?
    /// Something changed (called on `queue`).
    var onChange: ((QLabEngineSnapshot) -> Void)?
    /// QLab chose the only workspace open (remember it in the settings; called on `queue`).
    var onWorkspaceChosen: ((QLabWorkspaceInfo) -> Void)?

    init() {
        engine = QLabEngine(config: .init(), clock: { ProcessInfo.processInfo.systemUptime })
        engine.log = { [weak self] in self?.onLog?($0) }
        engine.onChange = { [weak self] in self?.changed() }
        engine.onWorkspaceChosen = { [weak self] in self?.onWorkspaceChosen?($0) }
        engine.send = { [weak self] bytes in self?.connection?.send(content: Data(bytes), completion: .idempotent) }
    }

    /// Starts (or changes) the link. `on` false: Ableton Live mode, nothing is opened.
    func configure(on: Bool, settings: QLabSettings, passcode: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.engine.setConfig(.init(workspaceID: settings.workspaceID, workspaceName: settings.workspaceName, passcode: passcode))
            let portChanged = settings.port != self.port
            self.port = settings.port
            if on && !self.running {
                self.running = true
                self.startTimer()
                self.connect()
            } else if !on && self.running {
                self.running = false
                self.timer?.cancel(); self.timer = nil
                self.connection?.cancel(); self.connection = nil
                self.engine.transportClosed()
                self.changed()
            } else if on && portChanged {
                self.connection?.cancel()
            }
        }
    }

    func stop() { configure(on: false, settings: QLabSettings(), passcode: "") }

    /// What this Mac's QLab looks like now (any thread).
    func snapshot() -> QLabEngineSnapshot { lock.lock(); defer { lock.unlock() }; return current }

    /// Runs a command; `done` on `queue`.
    func run(_ cmd: QLabCommand, asBackup: Bool, done: @escaping (QLabResultCode) -> Void) {
        queue.async { [weak self] in
            guard let self, self.running else { done(.notConnected); return }
            self.engine.run(cmd, asBackup: asBackup, done: done)
        }
    }

    func follow(_ number: String?) {
        queue.async { [weak self] in _ = self?.engine.follow(mainNumber: number) }
    }

    // MARK: Inside (on queue)

    private func changed() {
        let s = engine.snapshot
        lock.lock(); current = s; lock.unlock()
        onChange?(s)
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.engine.tick() }
        t.resume()
        timer = t
    }

    private func connect() {
        guard running, connection == nil, let p = NWEndpoint.Port(rawValue: port) else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        // This Mac only: never another interface.
        params.requiredInterfaceType = .loopback
        let c = NWConnection(host: "127.0.0.1", port: p, using: params)
        connection = c
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self, let c, self.connection === c else { return }
            switch st {
            case .ready:
                self.retryDelay = 1
                self.onLog?("QLab: TCP 127.0.0.1:\(self.port) connected")
                self.engine.transportConnected()
                self.receive(c)
            case .failed, .waiting:
                c.cancel()
            case .cancelled:
                self.closed(c)
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self, weak c] data, _, complete, error in
            guard let self, let c, self.connection === c else { return }
            if let data, !data.isEmpty { self.engine.received(Array(data)) }
            if complete || error != nil { c.cancel(); return }
            self.receive(c)
        }
    }

    private func closed(_ c: NWConnection) {
        guard connection === c else { return }
        connection = nil
        engine.transportClosed()
        guard running else { return }
        // QLab not open (or it quit): try again in 1 s, then up to every 5 s.
        let wait = retryDelay
        retryDelay = min(5, retryDelay + 1)
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.connect() }
    }
}

/// The QLab passcode in this Mac's keychain (never in settings.json, never sent to the other Mac).
enum QLabPasscodeStore {
    private static let service = "io.github.kajisho5.twinkeys"
    private static let account = "qlab-passcode"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ code: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !code.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(code.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "TwinKeys QLab passcode"
        SecItemAdd(add as CFDictionary, nil)
    }
}
#endif
