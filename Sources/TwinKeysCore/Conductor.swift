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
    /// A pairing code is set (without one nothing can link).
    public var isPaired = false
    /// Peers whose recent hello did not match our pairing code.
    public var mismatchedPeers: Set<String> = []
    public var octave = 3
    public var velocity = 100
    public var heldNotes: [UInt8] = []
    public var sendKeys = true
    public var receiveNotes = true
    public var keyCapture = true
    /// The last cue this Mac sent, or (on the backup) received. Nil until there is one.
    public var lastCue: CueStatus?
    /// Notes held by cue keys on this Mac.
    public var heldCueNotes: [UInt8] = []
}

/// What the "last cue" panel shows.
public struct CueStatus: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        /// Sent, waiting for the other Mac to answer.
        case waiting
        /// The other Mac answered; round trip in milliseconds.
        case delivered(ms: Double)
        /// No answer within `Conductor.cueAnswerTimeout`.
        case missing
        /// The other Mac runs a version without the delivery check.
        case unconfirmed
        /// Not connected when the cue was sent.
        case notConnected
        /// This Mac received the cue (backup side).
        case received
    }
    public var label: String
    public var memo: String
    public var note: UInt8
    /// Cues since the link came up (the same number on both Macs).
    public var count: Int
    public var delivery: Delivery
    public var peerName: String?
    public init(label: String, memo: String, note: UInt8, count: Int, delivery: Delivery, peerName: String?) {
        self.label = label; self.memo = memo; self.note = note; self.count = count; self.delivery = delivery; self.peerName = peerName
    }
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
    /// True if the peer is currently advertised on the network (Bonjour). Only used to label
    /// visible Macs whose pairing code does not match; trust comes from the pairing code.
    public var isKnownPeer: (String) -> Bool = { _ in true }
    /// Authentication and encryption; nil until a pairing code is set.
    private var channel: SecureChannel?
    /// Each peer's per-launch nonce, learned from its authenticated hello / helloAck.
    private var peerNonces: [String: [UInt8]] = [:]
    private var mismatchAt: [String: Double] = [:]
    /// Set when the app is quitting: key input is ignored from then on.
    private var quitting = false
    /// Last time an "ignored hello" was logged per peer (to keep floods out of the log).
    private var ignoredLogAt: [String: Double] = [:]
    /// Keys held longer than this are no longer protected from auto note-off.
    public static let maxProtectedHold = 600.0
    /// A cue is sent again every this many seconds while no answer comes…
    public static let cueResendInterval = 0.1
    /// …and counts as missing after this long (it is not sent again after that:
    /// a cue that starts late on the backup would do more harm than good).
    public static let cueAnswerTimeout = 0.3

    // Cue keys and the delivery check.
    /// Cue keys are kept from other apps (the event tap swallows them).
    private var blockCueKeys = false
    /// Key codes whose key-down was swallowed: their key-up is swallowed too.
    private var swallowed: Set<UInt16> = []
    private struct SentCue {
        var cue: CueKey; var count: Int; var seq: UInt32; var sentAt: Double
        var resends = 0; var delivery: CueStatus.Delivery
    }
    private var sentCue: SentCue?
    private var receivedCue: CueStatus?
    private var cueCount = 0
    /// The peer sent `features` with the cue bit (it answers cues).
    private var peerAnswersCues = false
    private var wasConnected = false
    /// Names of the peer's cue keys by (channel, note).
    private var peerCueNames: [NoteGuard.Key: (label: String, memo: String)] = [:]
    /// Sequence numbers of the peer's cue note-ons already played (to never play a resend twice).
    private var playedCueSeqs: [UInt32] = []
    private var heartbeatsSinceNames = 0

    public init(instanceID: UUID, displayName: String, mapping: KeyMapping, settings: AppSettings,
                midi: MIDIOutput?, net: PacketSink, redundancy: Int = 2,
                session: UInt32 = UInt32.random(in: 1...UInt32.max),
                clock: @escaping () -> Double, nanos: @escaping () -> UInt64) {
        self.instanceID = instanceID
        self.displayName = displayName
        self.engine = PerformanceEngine(mapping: mapping)
        self.engine.channel = UInt8(min(16, max(1, settings.midiChannel)) - 1)
        _ = self.engine.setCueKeys(settings.cueKeys)
        _ = self.engine.setPianoEnabled(settings.pianoKeys)
        self.blockCueKeys = settings.blockCueKeys
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

    /// Handles a key event. Returns true when the key should be kept from other apps
    /// (a cue key while "keep cue keys from other apps" is on).
    @discardableResult
    public func handleKey(_ input: KeyInput) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var swallow = false
        if !input.isDown, swallowed.remove(input.keycode) != nil { swallow = true }
        if input.isDown, input.isRepeat, swallowed.contains(input.keycode) { return true }
        guard keyCapture, sendKeys, !quitting else { return swallow }
        if input.isDown, blockCueKeys, input.modifiers.isEmpty, engine.isCueKey(input.keycode) {
            swallowed.insert(input.keycode); swallow = true
        }
        for (m, cue) in engine.handleEvents(input) {
            emitLocal(m, fromKeys: true)
            if let cue, case .noteOn = m { sendCue(m, cue) } else { sendRemote(m) }
        }
        return swallow
    }

    /// A datagram arrived. `knownPeer` is the peer already bound to the route it
    /// came on, if any. Returns the peer ID the packet belongs to (so the transport
    /// can bind a new route after a hello), or nil if it was not usable.
    @discardableResult
    public func receive(_ bytes: [UInt8], knownPeer: String?) -> String? {
        let isHello = SecureChannel.isHello(bytes)
        guard isHello || knownPeer != nil else { return nil }
        lock.lock(); defer { lock.unlock() }
        // Quitting: the final All Notes Off has gone out; nothing new may start.
        if quitting { return nil }
        let now = clock()
        guard let channel else { return nil }   // no pairing code: nothing is trusted

        // Authenticate before anything else.
        let packet: Packet
        if isHello {
            do { packet = try channel.openHello(bytes) } catch {
                noteMismatch(bytes, now)
                return nil
            }
        } else {
            guard let k = knownPeer, let nonce = peerNonces[k],
                  let p = try? channel.open(bytes, peerNonce: nonce) else { return nil }
            packet = p
        }

        let peer: String
        switch packet.body {
        case let .hello(id, _, _), let .helloAck(id, _, _): peer = id.uuidString
        default: peer = knownPeer!
        }
        guard peer != myID else { return nil }
        // A connection made by IP address: the first answer tells us who is on the other end.
        if let k = knownPeer, k.hasPrefix(PeerInfo.manualPrefix), link.peer == k, k != peer {
            link.renamePeer(from: k, to: peer)
            if let n = peerNames[k] { peerNames[peer] = peerNames[peer] ?? n }
        }
        switch packet.body {
        case .hello, .helloAck:
            // A hello on a new route must not take over a link that is alive on its own route
            // (the instance ID is public, so it could be someone else).
            // The same running instance (same session) opening a fresh route is allowed through.
            if knownPeer != peer, link.isConnected, link.peer == peer, now - link.lastHeard < 2,
               filters[peer]?.currentSession != packet.session {
                logIgnored(peer, now, "on a second route while the link is alive")
                return nil
            }
        default: break
        }
        if case .helloAck = packet.body, link.peer != peer {
            // Only the Mac we are connecting to may answer; anything else is not bound.
            return nil
        }
        var f = filters[peer] ?? SequenceFilter()
        let fresh = f.accept(session: packet.session, seq: packet.seq)
        filters[peer] = f
        guard fresh else { return peer }

        switch packet.body {
        case let .hello(_, nonce, name):
            setName(name, for: peer)
            peerNonces[peer] = nonce
            mismatchAt.removeValue(forKey: peer)
            perform(link.receivedHello(from: peer, now: now))
        case let .helloAck(_, nonce, name):
            setName(name, for: peer)
            peerNonces[peer] = nonce
            mismatchAt.removeValue(forKey: peer)
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
            if receiveNotes {
                emitLocal(.noteOn(channel: ch, note: note, velocity: vel), fromKeys: false)
                playedCue(seq: packet.seq, channel: ch, note: note, from: peer)
            }
        case let .cueResend(orig, ch, note, vel, released):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            guard receiveNotes else { return peer }
            if playedCueSeqs.contains(orig) {
                sendBody(.noteAck(seq: orig), to: peer)      // our answer was lost: answer again
            } else {
                emitLocal(.noteOn(channel: ch, note: note, velocity: vel), fromKeys: false)
                if released { emitLocal(.noteOff(channel: ch, note: note), fromKeys: false) }
                playedCue(seq: orig, channel: ch, note: note, from: peer)
                log("Cue \(noteName(note)) arrived on a resend")
            }
        case let .noteAck(ackSeq):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            if var c = sentCue, c.seq == ackSeq {
                switch c.delivery {
                case .waiting, .missing, .unconfirmed:
                    c.delivery = .delivered(ms: max(0, now - c.sentAt) * 1000)
                    sentCue = c
                default: break
                }
            }
        case let .features(flags):
            guard link.peer == peer else { return peer }
            peerAnswersCues = flags & 1 != 0
        case let .cueName(ch, note, label, memo):
            guard link.peer == peer else { return peer }
            peerCueNames[NoteGuard.Key(channel: ch, note: note)] = (clean(label), clean(memo))
            if peerCueNames.count > 128 { peerCueNames.removeAll() }
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
            // Each held packet covers one channel (piano keys and cue keys use different ones).
            for k in peerGuard.active.keys where k.channel == ch && !listed.contains(k) {
                emitLocal(.noteOff(channel: k.channel, note: k.note), fromKeys: false)
            }
        case .allNotesOff:
            guard link.peer == peer else { return peer }
            link.receivedOther(from: peer, now: now)
            localAllNotesOff()
            log("All Notes Off received from \(name(of: peer))")
        }
        linkChanged()
        return peer
    }

    /// Call every ~100 ms.
    public func tick() {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        perform(link.tick(now: now))
        linkChanged()
        checkCue(now)
        // A key "held" longer than maxProtectedHold probably lost its key-up: end it on both
        // Macs through the engine, so it also leaves the held list sent to the peer.
        for k in engine.heldKeys {
            if let t = keysGuard.active[k], now - t >= Self.maxProtectedHold {
                let offs = k.channel == CueKey.channel && engine.heldCueNotes.contains(k.note)
                    ? engine.releaseCue(note: k.note) : engine.release(note: k.note)
                for m in offs { emitLocal(m, fromKeys: true); sendRemote(m) }
                log("Released \(noteName(k.note)) after \(Int(Self.maxProtectedHold)) s without a key-up")
            }
        }
        // Notes whose keys are still down are not stuck: only the key-up ends them.
        let down = Set(engine.heldKeys)
        for m in keysGuard.expire(now: now, keep: down) { midi?.send(m.bytes); log("Auto note-off \(noteNameFor(m))") }
        for m in peerGuard.expire(now: now) { midi?.send(m.bytes); log("Auto note-off \(noteNameFor(m)) (from peer)") }
    }

    public func connect(to peer: String) {
        lock.lock(); defer { lock.unlock() }
        guard channel != nil else { log("Cannot connect: no pairing code set"); return }
        perform(link.connect(to: peer, now: clock()))
        linkChanged()
    }

    public func disconnect() {
        lock.lock(); defer { lock.unlock() }
        perform(link.disconnect(now: clock()))
        linkChanged()
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
            perform(link.disconnect(now: clock()))
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

    /// Sets the cue keys and tells the other Mac their names.
    public func setCueKeys(_ keys: [CueKey]) {
        lock.lock(); defer { lock.unlock() }
        for off in engine.setCueKeys(keys) { emitLocal(off, fromKeys: true); sendRemote(off) }
        if link.isConnected, let p = link.peer { sendCueNames(to: p) }
    }

    public func setPianoKeys(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        for off in engine.setPianoEnabled(on) { emitLocal(off, fromKeys: true); sendRemote(off) }
    }

    public func setBlockCueKeys(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        blockCueKeys = on
    }

    /// The transport opened a fresh route to the peer (the old one failed). The other side
    /// can only attribute packets on it after a hello, so send one right away.
    public func newRoute(to peer: String) {
        lock.lock(); defer { lock.unlock() }
        guard link.peer == peer, let channel else { return }
        sendBody(.hello(instanceID: instanceID, nonce: channel.myNonce, name: displayName), to: peer)
    }

    /// Sets (or clears) the pairing code. Changing it ends the current link.
    /// `nonce` is only for tests.
    public func setPairing(_ secret: PairingSecret?, nonce: [UInt8]? = nil) {
        lock.lock(); defer { lock.unlock() }
        if link.peer != nil { perform(link.disconnect(now: clock())) }
        channel = secret.map { SecureChannel(secret: $0, myNonce: nonce ?? SecureChannel.randomNonce()) }
        peerNonces.removeAll(); filters.removeAll(); mismatchAt.removeAll()
        log(secret == nil ? "Pairing code cleared" : "Pairing code set (fingerprint \(secret!.fingerprint))")
    }

    /// Forget sequence state and names of peers that are neither linked nor listed.
    public func prune(keeping visible: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        let keep = visible.union(link.peer.map { [$0] } ?? [])
        filters = filters.filter { keep.contains($0.key) }
        peerNames = peerNames.filter { keep.contains($0.key) }
        peerNonces = peerNonces.filter { keep.contains($0.key) }
        mismatchAt = mismatchAt.filter { keep.contains($0.key) }
    }

    public func setPeerName(_ name: String, for peer: String) {
        lock.lock(); defer { lock.unlock() }
        setName(name, for: peer)
    }

    public func snapshot() -> ConductorSnapshot {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        var cue: CueStatus? = receivedCue
        if let c = sentCue {
            cue = CueStatus(label: c.cue.label, memo: c.cue.memo, note: c.cue.note, count: c.count,
                            delivery: c.delivery, peerName: link.peer.map { name(of: $0) })
        }
        return ConductorSnapshot(link: link.state, latencyMs: link.latencyMs, peerNames: peerNames,
                                 isPaired: channel != nil,
                                 mismatchedPeers: Set(mismatchAt.filter { now - $0.value < 15 }.keys),
                                 octave: engine.octave, velocity: engine.velocity, heldNotes: engine.heldNotes,
                                 sendKeys: sendKeys, receiveNotes: receiveNotes, keyCapture: keyCapture,
                                 lastCue: cue, heldCueNotes: engine.heldCueNotes)
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

    /// Returns the sequence number used.
    @discardableResult
    private func sendBody(_ body: PacketBody, to peer: String, copies: Int = 1) -> UInt32 {
        guard let channel else { return 0 }
        seq &+= 1
        // Without the peer's nonce (no handshake yet) only hello/helloAck can be sent.
        guard let bytes = channel.seal(Packet(session: session, seq: seq, body: body), peerNonce: peerNonces[peer]) else { return seq }
        for _ in 0..<copies { net.send(bytes, to: peer) }
        return seq
    }

    // MARK: - Cues (call with lock held)

    /// A cue key went down: send it and start waiting for the answer.
    private func sendCue(_ m: MIDIMessage, _ cue: CueKey) {
        let now = clock()
        cueCount += 1
        receivedCue = nil
        guard link.isConnected, let p = link.peer, case let .noteOn(ch, n, v) = m else {
            sentCue = SentCue(cue: cue, count: cueCount, seq: 0, sentAt: now, delivery: .notConnected)
            return
        }
        let s = sendBody(.noteOn(channel: ch, note: n, velocity: v), to: p, copies: redundancy)
        sentCue = SentCue(cue: cue, count: cueCount, seq: s, sentAt: now, delivery: .waiting)
    }

    /// Resend a cue that has no answer yet; give up after `cueAnswerTimeout`.
    private func checkCue(_ now: Double) {
        guard var c = sentCue, c.delivery == .waiting else { return }
        defer { sentCue = c }
        let age = now - c.sentAt
        guard link.isConnected, let p = link.peer else { c.delivery = .missing; return }
        if age >= Self.cueAnswerTimeout {
            if peerAnswersCues {
                c.delivery = .missing
                log("Cue \(c.cue.label) (\(noteName(c.cue.note))): no answer from \(name(of: p)) within \(Int(Self.cueAnswerTimeout * 1000)) ms")
            } else {
                c.delivery = .unconfirmed
            }
            return
        }
        guard peerAnswersCues, age >= Self.cueResendInterval * Double(c.resends + 1), c.resends < 2 else { return }
        c.resends += 1
        let released = !engine.heldCueNotes.contains(c.cue.note)
        sendBody(.cueResend(originalSeq: c.seq, channel: CueKey.channel, note: c.cue.note,
                            velocity: CueKey.velocity, released: released), to: p)
    }

    /// The backup played a note-on from the peer: answer it, and show it if it is a cue.
    private func playedCue(seq: UInt32, channel ch: UInt8, note: UInt8, from peer: String) {
        sendBody(.noteAck(seq: seq), to: peer)
        playedCueSeqs.append(seq)
        if playedCueSeqs.count > 64 { playedCueSeqs.removeFirst() }
        let key = NoteGuard.Key(channel: ch, note: note)
        let named = peerCueNames[key]
        guard named != nil || (peerCueNames.isEmpty && ch == CueKey.channel) else { return }
        cueCount += 1
        sentCue = nil
        receivedCue = CueStatus(label: named?.label ?? noteName(note), memo: named?.memo ?? "", note: note,
                                count: cueCount, delivery: .received, peerName: name(of: peer))
    }

    private func sendCueNames(to p: String) {
        for k in engine.cueKeys.values.sorted(by: { $0.note < $1.note }) {
            sendBody(.cueName(channel: CueKey.channel, note: k.note, label: k.label, memo: k.memo), to: p)
        }
        heartbeatsSinceNames = 0
    }

    /// Start counting again when the link comes up.
    private func linkChanged() {
        let up = link.isConnected
        guard up != wasConnected else { return }
        wasConnected = up
        guard up else { return }
        cueCount = 0; sentCue = nil; receivedCue = nil; playedCueSeqs.removeAll()
        peerAnswersCues = false; peerCueNames.removeAll()
        if let p = link.peer {
            sendBody(.features(flags: 1), to: p)
            sendCueNames(to: p)
        }
    }

    private func clean(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
    }

    /// A hello that failed authentication: if it names a Mac visible on the network,
    /// remember it so the window can say "pairing code does not match".
    private func noteMismatch(_ bytes: [UInt8], _ now: Double) {
        guard bytes.count > SecureChannel.tagSize,
              let p = try? Packet.decode(Array(bytes.dropLast(SecureChannel.tagSize))) else { return }
        switch p.body {
        case let .hello(id, _, _), let .helloAck(id, _, _):
            let peer = id.uuidString
            guard peer != myID, isKnownPeer(peer) else { return }
            mismatchAt[peer] = now
            if mismatchAt.count > 64 { mismatchAt.removeAll() }
            logIgnored(peer, now, "pairing code does not match")
        default: break
        }
    }

    private func perform(_ actions: [LinkStateMachine.Action]) {
        for a in actions {
            switch a {
            case let .sendHello(p):
                net.resetRoute(to: p)
                if let channel { sendBody(.hello(instanceID: instanceID, nonce: channel.myNonce, name: displayName), to: p) }
            case let .sendHelloAck(p):
                if let channel { sendBody(.helloAck(instanceID: instanceID, nonce: channel.myNonce, name: displayName), to: p) }
            case let .sendHeartbeat(p):
                sendBody(.heartbeat(timestampNanos: nanos()), to: p)
                // Always send the full list (also when empty): the peer ends any of our notes
                // that are not in it, which repairs note-offs lost while the link was down.
                let on = sendKeys && keyCapture
                if CueKey.channel == engine.channel {
                    sendBody(.held(channel: engine.channel, notes: on ? engine.heldNotes + engine.heldCueNotes : []), to: p)
                } else {
                    sendBody(.held(channel: engine.channel, notes: on ? engine.heldNotes : []), to: p)
                    sendBody(.held(channel: CueKey.channel, notes: on ? engine.heldCueNotes : []), to: p)
                }
                sendBody(.features(flags: 1), to: p)
                heartbeatsSinceNames += 1
                if heartbeatsSinceNames >= 10, link.isConnected { sendCueNames(to: p) }
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
