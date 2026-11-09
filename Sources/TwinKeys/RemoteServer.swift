#if os(macOS)
import Foundation
import Network
import TwinKeysCore

/// Waits for TwinKeys Remote (iPhone / iPad) on TCP, advertised with Bonjour. Every connection
/// must know the pairing code, prove its device key, and be approved on this Mac once.
final class RemoteServer {
    let queue = DispatchQueue(label: "TwinKeys.remote", qos: .userInitiated)
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var pairing: PairingSecret?
    private let serverID: String
    private var serverName: String
    private var stopped = true

    // Hooks, set by AppModel. Called on `queue` unless noted.
    /// Is this device approved? (reads settings; thread-safe closure)
    var isApproved: (RemoteClientHello) -> Bool = { _ in false }
    /// Ask the person on the main thread; call the answer closure with true to allow.
    var askApproval: (_ name: String, _ code: String, _ answer: @escaping (Bool) -> Void) -> Void = { _, _, a in a(false) }
    /// Runs a command from the iPhone; `done(ok, error, backupDelivery)`.
    var runCommand: (LiveCommand, @escaping (Bool, String?, String) -> Void) -> Void = { _, d in d(false, "not ready", "notSent") }
    var pressCue: (UInt16) -> Bool = { _ in false }
    var allNotesOff: () -> Void = {}
    var snapshot: () -> LiveState = { LiveState() }
    var status: () -> RemoteStatus? = { nil }
    var onLog: ((String) -> Void)?
    /// Number of connected, approved devices changed (main thread).
    var onClientsChanged: ((Int) -> Void)?
    /// A device was allowed on this Mac: remember it (called on `queue`).
    var onApproved: (RemoteClientHello) -> Void = { _ in }

    private final class Client {
        let conn: NWConnection
        let session: RemoteSession
        var hello: RemoteClientHello?
        var code = ""
        var proven = false
        var approved = false
        init(conn: NWConnection, session: RemoteSession) { self.conn = conn; self.session = session }
    }

    init(serverID: String, serverName: String) {
        self.serverID = serverID; self.serverName = serverName
    }

