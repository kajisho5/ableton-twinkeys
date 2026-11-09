#if os(macOS)
import Foundation
import Network
import TwinKeysCore

/// Bonjour advertising and browsing plus UDP send/receive, using Network.framework.
final class NetworkService: PacketSink {
    static let serviceType = "_twinkeys._udp"
    /// Inbound routes that do not identify themselves with a hello in this time are closed.
    static let unboundTimeout: TimeInterval = 5
    static let maxUnbound = 16
    /// Fixed UDP port, so another Mac can connect by IP address. Falls back to any free port.
    static let fixedPort: UInt16 = 47801

    let queue = DispatchQueue(label: "TwinKeys.network", qos: .userInteractive)
    private let ownID: String
    private let ownBoot = UUID().uuidString
    private var serviceName: String
    private var sends = true
    private var receives = true

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var stopped = false
    private var useFixedPort = true
    /// The UDP port actually listened on (main queue reads it through `onListenPort`).
    var onListenPort: ((UInt16?) -> Void)?
    private var manualEndpoints: [String: NWEndpoint] = [:]   // placeholder or real peer ID -> typed address
    /// Set once Bonjour confirms our advertisement. macOS Local Network privacy blocks it
    /// silently (no error) when permission is missing, so its absence is the best signal.
    private var advertised = false

    // Accessed only on `queue`.
    private var routes: [String: NWConnection] = [:]          // peer ID -> connection we send on
    private var routePeer: [ObjectIdentifier: String] = [:]   // connection -> peer ID (all bound connections)
    private var unbound: [ObjectIdentifier: (conn: NWConnection, since: Date)] = [:]
    private var retiredAt: [ObjectIdentifier: Date] = [:]     // latest retirement per connection
    private var endpoints: [String: NWEndpoint] = [:]         // peer ID -> Bonjour endpoint
    private var interfaces: [String: NWInterface] = [:]       // peer ID -> best interface it was seen on
    private var unpinned: Set<String> = []                    // pinned route failed: let the system choose
    private var routePin: [String: String] = [:]               // peer ID -> interface name its route was pinned to
    private var lastReset: [String: Date] = [:]               // peer ID -> last resetRoute that opened a new route
    /// A second listener on the fixed port while the main one had to use another port.
    private var fixedPortListener: NWListener?
    /// Peers currently advertised. Read from any thread (also from the network queue itself),
    /// so it has its own lock instead of `queue.sync`.
    private var visible: Set<String> {
        get { visibleLock.lock(); defer { visibleLock.unlock() }; return _visible }
        set { visibleLock.lock(); _visible = newValue; visibleLock.unlock() }
    }
    private var _visible: Set<String> = []
    private let visibleLock = NSLock()
    private let pending = DispatchGroup()

    /// Called on `queue`. Return the peer ID the datagram belongs to (or nil).
    var onDatagram: (([UInt8], String?) -> String?)?
    /// Called on `queue` after a fresh outgoing route to a peer was opened.
    var onNewRoute: ((String) -> Void)?
    /// Called on the main queue.
    var onPeersChanged: (([PeerInfo]) -> Void)?
    var onLocalNetworkState: ((LocalNetworkState) -> Void)?
    var onProblem: ((String) -> Void)?
    /// Another running TwinKeys uses our instance ID (copied settings). Main queue.
    var onDuplicateID: (() -> Void)?
    /// Diagnostic messages for the log file (listener / browser state). Any thread.
    var onLog: ((String) -> Void)?

    init(ownID: String, serviceName: String) {
        self.ownID = ownID
        self.serviceName = serviceName
    }

    private static func parameters(on interface: NWInterface? = nil) -> NWParameters {
        let p = NWParameters.udp
        // Use the interface the peer was found on (wired first). Needed for link-local
        // addresses on a direct cable, and keeps the link off Wi-Fi when a cable is there.
        if let interface { p.requiredInterface = interface }
        p.serviceClass = .interactiveVoice   // low-latency queueing
        p.includePeerToPeer = false
        return p
    }

    /// True if the peer is currently advertised on the network. Thread-safe.
    func isVisible(_ peer: String) -> Bool { visible.contains(peer) }

    func start(sends: Bool, receives: Bool) {
        self.sends = sends; self.receives = receives
        queue.async { [weak self] in
            self?.startListener()
            self?.startBrowser()
        }
    }

    // MARK: Listener and browser (restarted after failures)

