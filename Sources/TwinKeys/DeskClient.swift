#if os(macOS)
import Foundation
import Network
import TwinKeysCore

/// The console (Yamaha) link (2.4, experimental; docs/design-v2.4-ql.md): RCP over TCP 49280 to
/// read and write fader levels, and Yamaha's OSC over UDP 49900 for a DM console whose levels
/// cannot be read. Only sockets live here; every decision is DeskLink's (TwinKeysCore), on `queue`.
///
/// AppModel runs it only while the feature is on, an address is set, and this Mac is the
/// receiving (backup) Mac or still has a takeover to undo.
final class DeskClient {
    let queue = DispatchQueue(label: "TwinKeys.desk", qos: .userInitiated)
    /// Accessed on `queue`.
    private var link: DeskLink?
    private var tcp: NWConnection?
    private var udp: NWConnection?
    private var buffer: [UInt8] = []
    private var timer: DispatchSourceTimer?
    /// Called on `queue`.
    var onLog: ((String) -> Void)?

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
    /// A line that never ends (not a console): dropped.
    private static let maxLine = 4096

    /// Starts with, changes to, or stops (nil) these settings. Any thread.
    func configure(_ settings: DeskSettings?) {
        queue.async { [weak self] in self?.apply(settings) }
    }

    /// "Check connection": connect again now.
    func checkNow() {
        queue.async { [weak self] in self?.update { $0.restart(now: DeskClient.now()) } }
    }

    /// Switches the console now if it can be; returns whether it started (and why not).
    func takeover(automatic: Bool) -> DeskReadiness {
        queue.sync { () -> DeskReadiness in
            guard link != nil else { return .notReady(.notConnected) }
            var result = DeskReadiness.notReady(.notConnected)
            update { l in
                let (r, a) = l.startTakeover(now: DeskClient.now(), automatic: automatic)
                result = r
                return a
            }
            return result
        }
    }

    func restore() -> DeskReadiness {
        queue.sync { () -> DeskReadiness in
            guard link != nil else { return .notReady(.notConnected) }
            var result = DeskReadiness.notReady(.notConnected)
            update { l in
                let (r, a) = l.startRestore(now: DeskClient.now())
                result = r
                return a
            }
            return result
        }
    }

    func dismiss() {
        queue.async { [weak self] in self?.update { l in l.dismiss(); return [] } }
    }

    /// nil while not running. Any thread except `queue`.
    func snapshot() -> DeskSnapshot? {
        queue.sync { () -> DeskSnapshot? in link?.snapshot(now: DeskClient.now()) }
    }

    func stop() {
        queue.sync { apply(nil) }
    }

    // MARK: On queue

    private func apply(_ settings: DeskSettings?) {
        guard let s = settings, s.enabled, s.hasValidHost else {
            if link != nil { onLog?("Console: link stopped") }
            update { $0.stop() }
            link = nil
            timer?.cancel(); timer = nil
            closeUDP()
            return
        }
        if link == nil {
            var l = DeskLink(settings: s)
            let a = l.start(now: DeskClient.now())
            link = l
            perform(a)
            startTimer()
        } else {
            let old = link?.settings
            update { $0.configure(s, now: DeskClient.now()) }
            if old?.host != s.host || old?.model != s.model { closeUDP() }
        }
        // DM: the OSC socket is ready before it is needed (UDP: nothing is sent until then).
        if s.model.supportsOSC, udp == nil { openUDP(host: s.host) }
    }

    /// Runs `body` on the link and performs what it returns.
    private func update(_ body: (inout DeskLink) -> [DeskLink.Action]) {
        guard var l = link else { return }
        let actions = body(&l)
        link = l
        perform(actions)
    }

    private func perform(_ actions: [DeskLink.Action]) {
        for a in actions {
            switch a {
            case .open: openTCP()
            case .close: closeTCP()
            case let .send(line): tcp?.send(content: Data(line.utf8), completion: .contentProcessed { _ in })
            case let .sendOSC(bytes): sendOSC(bytes)
            case let .log(m): onLog?("Console: \(m)")
            }
        }
    }

    private func startTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(25), repeating: .milliseconds(25), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.update { $0.tick(now: DeskClient.now()) } }
        t.resume()
        timer = t
    }

    private func openTCP() {
        closeTCP()
        guard let host = link?.settings.host, let port = NWEndpoint.Port(rawValue: DeskRCP.port) else { return }
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        options.connectionTimeout = Int(DeskLink.connectTimeout)
        let c = NWConnection(host: NWEndpoint.Host(host), port: port, using: NWParameters(tls: nil, tcp: options))
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.tcp === c else { return }
            switch state {
            case .ready:
                self.update { $0.connected(now: DeskClient.now()) }
            case let .waiting(error), let .failed(error):
                // Waiting: the system would retry by itself; DeskLink decides when instead.
                self.update { $0.connectionFailed(now: DeskClient.now(), refused: DeskClient.isRefused(error)) }
            default:
                break
            }
        }
        tcp = c
        buffer.removeAll()
        c.start(queue: queue)
        receive(on: c)
    }

    private func closeTCP() {
        guard let c = tcp else { return }
        tcp = nil
        c.stateUpdateHandler = nil
        c.cancel()
        buffer.removeAll()
    }

    private static func isRefused(_ error: NWError) -> Bool {
        if case .posix(.ECONNREFUSED) = error { return true }
        return false
    }

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak c] data, _, isComplete, error in
            guard let self, let c, self.tcp === c else { return }
            if let data, !data.isEmpty { self.consume(data) }
            if isComplete || error != nil {
                self.update { $0.connectionFailed(now: DeskClient.now(), refused: false) }
                return
            }
            self.receive(on: c)
        }
    }

    /// Splits the stream into lines (LF; a CR before it is ignored by the parser).
    private func consume(_ data: Data) {
        buffer.append(contentsOf: data)
        while let i = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<i], as: UTF8.self)
            buffer.removeSubrange(...i)
            update { $0.received(line: line, now: DeskClient.now()) }
            if tcp == nil { return }            // the link closed the connection meanwhile
        }
        if buffer.count > DeskClient.maxLine { buffer.removeAll() }
    }

    private func openUDP(host: String) {
        closeUDP()
        guard let port = NWEndpoint.Port(rawValue: DeskYamahaOSC.port) else { return }
        let c = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.udp === c else { return }
            switch state {
            case .failed, .waiting:
                // Built again for the next datagram.
                self.udp = nil
                c.cancel()
            default:
                break
            }
        }
        udp = c
        c.start(queue: queue)
    }

    private func closeUDP() {
        udp?.stateUpdateHandler = nil
        udp?.cancel()
        udp = nil
    }

    private func sendOSC(_ bytes: [UInt8]) {
        if udp == nil, let host = link?.settings.host { openUDP(host: host) }
        udp?.send(content: Data(bytes), completion: .idempotent)
    }
}
#endif