    /// Starts (or restarts) with this pairing code. nil stops it: nothing works without a code.
    func configure(pairing: PairingSecret?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pairing = pairing
            self.dropAll()
            self.listener?.cancel(); self.listener = nil
            self.stopped = pairing == nil
            if pairing != nil { self.startListener() }
        }
    }

    func stop() {
        queue.sync { stopped = true; dropAll(); listener?.cancel(); listener = nil }
    }

    /// Sends a Live change to every approved device.
    func broadcast(_ u: LiveUpdate) { queue.async { [weak self] in self?.sendAll(.update(u)) } }

    func broadcastStatus() {
        queue.async { [weak self] in
            guard let self, let s = self.status() else { return }
            self.sendAll(.status(s))
        }
    }

    /// A device was removed from the approved list: disconnect it.
    func revoke(deviceID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for (k, c) in self.clients where c.hello?.deviceID == deviceID { self.close(k, c) }
        }
    }

    // MARK: Internals (on queue)

    private func startListener() {
        guard !stopped else { return }
        let p = NWParameters.tcp
        p.includePeerToPeer = false
        guard let l = try? NWListener(using: p) else {
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startListener() }
            return
        }
        l.service = NWListener.Service(name: serverName, type: RemoteProtocol.serviceType)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self, weak l] s in
            guard let self else { return }
            switch s {
            case .ready: self.onLog?("Remote: waiting for iPhones on TCP port \(l?.port?.rawValue ?? 0)")
            case let .failed(e):
                self.onLog?("Remote: listener failed (\(e)); retrying")
                l?.cancel()
                self.queue.asyncAfter(deadline: .now() + 3) { self.startListener() }
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func accept(_ c: NWConnection) {
        guard let pairing, clients.count < 8 else { c.cancel(); return }
        let client = Client(conn: c, session: RemoteSession(serverWith: pairing))
        let key = ObjectIdentifier(c)
        clients[key] = client
        c.stateUpdateHandler = { [weak self] s in
            switch s {
            case .failed, .cancelled: self?.forget(key)
            default: break
            }
        }
        c.start(queue: queue)
        receive(key, client)
        // Must finish the handshake quickly.
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, let cl = self.clients[key], !cl.proven else { return }
            self.close(key, cl)
        }
    }

    private func receive(_ key: ObjectIdentifier, _ client: Client) {
        client.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, self.clients[key] != nil else { return }
            if let data, !data.isEmpty {
                do {
                    for e in try client.session.receive(Array(data)) { self.handle(e, key, client) }
                } catch {
                    self.onLog?("Remote: closed a connection (\(error))")
                    self.close(key, client)
                    return
                }
            }
            if complete || error != nil { self.close(key, client); return }
            self.receive(key, client)
        }
    }

    private func handle(_ e: RemoteSession.Event, _ key: ObjectIdentifier, _ c: Client) {
        switch e {
        case let .clientHello(hello, code):
            c.hello = hello; c.code = code
            guard let sh = try? c.session.serverHello(serverID: serverID, serverName: serverName) else { close(key, c); return }
            c.conn.send(content: Data(sh), completion: .idempotent)
        case .serverHello:
            close(key, c)      // only clients send this
        case let .message(m):
            if !c.proven {
                // The first sealed message proves the device holds its key.
                c.proven = true
                decideApproval(key, c)
            }
            guard c.approved else { return }
            handleMessage(m, c)
        }
    }

    private func decideApproval(_ key: ObjectIdentifier, _ c: Client) {
        guard let hello = c.hello else { close(key, c); return }
        if isApproved(hello) { welcome(c); return }
        send(.waitingForApproval(code: c.code), to: c)
        onLog?("Remote: \(hello.deviceName) asks to connect (code \(c.code))")
        let name = hello.deviceName
        DispatchQueue.main.async { [weak self] in
            self?.askApproval(name, c.code) { allow in
                self?.queue.async {
                    guard let self, self.clients[key] != nil else { return }
                    if allow, let h = c.hello { self.onApproved(h); self.welcome(c) } else { self.send(.denied, to: c); self.close(key, c) }
                }
            }
        }
    }

    private func welcome(_ c: Client) {
        c.approved = true
        send(.welcome(macName: serverName), to: c)
        send(.update(.full(snapshot())), to: c)
        if let s = status() { send(.status(s), to: c) }
        onLog?("Remote: \(c.hello?.deviceName ?? "?") connected")
        notifyCount()
    }

    private func handleMessage(_ m: RemoteMessage, _ c: Client) {
        switch m {
        case let .command(id, cmd):
            guard cmd.isValid else { send(.result(id: id, ok: false, error: "invalid", backup: "notSent"), to: c); return }
            runCommand(cmd) { [weak self] ok, err, backup in
                self?.queue.async { self?.send(.result(id: id, ok: ok, error: err, backup: backup), to: c) }
            }
        case let .cue(id, keycode):
            let ok = pressCue(keycode)
            send(.result(id: id, ok: ok, error: ok ? nil : "not a cue key", backup: "see status"), to: c)
        case let .allNotesOff(id):
            allNotesOff()
            send(.result(id: id, ok: true, error: nil, backup: "sent"), to: c)
        case let .ping(t):
            send(.pong(t), to: c)
        default:
            break
        }
    }

    private func send(_ m: RemoteMessage, to c: Client) {
        guard let bytes = try? c.session.seal(m) else { return }
        c.conn.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    private func sendAll(_ m: RemoteMessage) {
        for c in clients.values where c.approved { send(m, to: c) }
    }

    private func close(_ key: ObjectIdentifier, _ c: Client) {
        c.conn.cancel()
        forget(key)
    }

    private func forget(_ key: ObjectIdentifier) {
        if clients.removeValue(forKey: key) != nil { notifyCount() }
    }

    private func dropAll() {
        for c in clients.values { c.conn.cancel() }
        clients.removeAll()
        notifyCount()
    }

    private func notifyCount() {
        let n = clients.values.filter(\.approved).count
        DispatchQueue.main.async { [weak self] in self?.onClientsChanged?(n) }
    }
}
#endif
