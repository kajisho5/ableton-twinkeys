import Foundation

/// Where MIDI goes on this Mac (the virtual "TwinKeys" port).
public protocol MIDIOutput: AnyObject {
    /// One complete MIDI 1.0 channel message (3 bytes).
    func send(_ bytes: [UInt8])
}

/// Sends datagrams to a peer by instance ID.
public protocol PacketSink: AnyObject {
    func send(_ bytes: [UInt8], to peer: String)
    /// Forget any cached route to the peer so the next send looks it up again
    /// (the peer may have restarted on a new port).
    func resetRoute(to peer: String)
}

public struct ConductorSnapshot: Equatable, Sendable {
    public var link: LinkStateMachine.State = .idle
    public var latencyMs: Double?
    public var peerNames: [String: String] = [:]
    public var octave = 3
    public var velocity = 100
    public var heldNotes: [UInt8] = []
    public var sendKeys = true
    public var receiveNotes = true
    public var keyCapture = true
}

/// Connects key input, the local MIDI port and the network link.
/// Thread-safe: key events, network packets and timer ticks may arrive on
/// different threads. Work is done immediately on the calling thread (no hops)
/// to keep added latency low.
public final class Conductor: @unchecked Sendable {
    private let lock = NSLock()
    public let instanceID: UUID
    public let displayName: String
    private let session: UInt32
    private var seq: UInt32 = 0

    private var engine: PerformanceEngine
    private var link = LinkStateMachine()
    private var keysGuard: NoteGuard
    private var peerGuard: NoteGuard
    private var filters: [String: SequenceFilter] = [:]
    private var peerNames: [String: String] = [:]
    private var sendKeys: Bool
    private var receiveNotes: Bool
    private var keyCapture: Bool

    /// Each note, All Notes Off and Bye is sent this many times with the same
    /// sequence number; the receiver drops the copies.
    public let redundancy: Int

    private let midi: MIDIOutput?
    private let net: PacketSink
    private let clock: () -> Double
    private let nanos: () -> UInt64
    public var log: (String) -> Void = { _ in }
    /// True if the peer is currently advertised on the network (Bonjour). Hellos from
    /// anything else are ignored, so a device cannot link up without being visible.
    public var isKnownPeer: (String) -> Bool = { _ in true }
    /// Set when the app is quitting: key input is ignored from then on.
    private var quitting = false
    /// Last time an "ignored hello" was logged per peer (to keep floods out of the log).
    private var ignoredLogAt: [String: Double] = [:]
    /// Keys held longer than this are no longer protected from auto note-off.
    public static let maxProtectedHold = 600.0

    public init(instanceID: UUID, displayName: String, mapping: KeyMapping, settings: AppSettings,
                midi: MIDIOutput?, net: PacketSink, redundancy: Int = 2,
                session: UInt32 = UInt32.random(in: 1...UInt32.max),
                clock: @escaping () -> Double, nanos: @escaping () -> UInt64) {
        self.instanceID = instanceID
        self.displayName = displayName
        self.engine = PerformanceEngine(mapping: mapping)
        self.engine.channel = UInt8(min(16, max(1, settings.midiChannel)) - 1)
        self.keysGuard = NoteGuard(timeout: settings.autoNoteOffSeconds)
        self.peerGuard = NoteGuard(timeout: settings.autoNoteOffSeconds, minimumTimeout: 3)
        self.sendKeys = settings.sendKeys
        self.receiveNotes = settings.receiveNotes
        self.keyCapture = settings.keyCapture
        self.midi = midi
        self.net = net
        self.redundancy = max(1, redundancy)
        self.session = session
        self.clock = clock
        self.nanos = nanos
    }

    private var myID: String { instanceID.uuidString }

    // MARK: - Public inputs

    public func handleKey(_ input: KeyInput) {
        lock.lock(); defer { lock.unlock() }
        guard keyCapture, sendKeys, !quitting else { return }
        for m in engine.handle(input) {
            emitLocal(m, fromKeys: true)
            sendRemote(m)
        }
    }

