#if os(macOS)
import Foundation
import Network
import TwinKeysCore

/// Talks to the TwinKeys Bridge Remote Script inside Live, on this Mac only (127.0.0.1).
/// Commands go to UDP 47811; the script sends state and answers to UDP 47812.
final class LiveBridgeClient {
    static let commandPort: UInt16 = 47811
    static let statePort: UInt16 = 47812

    let queue = DispatchQueue(label: "TwinKeys.bridge", qos: .userInitiated)
    private var listener: NWListener?
    private var sender: NWConnection?
    /// The script's socket we hear from (one at a time; a new source replaces the old one).
    private var receiver: NWConnection?
    private var nextID = 0
    private var lastHeard = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var stopped = false
    /// Accessed on `queue`.
    private(set) var state = LiveState()

    /// Called on `queue` with each change (send it to the iPhones).
    var onUpdate: ((LiveUpdate) -> Void)?
    var onLog: ((String) -> Void)?
    private var pending: [Int: (Bool, String?) -> Void] = [:]

    /// Live answered within the last 6 s.
    var isConnected: Bool { queue.sync { Date().timeIntervalSince(lastHeard) < 6 } }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startListener()
            self.startSender()
            // Say hello every 2 s until Live answers (Live may start after TwinKeys), then every 5 s.
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.2, repeating: 2)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastHeard) > 5 { self.send(["cmd": "hello", "id": self.newID()]) }
            }
            t.resume()
            self.timer = t
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            timer?.cancel(); listener?.cancel(); sender?.cancel(); receiver?.cancel()
        }
    }

    /// Runs a command on this Mac's Live. `done` is called on `queue` with the script's answer
    /// (or ok: false after 1 s without one).
    /// `checkStructure`: send the track/scene layout this Mac knows, so the script refuses the
    /// command ("structure_changed") if Live's layout changed since (commands from an iPhone).
    func run(_ cmd: LiveCommand, checkStructure: Bool = false, done: ((Bool, String?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            guard cmd.isValid else { done?(false, "invalid"); return }
            let id = self.newID()
            if let done {
                self.pending[id] = done
                self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    if let d = self?.pending.removeValue(forKey: id) { d(false, "no_answer") }
                }
            }
            self.send(cmd.bridgeJSON(id: id, structure: checkStructure ? self.state.song.structure : nil))
        }
    }

    /// Everything, for an iPhone that just connected. Call on any thread.
    func snapshot() -> LiveState { queue.sync { state } }

    // MARK: Internals (on queue)

    private func newID() -> Int { nextID += 1; return nextID }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sender?.send(content: data, completion: .idempotent)
    }

    /// The command socket. UDP to a port nobody listens on yet (Live not started) can fail; then
    /// it is built again, so commands work as soon as Live is there.
    private func startSender() {
        guard !stopped else { return }
        let c = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: Self.commandPort)!, using: .udp)
        c.stateUpdateHandler = { [weak self, weak c] s in
            guard let self, let c, self.sender === c else { return }
            switch s {
            case .failed, .waiting:
                c.cancel()
            case .cancelled:
                self.sender = nil
                self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.sender == nil else { return }
                    self.startSender()
                }
            default: break
            }
        }
        c.start(queue: queue)
        sender = c
    }

    private func startListener() {
        guard !stopped else { return }
        let p = NWParameters.udp
        // Only this Mac: never reachable from the network.
        p.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.statePort)!)
        p.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: p) else {
            onLog?("Live Bridge: cannot listen on 127.0.0.1:\(Self.statePort); retrying")
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startListener() }
            return
        }
        l.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            // The script sends from one socket; a new one (Live restarted) replaces the old.
            if let old = self.receiver, old !== c { old.cancel() }
            self.receiver = c
            c.start(queue: self.queue)
            self.receive(on: c)
        }
        l.stateUpdateHandler = { [weak self, weak l] s in
            if case .failed = s {
                l?.cancel()
                self?.queue.asyncAfter(deadline: .now() + 5) { self?.startListener() }
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, _, _, error in
            guard let self else { return }
            if let data, data.count < 1_000_000,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.handle(obj)
            }
            guard let c else { return }
            if error == nil { self.receive(on: c) } else {
                c.cancel()
                if self.receiver === c { self.receiver = nil }
            }
        }
    }

    private func handle(_ m: [String: Any]) {
        let wasConnected = Date().timeIntervalSince(lastHeard) < 6
        lastHeard = Date()
        if !wasConnected { onLog?("Live Bridge connected") }
        if m["type"] as? String == "ack" {
            if let id = (m["id"] as? NSNumber)?.intValue, let done = pending.removeValue(forKey: id) {
                done((m["ok"] as? NSNumber)?.boolValue ?? false, m["error"] as? String)
            }
            return
        }
        if m["type"] as? String == "error" { onLog?("Live Bridge: \(m["message"] as? String ?? "?")"); return }
        if let u = state.apply(bridge: m) { onUpdate?(u) }
    }
}

/// Copies the Bridge script from the app into Live's User Library (Remote Scripts).
enum LiveBridgeInstaller {
    static let folderName = "TwinKeysBridge"
    /// ~/Music/Ableton/User Library/Remote Scripts (the default User Library location).
    static var remoteScripts: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Ableton/User Library/Remote Scripts", isDirectory: true)
    }
    static var installed: URL { remoteScripts.appendingPathComponent(folderName, isDirectory: true) }
    static var bundled: URL? { Bundle.main.url(forResource: folderName, withExtension: nil) }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installed.appendingPathComponent("__init__.py").path) }

    /// Installs or updates the script. Returns an error message, or nil on success.
    static func install() -> String? {
        guard let src = bundled else { return "The Bridge is not included in this build." }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: remoteScripts, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installed.path) { try fm.removeItem(at: installed) }
            try fm.copyItem(at: src, to: installed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
#endif
