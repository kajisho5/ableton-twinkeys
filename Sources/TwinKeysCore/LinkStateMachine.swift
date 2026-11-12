/// Connection state for one peer, with heartbeat-based loss detection and
/// automatic reconnection. Pure logic: time comes in from the caller, and the
/// caller performs the returned actions. This makes every transition testable.
public struct LinkStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        /// `attempt` starts at 1. `nextRetryAt` is when the next hello is due.
        case connecting(peer: String, attempt: Int, nextRetryAt: Double)
        case connected(peer: String)
    }

    public enum Action: Equatable, Sendable {
        case sendHello(peer: String)
        case sendHelloAck(peer: String)
        case sendHeartbeat(peer: String)
        case sendHeartbeatAck(peer: String, timestampNanos: UInt64)
        case sendBye(peer: String)
        /// Turn notes off as `Safety.plan(for:)` says for this trigger. `peer` is the peer
        /// the link was with (for sending All Notes Off to it).
        case safety(SafetyTrigger, peer: String)
        case log(String)
    }

    public static let heartbeatInterval = 1.0
    public static let timeout = 3.0
    public static let minRetry = 1.0
    public static let maxRetry = 5.0

    public private(set) var state: State = .idle
    public private(set) var lastHeard: Double = 0
    private var lastHeartbeatSent: Double = -.infinity
    private var rtts: [Double] = []
    /// Peers the person disconnected from (or switched away from). Their hellos are answered
    /// with Bye until the person connects to them again, so a lost Bye cannot undo that choice.
    /// Value: when its last hello arrived. An entry expires after `declineMemory` seconds without
    /// hellos (the peer evidently got the Bye), so the person on that Mac can connect again later.
    public private(set) var declined: [String: Double] = [:]
    public static let declineMemory = 30.0

    public init() {}

    public var peer: String? {
        switch state {
        case .idle: return nil
        case let .connecting(p, _, _), let .connected(p): return p
        }
    }

    public var isConnected: Bool { if case .connected = state { return true }; return false }

    /// Median of the last 5 heartbeat round trips, in milliseconds.
    public var latencyMs: Double? {
        guard !rtts.isEmpty else { return nil }
        let s = rtts.sorted()
        return s[s.count / 2] * 1000
    }

    /// Retry delay after `attempt` attempts: 1, 2, 4, 5, 5, ... seconds.
    public static func retryDelay(attempt: Int) -> Double {
        min(maxRetry, minRetry * Double(1 << min(max(attempt - 1, 0), 8)))
    }

    /// A placeholder peer (for example "manual:192.168.1.20") turned out to be `real`.
    public mutating func renamePeer(from old: String, to real: String) {
        switch state {
        case let .connecting(p, a, n) where p == old: state = .connecting(peer: real, attempt: a, nextRetryAt: n)
        case let .connected(p) where p == old: state = .connected(peer: real)
        default: break
        }
    }

    // MARK: - Inputs

    /// User pressed Connect.
    public mutating func connect(to peer: String, now: Double) -> [Action] {
        var actions: [Action] = []
        if let old = self.peer, old != peer {
            actions += leave(old)
            declined[old] = now     // its late hellos must not bring it back
        }
        declined.removeValue(forKey: peer)   // the person chose this peer
        state = .connecting(peer: peer, attempt: 1, nextRetryAt: now + Self.retryDelay(attempt: 1))
        rtts.removeAll()
        actions.append(.sendHello(peer: peer))
        return actions
    }

    /// User pressed Disconnect.
    public mutating func disconnect(now: Double? = nil) -> [Action] {
        guard let p = peer else { return [] }
        state = .idle
        rtts.removeAll()
        declined[p] = now ?? lastHeard
        return leave(p) + [.log("Disconnected from \(p)")]
    }

    /// Notes off on both sides, then say goodbye so the peer does not reconnect.
    private func leave(_ p: String) -> [Action] {
        [.safety(.manualDisconnect, peer: p), .sendBye(peer: p)]
    }

    /// A hello arrived (the peer connects to us, or reconnects after a drop).
    public mutating func receivedHello(from peer: String, now: Double) -> [Action] {
        if let t = declined[peer], now - t >= Self.declineMemory { declined.removeValue(forKey: peer) }
        if declined[peer] != nil, peer != self.peer {
            declined[peer] = now
            // Answer with Bye (also while linked to another Mac) so the old peer stops retrying.
            return [.sendBye(peer: peer), .log("Ignored hello from \(peer) after a manual disconnect")]
        }
        switch state {
        case let .connected(p) where p == peer:
            lastHeard = now
            return [.sendHelloAck(peer: peer)]
        case let .connected(p), let .connecting(p, _, _):
            if p != peer {
                // Already linked with someone else (1:1 in v1). Ignore.
                return [.log("Ignored hello from \(peer) while linked to \(p)")]
            }
        case .idle:
            break
        }
        lastHeard = now
        state = .connected(peer: peer)
        rtts.removeAll()
        return [.sendHelloAck(peer: peer), .log("Connected to \(peer)")]
    }

    public mutating func receivedHelloAck(from peer: String, now: Double) -> [Action] {
        guard case let .connecting(p, _, _) = state, p == peer else {
            if self.peer == peer { lastHeard = now }
            return []
        }
        lastHeard = now
        state = .connected(peer: peer)
        return [.log("Connected to \(peer)")]
    }

    /// The peer said goodbye: stop and do not reconnect.
    public mutating func receivedBye(from peer: String) -> [Action] {
        guard self.peer == peer else { return [] }
        state = .idle
        rtts.removeAll()
        return [.safety(.peerSaidBye, peer: peer), .log("\(peer) disconnected")]
    }

    public mutating func receivedHeartbeat(from peer: String, timestampNanos: UInt64, now: Double) -> [Action] {
        guard self.peer == peer else { return [] }
        if case .connecting = state {
            // The peer still thinks the link is up, but we timed out. Acking would keep it
            // "connected" while we drop its notes; a hello re-establishes the link on both sides.
            return [.sendHello(peer: peer)]
        }
        if isConnected { lastHeard = now }
        return [.sendHeartbeatAck(peer: peer, timestampNanos: timestampNanos)]
    }

    /// `rtt` in seconds, measured by the caller from the echoed timestamp.
    public mutating func receivedHeartbeatAck(from peer: String, rtt: Double, now: Double) {
        guard self.peer == peer, isConnected else { return }
        lastHeard = now
        rtts.append(rtt)
        if rtts.count > 5 { rtts.removeFirst(rtts.count - 5) }
    }

    /// Any other packet from the peer also proves it is alive.
    public mutating func receivedOther(from peer: String, now: Double) {
        if self.peer == peer, isConnected { lastHeard = now }
    }

    /// Call regularly (e.g. every 100-250 ms).
    public mutating func tick(now: Double) -> [Action] {
        switch state {
        case .idle:
            return []
        case let .connected(p):
            if now - lastHeard >= Self.timeout {
                state = .connecting(peer: p, attempt: 1, nextRetryAt: now + Self.retryDelay(attempt: 1))
                rtts.removeAll()
                return [.safety(.connectionLost, peer: p), .log("Lost connection to \(p); reconnecting"), .sendHello(peer: p)]
            }
            if now - lastHeartbeatSent >= Self.heartbeatInterval {
                lastHeartbeatSent = now
                return [.sendHeartbeat(peer: p)]
            }
            return []
        case let .connecting(p, attempt, next):
            guard now >= next else { return [] }
            let a = attempt + 1
            state = .connecting(peer: p, attempt: a, nextRetryAt: now + Self.retryDelay(attempt: a))
            return [.sendHello(peer: p)]
        }
    }
}

/// 2.3: when the main Mac was lost, for the "main Mac stopped" banner on a receiving Mac (and the
/// console's automatic takeover). Only an unexpected loss counts: the link timed out and is being
/// retried. A deliberate end (Disconnect on this Mac, or the other Mac saying goodbye when it quits)
/// leaves the link idle and is not a loss.
public struct MainLossWatch: Sendable {
    public private(set) var lostSince: Double?
    private var wasConnected = false
    public init() {}

    public mutating func update(_ link: LinkStateMachine.State, now: Double) {
        switch link {
        case .connected:
            wasConnected = true
            lostSince = nil
        case .idle:
            wasConnected = false
            lostSince = nil
        case .connecting:
            if wasConnected, lostSince == nil { lostSince = now }
        }
    }

    /// Lost for at least `after` seconds.
    public func isLost(now: Double, after: Double = 3) -> Bool {
        lostSince.map { now - $0 >= after } ?? false
    }
}