    private func startListener() {
        guard !stopped else { return }
        do {
            let l: NWListener
            if useFixedPort, let port = NWEndpoint.Port(rawValue: Self.fixedPort) {
                l = try NWListener(using: Self.parameters(), on: port)
            } else {
                l = try NWListener(using: Self.parameters())
            }
            l.service = service()
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.serviceRegistrationUpdateHandler = { [weak self] change in
                switch change {
                case let .add(endpoint):
                    guard let self else { return }
                    self.advertised = true
                    self.onLog?("Advertising on the network as \(endpoint)")
                    // Access works now: clear a "not allowed" shown by the watchdog.
                    let empty = self.visible.isEmpty
                    DispatchQueue.main.async { self.onLocalNetworkState?(empty ? .searching : .peersVisible) }
                case let .remove(endpoint): self?.onLog?("No longer advertised: \(endpoint)")
                @unknown default: break
                }
            }
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self else { return }
                self.onLog?("Listener state: \(state)\(l?.port.map { " (UDP port \($0))" } ?? "")")
                if case .ready = state {
                    let port = l?.port?.rawValue
                    DispatchQueue.main.async { self.onListenPort?(port) }
                }
                if case let .failed(error) = state {
                    l?.cancel()
                    if self.useFixedPort, case .posix(.EADDRINUSE) = error {
                        // Port 47801 is taken (for example by another copy): use any free port now,
                        // and keep trying to get 47801 back (Connect by IP uses it).
                        self.onLog?("UDP port \(Self.fixedPort) in use; using another port for now")
                        self.useFixedPort = false
                        self.queue.async { self.startListener() }
                        self.queue.asyncAfter(deadline: .now() + 30) { self.retryFixedPort() }
                    } else if self.useFixedPort {
                        // Any other failure (for example after sleep): try the same port again.
                        self.report("Listening for other Macs failed (\(error)); retrying")
                        self.queue.asyncAfter(deadline: .now() + 2) { self.startListener() }
                    } else {
                        self.report("Listening for other Macs failed (\(error)); retrying")
                        self.queue.asyncAfter(deadline: .now() + 2) { self.startListener() }
                    }
                }
            }
            l.start(queue: queue)
            listener = l
            queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, !self.stopped, !self.advertised else { return }
                self.onLog?("Not advertised after 10 s: Local Network access is probably not allowed")
                DispatchQueue.main.async { self.onLocalNetworkState?(.denied) }
            }
        } catch {
            report("Could not start listening for other Macs: \(error)")
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startListener() }
        }
    }

    /// While the main listener is on another port, keep trying to also listen on the fixed port
    /// (no Bonjour advertisement on it: it only serves Connect by IP).
    private func retryFixedPort() {
        guard !stopped, !useFixedPort, fixedPortListener == nil,
              let port = NWEndpoint.Port(rawValue: Self.fixedPort),
              let l = try? NWListener(using: Self.parameters(), on: port) else { return }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self, weak l] state in
            guard let self else { return }
            switch state {
            case .ready: self.onLog?("Now also listening on UDP port \(Self.fixedPort)")
            case .failed:
                l?.cancel()
                self.fixedPortListener = nil
                self.queue.asyncAfter(deadline: .now() + 30) { self.retryFixedPort() }
            default: break
            }
        }
        fixedPortListener = l
        l.start(queue: queue)
    }

    private func startBrowser() {
        guard !stopped else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in self?.update(results) }
        b.stateUpdateHandler = { [weak self, weak b] state in
            guard let self else { return }
            self.onLog?("Browser state: \(state)")
            switch state {
            case .ready:
                // Access works now (it may have been granted after a refusal).
                DispatchQueue.main.async { self.onLocalNetworkState?(self.visible.isEmpty ? .searching : .peersVisible) }
            case let .waiting(error):
                if Self.isPolicyDenied(error) { DispatchQueue.main.async { self.onLocalNetworkState?(.denied) } }
            case let .failed(error):
                if Self.isPolicyDenied(error) { DispatchQueue.main.async { self.onLocalNetworkState?(.denied) } }
                b?.cancel()
                self.queue.asyncAfter(deadline: .now() + 2) { self.startBrowser() }
            default: break
            }
        }
        b.start(queue: queue)
        browser = b
    }

    /// Registers a typed IP address (IPv4 or IPv6) and returns a placeholder peer ID for it.
    /// The real peer ID is learned from its first authenticated answer.
    func addManual(host raw: String) -> String {
        let parsed = ManualAddress.parse(raw) ?? (raw, Self.fixedPort)
        let key = PeerInfo.manualPrefix + raw.trimmingCharacters(in: .whitespaces)
        let port = NWEndpoint.Port(rawValue: parsed.port) ?? NWEndpoint.Port(rawValue: Self.fixedPort)!
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(parsed.host), port: port)
        queue.sync { manualEndpoints[key] = endpoint }
        return key
    }

    /// This Mac's IPv4 addresses on Ethernet / Wi-Fi / bridge interfaces, for display.
    static func localAddresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }

    func updateModes(sends: Bool, receives: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sends = sends; self.receives = receives
            self.listener?.service = self.service()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            listener?.cancel(); browser?.cancel(); fixedPortListener?.cancel()
            for c in Array(routes.values) + unbound.values.map(\.conn) { c.cancel() }
            routes.removeAll(); routePeer.removeAll(); unbound.removeAll()
        }
    }

    /// Waits until the last packets (All Notes Off, Bye) have been handed to the network,
    /// or until the timeout.
    func flush(timeout: TimeInterval) {
        queue.sync {}
        _ = pending.wait(timeout: .now() + timeout)
    }

    // MARK: PacketSink (called from any thread)

    func send(_ bytes: [UInt8], to peer: String) {
        let data = Data(bytes)
        pending.enter()
        queue.async { [weak self] in
            guard let self, let conn = self.route(to: peer) else { self?.pending.leave(); return }
            conn.send(content: data, completion: .contentProcessed { [weak self] _ in self?.pending.leave() })
        }
    }

    func resetRoute(to peer: String) {
        queue.async { [weak self] in
            guard let self, let old = self.routes[peer] else { return }
            // We can only open a new route to a peer we can see on Bonjour; otherwise keep the
            // current route (for example one the peer opened to us).
            guard self.endpoints[peer] != nil || self.manualEndpoints[peer] != nil else { return }
            // At most one new route per second (hellos while connecting would otherwise open many).
            if let t = self.lastReset[peer], Date().timeIntervalSince(t) < 1 { return }
            self.lastReset[peer] = Date()
            self.routes.removeValue(forKey: peer)
            self.retire(old)
        }
    }

    // MARK: Internals (on queue)

    private func service() -> NWListener.Service {
        var txt = NWTXTRecord()
        txt[TXTKeys.id] = ownID
        txt[TXTKeys.version] = String(WireProtocol.version)
        txt[TXTKeys.modes] = TXTKeys.modes(sends: sends, receives: receives)
        txt[TXTKeys.boot] = ownBoot
        return NWListener.Service(name: serviceName, type: Self.serviceType, domain: nil, txtRecord: txt)
    }

    private func route(to peer: String) -> NWConnection? {
        if let c = routes[peer] { return c }
        guard let ep = endpoints[peer] ?? manualEndpoints[peer] else { return nil }
        let pin = unpinned.contains(peer) ? nil : interfaces[peer]
        let c = NWConnection(to: ep, using: Self.parameters(on: pin))
        bind(c, to: peer)
        routePin[peer] = pin?.name
        c.stateUpdateHandler = { [weak self, weak c] state in
            switch state {
            case .failed:
                // The pinned interface did not work: next time let the system choose.
                if pin != nil { self?.unpinned.insert(peer) }
                if let c { self?.drop(c); c.cancel() }
            case .waiting where pin != nil:
                // The pinned interface went away (cable pulled): do not wait for it to come back.
                self?.unpinned.insert(peer)
                if let c { self?.drop(c); c.cancel() }
            case .cancelled: if let c { self?.drop(c) }
            default: break
            }
        }
        c.start(queue: queue)
        receive(on: c)
        // The peer can only tell who we are on this new route after a hello.
        queue.async { [weak self] in self?.onNewRoute?(peer) }
        return c
    }

    private func accept(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        if unbound.count >= Self.maxUnbound, let oldest = unbound.min(by: { $0.value.since < $1.value.since }) {
            unbound.removeValue(forKey: oldest.key); oldest.value.conn.cancel()
        }
        unbound[key] = (c, Date())
        c.stateUpdateHandler = { [weak self, weak c] state in
            switch state {
            case .failed: if let c { self?.drop(c); c.cancel() }
            case .cancelled: if let c { self?.drop(c) }
            default: break
            }
        }
        c.start(queue: queue)
        receive(on: c)
        // Close it if it never says hello (scanners, junk, stale flows).
        queue.asyncAfter(deadline: .now() + Self.unboundTimeout) { [weak self] in
            guard let self, let entry = self.unbound.removeValue(forKey: key) else { return }
            entry.conn.cancel()
        }
    }

    /// Makes `c` the route we send to `peer` on. The previous route is not cancelled at once:
    /// when both Macs say hello at the same moment, the peer may still be answering on it.
    private func bind(_ c: NWConnection, to peer: String) {
        unbound.removeValue(forKey: ObjectIdentifier(c))
        if let old = routes[peer], old !== c { retire(old) }
        routes[peer] = c
        routePeer[ObjectIdentifier(c)] = peer
    }

    /// Keeps receiving on an old route for a while, then closes it.
    private func retire(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        let stamp = Date()
        retiredAt[key] = stamp
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            // Only the latest retirement counts (it may have been re-bound and retired again).
            guard self.retiredAt[key] == stamp else { return }
            self.retiredAt.removeValue(forKey: key)
            if let p = self.routePeer[key], self.routes[p] === c { return }   // in use again
            self.routePeer.removeValue(forKey: key)
            c.cancel()
        }
    }

    private func drop(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        unbound.removeValue(forKey: key)
        if let p = routePeer.removeValue(forKey: key), routes[p] === c {
            routes.removeValue(forKey: p)
        }
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, _, _, error in
            guard let self, let c else { return }
            if let data, !data.isEmpty {
                let known = self.routePeer[ObjectIdentifier(c)]
                if let peer = self.onDatagram?([UInt8](data), known), peer != known || self.routes[peer] !== c {
                    // A hello told us who is on the other end of this route. A route opened to a
                    // typed address keeps that address for reconnecting to the real peer.
                    if let k = known, k.hasPrefix(PeerInfo.manualPrefix), let ep = self.manualEndpoints[k] {
                        self.manualEndpoints[peer] = ep
                        self.manualEndpoints.removeValue(forKey: k)
                        if self.routes[k] === c { self.routes.removeValue(forKey: k) }
                    }
                    self.bind(c, to: peer)
                }
            }
            if error == nil { self.receive(on: c) }
        }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: PeerInfo] = [:]
        var eps: [String: (NWEndpoint, Int, NWInterface?)] = [:]
        var duplicate = false
        // Sort so the choice does not change between updates; prefer wired, then Wi-Fi.
        let sorted = results.sorted { "\($0.endpoint)" < "\($1.endpoint)" }
        for r in sorted {
            guard case let .service(name, _, _, _) = r.endpoint, case let .bonjour(txt) = r.metadata else { continue }
            let dict = txt.dictionary
            if TXTKeys.isDuplicateOfUs(dict, ownID: ownID, ownBoot: ownBoot) { duplicate = true; continue }
            guard let peer = TXTKeys.peer(from: dict, serviceName: name, ownID: ownID) else { continue }
            let (rank, best) = Self.best(r.interfaces)
            if let current = eps[peer.id], current.1 <= rank { continue }
            found[peer.id] = peer
            eps[peer.id] = (r.endpoint, rank, best)
        }
        endpoints = eps.mapValues { $0.0 }
        let newInterfaces = eps.compactMapValues { $0.2 }
        for (id, i) in newInterfaces where interfaces[id]?.name != i.name { unpinned.remove(id) }
        interfaces = newInterfaces
        // The best interface to a peer changed (cable plugged back in, Wi-Fi only now): move a
        // route we opened onto it. Sending on the new route starts with a hello.
        for (peer, name) in routePin where newInterfaces[peer] != nil && newInterfaces[peer]?.name != name {
            if let old = routes[peer] {
                routes.removeValue(forKey: peer)
                retire(old)
                onLog?("Route to \(peer) moves to \(newInterfaces[peer]!.name)")
            }
            routePin.removeValue(forKey: peer)
        }
        visible = Set(found.keys)
        let list = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(list)
            self?.onLocalNetworkState?(list.isEmpty ? .searching : .peersVisible)
            if duplicate { self?.onDuplicateID?() }
        }
    }

    /// The best interface a service was seen on and its rank (lower is better):
    /// wired Ethernet, then Wi-Fi, then anything else (for example Thunderbolt Bridge).
    private static func best(_ interfaces: [NWInterface]) -> (Int, NWInterface?) {
        if let i = interfaces.first(where: { $0.type == .wiredEthernet }) { return (0, i) }
        if let i = interfaces.first(where: { $0.type == .wifi }) { return (1, i) }
        return (2, interfaces.first)
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onProblem?(message) }
    }

    /// kDNSServiceErr_PolicyDenied: local network access was refused by the system.
    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case let .dns(code) = error { return code == -65570 }
        return false
    }
}
#endif