    /// A datagram arrived. `knownPeer` is the peer already bound to the route it
    /// came on, if any. Returns the peer ID the packet belongs to (so the transport
    /// can bind a new route after a hello), or nil if it was not usable.
    @discardableResult
    public func receive(_ bytes: [UInt8], knownPeer: String?) -> String? {
        guard let packet = try? Packet.decode(bytes) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        let peer: String
        switch packet.body {
        case let .hello(id, _), let .helloAck(id, _): peer = id.uuidString
        default:
            guard let k = knownPeer else { return nil }
            peer = k
        }
        guard peer != myID else { return nil }
        if case .hello = packet.body {
            // Only Macs that are visible on the network may link up.
            // A route already bound to this peer is fine too (the Bonjour entry may have expired).
            guard isKnownPeer(peer) || knownPeer == peer else {
                logIgnored(peer, now, "not advertised on the network"); return nil
            }
        }
        switch packet.body {
        case .hello, .helloAck:
            // A hello on a new route must not take over a link that is alive on its own route
            // (the instance ID is public, so it could be someone else).
            if knownPeer != peer, link.isConnected, link.peer == peer, now - link.lastHeard < 2 {
                logIgnored(peer, now, "on a second route while the link is alive")
                return nil
            }
        default: break
        }
        var f = filters[peer] ?? SequenceFilter()
        let fresh = f.accept(session: packet.session, seq: packet.seq)
        filters[peer] = f
        guard fresh else { return peer }

        switch packet.body {
        case let .hello(_, name):
            setName(name, for: peer)
            perform(link.receivedHello(from: peer, now: now))
        case let .helloAck(_, name):
            setName(name, for: peer)
            perform(link.receivedHelloAck(from: peer, now: now))
        case .bye:
            perform(link.receivedBye(from: peer))
        case let .heartbeat(t):
            perform(link.receivedHeartbeat(from: peer, timestampNanos: t, now: now))
        case let .heartbeatAck(t):
            let n = nanos()
            let rtt = n >= t ? Double(n - t) / 1e9 : 0
            link.receivedHeartbeatAck(from: peer, rtt: rtt, now: now)
        case let .noteOn(ch, note, vel):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            if receiveNotes { emitLocal(.noteOn(channel: ch, note: note, velocity: vel), fromKeys: false) }
        case let .noteOff(ch, note):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            if receiveNotes { emitLocal(.noteOff(channel: ch, note: note), fromKeys: false) }
        case let .held(ch, notes):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            // The full list of keys the peer holds. Listed notes keep sounding; any other note
            // from the peer lost its note-off (for example while the link was down) and ends now.
            let listed = Set(notes.map { NoteGuard.Key(channel: ch, note: $0) })
            for k in listed { peerGuard.touch(channel: k.channel, note: k.note, now: now) }
            for k in peerGuard.active.keys where !listed.contains(k) {
                emitLocal(.noteOff(channel: k.channel, note: k.note), fromKeys: false)
            }
        case .allNotesOff:
            guard link.peer == peer else { return peer }
            link.receivedOther(from: peer, now: now)
            localAllNotesOff()
            log("All Notes Off received from \(name(of: peer))")
        }
        return peer
    }

    /// Call every ~100 ms.
    public func tick() {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        perform(link.tick(now: now))
        // Notes whose keys are still down are not stuck: only the key-up ends them
        // (up to maxProtectedHold, in case a key-up was never seen).
        let down = Set(engine.heldNotes.map { NoteGuard.Key(channel: engine.channel, note: $0) }
            .filter { k in keysGuard.active[k].map { now - $0 < Self.maxProtectedHold } ?? false })
        for m in keysGuard.expire(now: now, keep: down) { midi?.send(m.bytes); log("Auto note-off \(noteNameFor(m))") }
        for m in peerGuard.expire(now: now) { midi?.send(m.bytes); log("Auto note-off \(noteNameFor(m)) (from peer)") }
    }

