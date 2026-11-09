#if os(macOS)
import Foundation
import Network
import TwinKeysCore

/// Bonjour advertising and browsing plus UDP send/receive, using Network.framework.
final class NetworkService: PacketSink {
    static let serviceType = "_twinkeys._udp"

    let queue = DispatchQueue(label: "TwinKeys.network", qos: .userInteractive)
    private let ownID: String
    private var serviceName: String

    private var listener: NWListener?
    private var browser: NWBrowser?

    // Accessed only on `queue`.
    private var routes: [String: NWConnection] = [:]          // peer ID -> connection
    private var routePeer: [ObjectIdentifier: String] = [:]   // connection -> peer ID
    private var endpoints: [String: NWEndpoint] = [:]         // peer ID -> Bonjour endpoint

    /// Called on `queue`. Return the peer ID the datagram belongs to (or nil).
    var onDatagram: (([UInt8], String?) -> String?)?
    /// Called on the main queue.
    var onPeersChanged: (([PeerInfo]) -> Void)?
    var onLocalNetworkState: ((LocalNetworkState) -> Void)?
    var onProblem: ((String) -> Void)?

    init(ownID: String, serviceName: String) {
        self.ownID = ownID
        self.serviceName = serviceName
    }

    private static func parameters() -> NWParameters {
        let p = NWParameters.udp
        p.serviceClass = .interactiveVoice   // low-latency queueing
        p.includePeerToPeer = false
        return p
    }

    func start(sends: Bool, receives: Bool) {
        do {
            let l = try NWListener(using: Self.parameters())
            l.service = service(sends: sends, receives: receives)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    self?.report("Could not start listening for other Macs: \(error)")
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            report("Could not start listening for other Macs: \(error)")
        }

        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in self?.update(results) }
        b.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .waiting(error), let .failed(error):
                if Self.isPolicyDenied(error) {
                    DispatchQueue.main.async { self?.onLocalNetworkState?(.denied) }
                }
            default: break
            }
        }
        b.start(queue: queue)
        browser = b
    }

    func updateModes(sends: Bool, receives: Bool) {
        queue.async { [weak self] in
            guard let self, let listener = self.listener else { return }
            listener.service = self.service(sends: sends, receives: receives)
        }
    }

    func stop() {
        listener?.cancel(); browser?.cancel()
        queue.sync {
            routes.values.forEach { $0.cancel() }
            routes.removeAll(); routePeer.removeAll()
        }
    }

    /// Gives the last packets (All Notes Off, Bye) time to leave before quitting.
    func flush(timeout: TimeInterval) {
        queue.sync {}
        Thread.sleep(forTimeInterval: timeout)
    }

    // MARK: PacketSink (called from any thread)

    func send(_ bytes: [UInt8], to peer: String) {
        let data = Data(bytes)
        queue.async { [weak self] in
            guard let self, let conn = self.route(to: peer) else { return }
            conn.send(content: data, completion: .idempotent)
        }
    }

    func resetRoute(to peer: String) {
        queue.async { [weak self] in
            guard let self, let old = self.routes.removeValue(forKey: peer) else { return }
            // Only drop routes we opened; an incoming route is the peer's choice.
            if self.endpoints[peer] != nil {
                self.routePeer.removeValue(forKey: ObjectIdentifier(old))
                old.cancel()
            } else {
                self.routes[peer] = old
            }
        }
    }

    // MARK: Internals (on queue)

    private func service(sends: Bool, receives: Bool) -> NWListener.Service {
        var txt = NWTXTRecord()
        txt[TXTKeys.id] = ownID
        txt[TXTKeys.version] = String(WireProtocol.version)
        txt[TXTKeys.modes] = TXTKeys.modes(sends: sends, receives: receives)
        return NWListener.Service(name: serviceName, type: Self.serviceType, domain: nil, txtRecord: txt)
    }

    private func route(to peer: String) -> NWConnection? {
        if let c = routes[peer] { return c }
        guard let ep = endpoints[peer] else { return nil }
        let c = NWConnection(to: ep, using: Self.parameters())
        bind(c, to: peer)
        c.stateUpdateHandler = { [weak self, weak c] state in
            if case .failed = state, let c { self?.drop(c) }
        }
        c.start(queue: queue)
        receive(on: c)
        return c
    }

    private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { [weak self, weak c] state in
            switch state {
            case .failed, .cancelled: if let c { self?.drop(c) }
            default: break
            }
        }
        c.start(queue: queue)
        receive(on: c)
    }

    private func bind(_ c: NWConnection, to peer: String) {
        if let old = routes[peer], old !== c {
            routePeer.removeValue(forKey: ObjectIdentifier(old))
            old.cancel()
        }
        routes[peer] = c
        routePeer[ObjectIdentifier(c)] = peer
    }

    private func drop(_ c: NWConnection) {
        if let p = routePeer.removeValue(forKey: ObjectIdentifier(c)), routes[p] === c {
            routes.removeValue(forKey: p)
        }
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, _, _, error in
            guard let self, let c else { return }
            if let data, !data.isEmpty {
                let known = self.routePeer[ObjectIdentifier(c)]
                if let peer = self.onDatagram?([UInt8](data), known), peer != known {
                    // A hello told us who is on the other end of this route.
                    self.bind(c, to: peer)
                }
            }
            if error == nil { self.receive(on: c) }
        }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: PeerInfo] = [:]
        var eps: [String: NWEndpoint] = [:]
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint,
                  case let .bonjour(txt) = r.metadata,
                  let peer = TXTKeys.peer(from: txt.dictionary, serviceName: name, ownID: ownID) else { continue }
            if found[peer.id] == nil {
                found[peer.id] = peer
                eps[peer.id] = r.endpoint
            }
        }
        endpoints = eps
        let list = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(list)
            if !list.isEmpty { self?.onLocalNetworkState?(.peersVisible) }
        }
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
