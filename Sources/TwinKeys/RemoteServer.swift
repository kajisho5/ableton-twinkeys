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
    /// One approval question at a time, with a time limit and a pause after a refusal.
    private var gate = RemoteApprovalGate()
    private var sweeper: DispatchSourceTimer?
    /// An approved device that sends nothing for this long is gone (it pings every 2 s).
    static let idleLimit: Double = 8
    /// Bytes queued to one device: above `slowLimit` meters and clip progress are skipped for it,
    /// above `dropLimit` it is disconnected.
    static let slowLimit = 1 << 20
    static let dropLimit = 8 << 20

    // Hooks, set by AppModel. Called on `queue` unless noted.
    /// Is this device approved? (reads settings; thread-safe closure)
    var isApproved: (RemoteClientHello) -> Bool = { _ in false }
    /// Ask the person on the main thread; call the answer closure with true to allow. `token`
    /// names this question: an answer is only ever applied to the question it was shown for.
    var askApproval: (_ token: Int, _ name: String, _ code: String, _ answer: @escaping (Bool) -> Void) -> Void = { _, _, _, a in a(false) }
    /// The question `token` is over without an answer (time limit, or the device left): close its
    /// alert (main thread).
    var cancelApproval: (_ token: Int) -> Void = { _ in }
    /// Runs a command from the iPhone; `done(ok, error, backupDelivery)`.
    /// `late(ok)`: Live answered after the 1 s limit (the iPhone was told "no answer").
    var runCommand: (LiveCommand, @escaping (Bool, String?, String) -> Void, @escaping (Bool) -> Void) -> Void = { _, d, _ in d(false, "not ready", "notSent") }
    /// Live's track/scene layout as this Mac knows it now (`LiveSong.structure`).
    var currentStructure: () -> Int? = { nil }
    /// Number of scenes in Live as this Mac knows it.
    var currentSceneCount: () -> Int? = { nil }
    var pressCue: (UInt16) -> Bool = { _ in false }
    /// An approved iPhone asks this Mac to become the main (2.3).
    var becomeMain: () -> Void = {}
    var allNotesOff: () -> Void = {}
    var snapshot: () -> LiveState = { LiveState() }
    var status: () -> RemoteStatus? = { nil }
    var onLog: ((String) -> Void)?
    /// Number of connected, approved devices changed (main thread).
    var onClientsChanged: ((Int) -> Void)?
    /// Connection display: the Apple Watch as the connected iPhones report it, combined (main thread).
    var onWatchChanged: ((WatchLevel) -> Void)?
    /// A device was allowed on this Mac: remember it (called on `queue`).
    var onApproved: (RemoteClientHello) -> Void = { _ in }

    private final class Client {
        let conn: NWConnection
        let session: RemoteSession
        var hello: RemoteClientHello?
        var code = ""
        var proven = false
        var approved = false
        /// The approval question open for this connection.
        var approvalToken: Int?
        /// The iPhone's show lock (`RemoteMessage.lock` / `.lockScope`) and what it stops.
        var locked = false
        var lockScope: LockScope = .standard
        var lastHeard = ProcessInfo.processInfo.systemUptime
        /// Bytes handed to the connection and not yet sent.
        var inFlight = 0
        /// The layout (`LiveSong.structure`) of the last state sent to this iPhone.
        var seenStructure: Int?
        /// Its Apple Watch, as it last reported (nil: not told; iPhones before the connection display).
        var watch: RemoteWatchState?
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
            if pairing != nil { self.startListener(); self.startSweeper() }
        }
    }

    func stop() {
        queue.sync { stopped = true; dropAll(); listener?.cancel(); listener = nil; sweeper?.cancel(); sweeper = nil }
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
        // Keepalive: a phone that vanished (Wi-Fi gone, battery) is noticed by TCP too.
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let p = NWParameters(tls: nil, tcp: tcp)
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
                client.lastHeard = ProcessInfo.processInfo.systemUptime
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
        let token: Int
        switch gate.request(deviceID: hello.deviceID, now: ProcessInfo.processInfo.systemUptime) {
        case let .ask(t): token = t
        case .busy:
            // Another device is being asked about: refuse quietly (no second alert).
            onLog?("Remote: \(hello.deviceName) refused (another device is waiting for approval)")
            close(key, c); return
        case .coolingDown:
            // Refused a moment ago: no new alert.
            close(key, c); return
        }
        c.approvalToken = token
        send(.waitingForApproval(code: c.code), to: c)
        onLog?("Remote: \(hello.deviceName) asks to connect (code \(c.code))")
        let name = hello.deviceName, code = c.code
        queue.asyncAfter(deadline: .now() + RemoteApprovalGate.timeout) { [weak self] in
            guard let self, self.gate.isExpired(token: token, now: ProcessInfo.processInfo.systemUptime + 0.5) else { return }
            self.onLog?("Remote: \(name) was not allowed in time")
            self.answered(token, key, allow: false)
            DispatchQueue.main.async { [weak self] in self?.cancelApproval(token) }
        }
        DispatchQueue.main.async { [weak self] in
            self?.askApproval(token, name, code) { allow in
                self?.queue.async { self?.answered(token, key, allow: allow) }
            }
        }
    }

    /// The approval question `token` ended. Ignored unless it is still the open question.
    private func answered(_ token: Int, _ key: ObjectIdentifier, allow: Bool) {
        guard gate.finish(token: token, allowed: allow, now: ProcessInfo.processInfo.systemUptime) else { return }
        guard let c = clients[key], c.approvalToken == token else { return }
        c.approvalToken = nil
        if allow, let h = c.hello { onApproved(h); welcome(c) } else { send(.denied, to: c); close(key, c) }
    }

    /// The connection is going away: an open question about it ends (refused) and its alert closes.
    private func endApproval(_ c: Client) {
        guard let token = c.approvalToken else { return }
        c.approvalToken = nil
        if gate.finish(token: token, allowed: false, now: ProcessInfo.processInfo.systemUptime) {
            DispatchQueue.main.async { [weak self] in self?.cancelApproval(token) }
        }
    }

    /// Once a second: drop approved devices that went quiet.
    private func startSweeper() {
        guard sweeper == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for (k, c) in self.clients where c.approved && now - c.lastHeard > Self.idleLimit {
                self.onLog?("Remote: \(c.hello?.deviceName ?? "?") stopped answering; disconnected")
                self.close(k, c)
            }
        }
        t.resume()
        sweeper = t
    }

    private func welcome(_ c: Client) {
        c.approved = true
        c.lastHeard = ProcessInfo.processInfo.systemUptime
        send(.welcome(macName: serverName), to: c)
        // In pieces (one clip column per message): a big set in one message could pass the
        // receive limit on the iPhone.
        for u in snapshot().initialUpdates() { send(.update(u), to: c) }
        if let s = status() { send(.status(s), to: c) }
        onLog?("Remote: \(c.hello?.deviceName ?? "?") connected")
        notifyCount()
    }

    private func handleMessage(_ m: RemoteMessage, _ c: Client) {
        switch m {
        case let .command(id, cmd):
            runFromPhone(id, cmd, seen: c.seenStructure, c)
        case let .commandAt(id, cmd, structure):
            runFromPhone(id, cmd, seen: structure ?? c.seenStructure, c)
        case let .go(id, scene, structure):
            // GO is never stopped by the show lock: launch the scene, then select the next one.
            runFromPhone(id, .fireScene(scene), seen: structure ?? c.seenStructure, c, isGo: true)
            if scene + 1 < (currentSceneCount() ?? Int.max) {
                runFromPhone(-1, .selectScene(scene + 1), seen: structure ?? c.seenStructure, c, isGo: true)
            }
        case let .becomeMain(id):
            onLog?("Remote: \(c.hello?.deviceName ?? "?"): make this Mac the main")
            becomeMain()
            send(.result(id: id, ok: true, error: nil, backup: "notSent"), to: c)
        case let .cue(id, keycode):
            if c.locked, c.lockScope.contains(.cues) { send(.result(id: id, ok: false, error: "locked", backup: "notSent"), to: c); return }
            let ok = pressCue(keycode)
            onLog?("Remote: \(c.hello?.deviceName ?? "?"): cue key \(keycode)\(ok ? "" : " (not a cue key)")")
            send(.result(id: id, ok: ok, error: ok ? nil : "not a cue key", backup: "see status"), to: c)
        case let .allNotesOff(id):
            onLog?("Remote: \(c.hello?.deviceName ?? "?"): All Notes Off")
            allNotesOff()
            send(.result(id: id, ok: true, error: nil, backup: "sent"), to: c)
        case let .ping(t, watch):
            send(.pong(t), to: c)
            // Connection display: the iPhone's Apple Watch comes with its pings.
            if let watch, watch != c.watch {
                c.watch = watch
                notifyCount()
            }
        case let .lock(on):
            if c.locked != on { onLog?("Remote: \(c.hello?.deviceName ?? "?"): show lock \(on ? "on" : "off")") }
            c.locked = on
            c.lockScope = .standard
        case let .lockScope(on, scope):
            if c.locked != on { onLog?("Remote: \(c.hello?.deviceName ?? "?"): show lock \(on ? "on" : "off")") }
            c.locked = on
            c.lockScope = LockScope(rawValue: scope)
        default:
            break
        }
    }

    /// A Live command from an iPhone. `seen`: the Live layout the iPhone was showing.
    /// `isGo`: part of GO (never stopped by the show lock). `id` -1: no answer to the iPhone.
    private func runFromPhone(_ id: Int, _ cmd: LiveCommand, seen: Int?, _ c: Client, isGo: Bool = false) {
        guard cmd.isValid else { if id >= 0 { send(.result(id: id, ok: false, error: "invalid", backup: "notSent"), to: c) }; return }
        // The show lock is enforced here too, not only on the iPhone.
        guard isGo || !c.locked || !c.lockScope.blocks(cmd) else {
            if id >= 0 { send(.result(id: id, ok: false, error: "locked", backup: "notSent"), to: c) }
            return
        }
        // Operation log (fader and tempo moves are too many to log one by one).
        let who = c.hello?.deviceName ?? "?"
        if !cmd.isContinuous { onLog?("Remote: \(who): \(cmd)") }
        // The iPhone was showing an older layout than Live has now: refuse before anything is
        // sent to either Live (the backup would otherwise run it while this Mac refuses it).
        if cmd.targetsLayout, let seen, let now = currentStructure(), seen != now {
            onLog?("Remote: \(who): \(cmd) not run (Live's layout changed)")
            if id >= 0 { send(.result(id: id, ok: false, error: "structure_changed", backup: "notSent"), to: c) }
            return
        }
        runCommand(cmd, { [weak self] ok, err, backup in
            if !ok, !cmd.isContinuous { self?.onLog?("Remote: \(who): \(cmd) not run (\(err ?? "error"))") }
            if id >= 0 { self?.queue.async { self?.send(.result(id: id, ok: ok, error: err, backup: backup), to: c) } }
        }, { [weak self] ok in
            guard ok, id >= 0 else { return }
            // Live ran it after all: the iPhone must not think it failed (no second tap).
            self?.onLog?("Remote: \(who): \(cmd) ran late")
            self?.queue.async { self?.send(.result(id: id, ok: true, error: "late", backup: "unknown"), to: c) }
        })
    }

    private func send(_ m: RemoteMessage, to c: Client) {
        guard let bytes = try? c.session.seal(m) else { return }
        if case let .update(u) = m {
            switch u {
            case let .song(x): c.seenStructure = x.structure
            case let .full(s): c.seenStructure = s.song.structure
            default: break
            }
        }
        let n = bytes.count
        c.inFlight += n
        // Completion runs on `queue` (the connection's queue).
        c.conn.send(content: Data(bytes), completion: .contentProcessed { _ in c.inFlight -= n })
    }

    private func sendAll(_ m: RemoteMessage) {
        var skippable = false
        if case let .update(u) = m {
            switch u {
            case .meters, .progress: skippable = true
            default: break
            }
        }
        for (k, c) in clients where c.approved {
            if c.inFlight > Self.dropLimit {
                onLog?("Remote: \(c.hello?.deviceName ?? "?") is not keeping up; disconnected")
                close(k, c)
                continue
            }
            // A slow device skips meters and clip progress (newer ones follow) until it catches up.
            if skippable && c.inFlight > Self.slowLimit { continue }
            send(m, to: c)
        }
    }

    private func close(_ key: ObjectIdentifier, _ c: Client) {
        c.conn.cancel()
        forget(key)
    }

    private func forget(_ key: ObjectIdentifier) {
        if let c = clients.removeValue(forKey: key) { endApproval(c); notifyCount() }
    }

    private func dropAll() {
        for c in clients.values { endApproval(c); c.conn.cancel() }
        clients.removeAll()
        notifyCount()
    }

    private func notifyCount() {
        let approved = clients.values.filter(\.approved)
        let n = approved.count
        let watch = WatchLevel.combined(approved.map(\.watch))
        DispatchQueue.main.async { [weak self] in
            self?.onClientsChanged?(n)
            self?.onWatchChanged?(watch)
        }
    }
}
#endif