    public func connect(to peer: String) {
        lock.lock(); defer { lock.unlock() }
        perform(link.connect(to: peer, now: clock()))
    }

    public func disconnect() {
        lock.lock(); defer { lock.unlock() }
        perform(link.disconnect())
    }

    public func panic() {
        lock.lock(); defer { lock.unlock() }
        apply(.panicButton, peer: link.isConnected ? link.peer : nil)
        log("Panic: All Notes Off")
    }

    /// Clean shutdown: notes off everywhere and tell the peer we are leaving.
    /// The key monitor may have missed key-ups (event tap disabled, Secure Input):
    /// end notes of keys we think are down, here and on the peer.
    public func releaseHeldKeys() {
        lock.lock(); defer { lock.unlock() }
        guard !engine.heldNotes.isEmpty else { return }
        apply(.keyCaptureTurnedOff, peer: link.isConnected ? link.peer : nil)
        log("Released held keys (key events may have been missed)")
    }

    public func prepareForQuit() {
        lock.lock(); defer { lock.unlock() }
        quitting = true
        if link.peer != nil {
            // Disconnect turns notes off here and on the peer, then says goodbye.
            perform(link.disconnect())
        } else {
            apply(.appWillQuit, peer: nil)
        }
    }

    public func setSendKeys(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard on != sendKeys else { return }
        if !on { apply(.sendingTurnedOff, peer: link.isConnected ? link.peer : nil) }
        sendKeys = on
    }

    public func setKeyCapture(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard on != keyCapture else { return }
        if !on { apply(.keyCaptureTurnedOff, peer: link.isConnected ? link.peer : nil) }
        keyCapture = on
    }

    public func setReceiveNotes(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        receiveNotes = on
        if !on { for m in peerGuard.releaseAll() { midi?.send(m.bytes) } }
    }

    public func setAutoNoteOff(seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        keysGuard.timeout = seconds; peerGuard.timeout = seconds
    }

    public func setMapping(_ m: KeyMapping) {
        lock.lock(); defer { lock.unlock() }
        for off in engine.setMapping(m) { emitLocal(off, fromKeys: true); sendRemote(off) }
    }

    /// The transport opened a fresh route to the peer (the old one failed). The other side
    /// can only attribute packets on it after a hello, so send one right away.
    public func newRoute(to peer: String) {
        lock.lock(); defer { lock.unlock() }
        guard link.peer == peer else { return }
        sendBody(.hello(instanceID: instanceID, name: displayName), to: peer)
    }

    /// Forget sequence state and names of peers that are neither linked nor listed.
    public func prune(keeping visible: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        let keep = visible.union(link.peer.map { [$0] } ?? [])
        filters = filters.filter { keep.contains($0.key) }
        peerNames = peerNames.filter { keep.contains($0.key) }
    }

    public func setPeerName(_ name: String, for peer: String) {
        lock.lock(); defer { lock.unlock() }
        setName(name, for: peer)
    }

    public func snapshot() -> ConductorSnapshot {
        lock.lock(); defer { lock.unlock() }
        return ConductorSnapshot(link: link.state, latencyMs: link.latencyMs, peerNames: peerNames,
                                 octave: engine.octave, velocity: engine.velocity, heldNotes: engine.heldNotes,
                                 sendKeys: sendKeys, receiveNotes: receiveNotes, keyCapture: keyCapture)
    }

    // MARK: - Internals (call with lock held)

    /// `peer`: the peer to notify (nil when there is no link).
    private func apply(_ trigger: SafetyTrigger, peer: String?) {
        let plan = Safety.plan(for: trigger, connected: peer != nil)
        switch plan.local {
        case .none: break
        case .all:
            localAllNotesOff()
            if plan.remote, let p = peer { sendBody(.allNotesOff, to: p, copies: redundancy) }
        case .notesFromKeys:
            for m in engine.releaseAll() {
                emitLocal(m, fromKeys: true)
                if plan.remote, let p = peer { send(m, to: p) }
            }
        case .notesFromPeer:
            for m in peerGuard.releaseAll() { midi?.send(m.bytes) }
        }
    }

