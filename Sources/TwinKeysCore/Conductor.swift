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

    public init(instanceID: UUID, displayName: String, mapping: KeyMapping, settings: AppSettings,
                midi: MIDIOutput?, net: PacketSink, redundancy: Int = 2,
                session: UInt32 = UInt32.random(in: 1...UInt32.max),
                clock: @escaping () -> Double, nanos: @escaping () -> UInt64) {
        self.instanceID = instanceID
        self.displayName = displayName
        self.engine = PerformanceEngine(mapping: mapping)
        self.engine.channel = UInt8(min(16, max(1, settings.midiChannel)) - 1)
        self.keysGuard = NoteGuard(timeout: settings.autoNoteOffSeconds)
        self.peerGuard = NoteGuard(timeout: settings.autoNoteOffSeconds)
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
        guard keyCapture, sendKeys else { return }
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
        var f = filters[peer] ?? SequenceFilter()
        let fresh = f.accept(session: packet.session, seq: packet.seq)
        filters[peer] = f
        guard fresh else { return peer }

        switch packet.body {
        case let .hello(_, name):
            if !name.isEmpty { peerNames[peer] = name }
            perform(link.receivedHello(from: peer, now: now))
        case let .helloAck(_, name):
            if !name.isEmpty { peerNames[peer] = name }
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
            // Always deliver note-offs for notes we played, even if receiving was just turned off.
            if receiveNotes || peerGuard.active[NoteGuard.Key(channel: ch, note: note)] != nil {
                emitLocal(.noteOff(channel: ch, note: note), fromKeys: false)
            }
        case .allNotesOff:
            guard link.peer == peer else { return peer }
            link.receivedOther(from: peer, now: now)
            localAllNotesOff()
            log("All Notes Off received from \(peerNames[peer] ?? peer)")
        }
        return peer
    }

    /// Call every ~100 ms.
    public func tick() {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        perform(link.tick(now: now))
        for m in keysGuard.expire(now: now) { midi?.send(m.bytes); log("Auto note-off \(noteNameFor(m))") }
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
        apply(.panicButton)
        log("Panic: All Notes Off")
    }

    /// Clean shutdown: notes off everywhere and tell the peer we are leaving.
    public func prepareForQuit() {
        lock.lock(); defer { lock.unlock() }
        apply(.appWillQuit)
        perform(link.disconnect())
    }

    public func setSendKeys(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard on != sendKeys else { return }
        if !on { apply(.sendingTurnedOff) }
        sendKeys = on
    }

    public func setKeyCapture(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard on != keyCapture else { return }
        if !on { apply(.keyCaptureTurnedOff) }
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

    public func setPeerName(_ name: String, for peer: String) {
        lock.lock(); defer { lock.unlock() }
        peerNames[peer] = name
    }

    public func snapshot() -> ConductorSnapshot {
        lock.lock(); defer { lock.unlock() }
        return ConductorSnapshot(link: link.state, latencyMs: link.latencyMs, peerNames: peerNames,
                                 octave: engine.octave, velocity: engine.velocity, heldNotes: engine.heldNotes,
                                 sendKeys: sendKeys, receiveNotes: receiveNotes, keyCapture: keyCapture)
    }

    // MARK: - Internals (call with lock held)

    private func apply(_ trigger: SafetyTrigger) {
        let plan = Safety.plan(for: trigger, connected: link.isConnected)
        switch plan.local {
        case .none: break
        case .all:
            localAllNotesOff()
            if plan.remote, let p = link.peer { sendBody(.allNotesOff, to: p, copies: redundancy) }
        case .notesFromKeys:
            for m in engine.releaseAll() {
                emitLocal(m, fromKeys: true)
                if plan.remote { sendRemote(m) }
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
            case let .sendHeartbeatAck(p, t):
                sendBody(.heartbeatAck(timestampNanos: t), to: p)
            case let .sendBye(p):
                sendBody(.bye, to: p, copies: redundancy)
            case let .sendAllNotesOff(p):
                sendBody(.allNotesOff, to: p, copies: redundancy)
            case .allNotesOffLocal:
                localAllNotesOff()
            case .releaseNotesFromPeer:
                for m in peerGuard.releaseAll() { midi?.send(m.bytes) }
            case let .log(s):
                log(s.replacingOccurrences(of: link.peer ?? "\u{0}", with: peerNames[link.peer ?? ""] ?? link.peer ?? ""))
            }
        }
    }

    private func noteNameFor(_ m: MIDIMessage) -> String {
        switch m { case let .noteOn(_, n, _), let .noteOff(_, n): return noteName(n) }
    }
}