    private func localAllNotesOff() {
        _ = engine.releaseAll()
        for b in MIDIMessage.allNotesOffBytes { midi?.send(b) }
        // Some instruments ignore CC 123, so also end every note we know is on.
        for m in keysGuard.releaseAll() + peerGuard.releaseAll() { midi?.send(m.bytes) }
    }

    private func emitLocal(_ m: MIDIMessage, fromKeys: Bool) {
        midi?.send(m.bytes)
        if fromKeys { keysGuard.record(m, now: clock()) } else { peerGuard.record(m, now: clock()) }
    }

    private func sendRemote(_ m: MIDIMessage) {
        guard link.isConnected, let p = link.peer else { return }
        send(m, to: p)
    }

    private func send(_ m: MIDIMessage, to p: String) {
        switch m {
        case let .noteOn(ch, n, v): sendBody(.noteOn(channel: ch, note: n, velocity: v), to: p, copies: redundancy)
        case let .noteOff(ch, n): sendBody(.noteOff(channel: ch, note: n), to: p, copies: redundancy)
        }
    }

    private func sendBody(_ body: PacketBody, to peer: String, copies: Int = 1) {
        seq &+= 1
        let bytes = Packet(session: session, seq: seq, body: body).encode()
        for _ in 0..<copies { net.send(bytes, to: peer) }
    }

    private func perform(_ actions: [LinkStateMachine.Action]) {
        for a in actions {
            switch a {
            case let .sendHello(p):
                net.resetRoute(to: p)
                sendBody(.hello(instanceID: instanceID, name: displayName), to: p)
            case let .sendHelloAck(p):
                sendBody(.helloAck(instanceID: instanceID, name: displayName), to: p)
            case let .sendHeartbeat(p):
                sendBody(.heartbeat(timestampNanos: nanos()), to: p)
                // Always send the full list (also when empty): the peer ends any of our notes
                // that are not in it, which repairs note-offs lost while the link was down.
                let holding = (sendKeys && keyCapture) ? engine.heldNotes : []
                sendBody(.held(channel: engine.channel, notes: holding), to: p)
            case let .sendHeartbeatAck(p, t):
                sendBody(.heartbeatAck(timestampNanos: t), to: p)
            case let .sendBye(p):
                sendBody(.bye, to: p, copies: redundancy)
            case let .safety(trigger, p):
                apply(trigger, peer: p)
            case let .log(s) where s.hasPrefix("Ignored hello"):
                // Repeated hellos can be a flood: log each kind at most once a minute.
                let now = clock()
                if let t = ignoredLogAt[s], now - t < 60 { continue }
                ignoredLogAt[s] = now
                if ignoredLogAt.count > 64 { ignoredLogAt.removeAll() }
                log(peerNames.reduce(s) { $0.replacingOccurrences(of: $1.key, with: $1.value) })
            case let .log(s):
                // Show peer names instead of instance IDs.
                log(peerNames.reduce(s) { $0.replacingOccurrences(of: $1.key, with: $1.value) })
            }
        }
    }

    private func name(of peer: String) -> String { peerNames[peer] ?? peer }

    /// Peer names come from the network: keep printable characters only.
    private func setName(_ raw: String, for peer: String) {
        let clean = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { peerNames[peer] = clean }
    }

    private func logIgnored(_ peer: String, _ now: Double, _ why: String) {
        if let t = ignoredLogAt[peer], now - t < 60 { return }
        ignoredLogAt[peer] = now
        if ignoredLogAt.count > 64 { ignoredLogAt.removeAll() }
        log("Ignored hello from \(peer): \(why)")
    }

    private func noteNameFor(_ m: MIDIMessage) -> String {
        switch m { case let .noteOn(_, n, _), let .noteOff(_, n): return noteName(n) }
    }
}
