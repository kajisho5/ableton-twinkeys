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
    /// Notes held by cue keys on this Mac.
    public var heldNotes: [UInt8] = []
    public var sendKeys = true
    public var receiveNotes = true
    public var keyCapture = true
    /// The last cue this Mac sent, or (on the backup) received. Nil until there is one.
    public var lastCue: CueStatus?
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
        /// The key of this press has been released.
        var keyUp = false
    }
    /// Cues sent recently, oldest first. Each is resent and checked on its own, so a quick
    /// second press never hides a first one that got lost.
    private var sentCues: [SentCue] = []
    private var receivedCue: CueStatus?
    /// Which was last: a cue sent from here or one received (both can happen when both Macs send).
    private var lastCueWasReceived = false
    /// This Mac's link counter, sent with every heartbeat. When the other Mac sees it change
    /// (this Mac reconnected), it starts counting again too. Random start: a restart changes it.
    private var linkEpoch = UInt8.random(in: 0...255)
    /// The other Mac's (session, epoch) last seen.
    private var peerEpoch: (session: UInt32, epoch: UInt8)?
    /// A hello from a new session of the linked peer, not yet trusted: it could be a replay of
    /// an old capture. It is used only once a packet sealed with its nonce opens.
    private var pendingHello: (peer: String, session: UInt32, seq: UInt32, nonce: [UInt8], name: String)?
    private var cueCount = 0
    /// The peer sent `features` with the cue bit (it answers cues).
    private var peerAnswersCues = false
    private var wasConnected = false
    /// Names of the peer's cue keys by (channel, note).
    private var peerCueNames: [NoteGuard.Key: (label: String, memo: String)] = [:]
    /// Sequence numbers of the peer's cue note-ons already played (to never play a resend twice).
    private var playedCueSeqs: [PlayedCue] = []
    private struct PlayedCue: Hashable { var session: UInt32; var seq: UInt32 }
    private var heartbeatsSinceNames = 0

    public init(instanceID: UUID, displayName: String, settings: AppSettings,
                midi: MIDIOutput?, net: PacketSink, redundancy: Int = 2,
                session: UInt32 = UInt32.random(in: 1...UInt32.max),
                clock: @escaping () -> Double, nanos: @escaping () -> UInt64) {
        self.instanceID = instanceID
        self.displayName = displayName
        self.engine = PerformanceEngine(cueKeys: settings.cueKeys, channel: UInt8(min(16, max(1, settings.midiChannel)) - 1))
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
        // A fresh press starts over (an entry left from a key-up that never arrived is dropped).
        if input.isDown, !input.isRepeat { swallowed.remove(input.keycode) }
        if !input.isDown, swallowed.remove(input.keycode) != nil { swallow = true }
        if input.isDown, input.isRepeat, swallowed.contains(input.keycode) { return true }
        guard keyCapture, sendKeys, !quitting else { return swallow }
        if input.isDown, blockCueKeys, input.modifiers.isEmpty, engine.isCueKey(input.keycode) {
            swallowed.insert(input.keycode); swallow = true
        }
        for (m, cue) in engine.handleEvents(input) {
            emitLocal(m, fromKeys: true)
            if let cue, case .noteOn = m { sendCue(m, cue); continue }
            if case .noteOff = m, let i = sentCues.lastIndex(where: { $0.cue.keycode == input.keycode }) {
                sentCues[i].keyUp = true
            }
            sendRemote(m)
        }
        return swallow
    }

    /// A cue button on the iPhone: the same as pressing and releasing that cue key here
    /// (works whether or not key capture is on). Returns false if it is not a cue key.
    @discardableResult
    public func pressCue(keycode: UInt16) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard sendKeys, !quitting, engine.isCueKey(keycode), !engine.held.keys.contains(keycode) else { return false }
        for input in [KeyInput(keycode: keycode, isDown: true), KeyInput(keycode: keycode, isDown: false)] {
            for (m, cue) in engine.handleEvents(input) {
                emitLocal(m, fromKeys: true)
                if let cue, case .noteOn = m { sendCue(m, cue); continue }
                if case .noteOff = m, let i = sentCues.lastIndex(where: { $0.cue.keycode == keycode }) { sentCues[i].keyUp = true }
                sendRemote(m)
            }
        }
        return true
    }

    /// Cue keys (for the iPhone's cue buttons).
    public var cueKeys: [CueKey] {
        lock.lock(); defer { lock.unlock() }
        return engine.cueKeys.values.sorted { $0.note < $1.note }
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
            guard let k = knownPeer else { return nil }
            if let nonce = peerNonces[k], let p = try? channel.open(bytes, peerNonce: nonce) {
                packet = p
            } else if let h = pendingHello, h.peer == k, let p = try? channel.open(bytes, peerNonce: h.nonce) {
                // The peer really restarted (an old capture cannot seal with our current nonce):
                // take its new session now.
                pendingHello = nil
                // Keep the list of the peer's earlier sessions: they must stay refused.
                var f = filters[k] ?? SequenceFilter()
                _ = f.accept(session: h.session, seq: h.seq)
                filters[k] = f
                peerNonces[k] = h.nonce
                setName(h.name, for: k)
                perform(link.receivedHello(from: k, now: now))
                log("\(name(of: k)) restarted; continuing with its new session")
                // Its new instance cannot know which cues the old one played: do not resend them
                // (they show as not confirmed), and count from zero like after any reconnect.
                resetCues()
                peerEpoch = nil
                packet = p
            } else {
                return nil
            }
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
        if case let .hello(_, nonce, name) = packet.body, link.isConnected, link.peer == peer,
           let current = filters[peer]?.currentSession, current != packet.session {
            // A session the peer already left behind is never taken back (replays).
            if filters[peer]?.isRetired(packet.session) == true { return nil }
            // A hello from another session while the link is up: the peer restarted, or someone
            // replays an old hello. Answer it, but change nothing until the new session proves
            // itself (see the open above). The route is not rebound either.
            pendingHello = (peer, packet.session, packet.seq, nonce, name)
            sendBody(.helloAck(instanceID: instanceID, nonce: channel.myNonce, name: displayName), to: peer)
            return nil
        }
        var f = filters[peer] ?? SequenceFilter()
        let orderFree: Bool
        switch packet.body {
        case .heartbeat, .heartbeatAck, .held, .features, .cueName, .noteAck, .cueCount, .liveAck, .liveStatus, .setSummary, .setItem, .liveResult, .roleClaim, .remoteSummary, .desk: orderFree = true
        case let .liveCommand(_, c): orderFree = !c.isContinuous   // a late fader value must not overwrite a newer one
        default: orderFree = false
        }
        let fresh = f.accept(session: packet.session, seq: packet.seq, allowLate: orderFree)
        filters[peer] = f
        // A repeated packet changes nothing (a repeated hello must not move the route either).
        guard fresh else {
            switch packet.body { case .hello, .helloAck: return nil; default: return peer }
        }

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
                playedCue(session: packet.session, seq: packet.seq, channel: ch, note: note, from: peer)
            }
        case let .cueResend(orig, ch, note, vel, released):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            guard receiveNotes else { return peer }
            if playedCueSeqs.contains(PlayedCue(session: packet.session, seq: orig)) {
                sendBody(.noteAck(seq: orig), to: peer)      // our answer was lost: answer again
            } else {
                emitLocal(.noteOn(channel: ch, note: note, velocity: vel), fromKeys: false)
                if released { emitLocal(.noteOff(channel: ch, note: note), fromKeys: false) }
                playedCue(session: packet.session, seq: orig, channel: ch, note: note, from: peer)
                log("Cue \(noteName(note)) arrived on a resend")
            }
        case let .noteAck(ackSeq):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            if let i = sentCues.firstIndex(where: { $0.seq == ackSeq }) {
                switch sentCues[i].delivery {
                case .waiting, .missing, .unconfirmed:
                    sentCues[i].delivery = .delivered(ms: max(0, now - sentCues[i].sentAt) * 1000)
                default: break
                }
            }
        case let .features(flags, epoch):
            guard link.peer == peer else { return peer }
            peerAnswersCues = flags & 1 != 0
            // The other Mac (re)connected and started counting again, maybe without this Mac
            // noticing a drop: start again too, and send our cue names (it forgot them).
            // 1.0.1 and later repeat their link counter (epoch) with every heartbeat, so one lost
            // packet does not matter; 1.0.0 only sends bit 2 once.
            var restarted: Bool
            if let e = epoch {
                if let old = peerEpoch {
                    restarted = old.session != packet.session || old.epoch != e
                } else {
                    // First counter seen since this link came up: bit 2 only matters if cues were
                    // already counted here (both Macs reset at link-up; do not reset twice).
                    restarted = flags & 2 != 0 && countedSinceReset
                }
                peerEpoch = (packet.session, e)
            } else {
                restarted = flags & 2 != 0          // 1.0.0
            }
            if restarted, link.isConnected {
                resetCues()
                sendBody(features(), to: peer)
                sendCueNames(to: peer)
            }
        case let .liveCommand(id, cmd):
            guard link.peer == peer, link.isConnected else { return peer }
            link.receivedOther(from: peer, now: now)
            let key = PlayedCue(session: packet.session, seq: id)
            if !ranLiveCommands.contains(key) {
                ranLiveCommands.append(key)
                if ranLiveCommands.count > 256 { ranLiveCommands.removeFirst() }
                if let run = onLiveCommandRun {
                    // Tell the main Mac what this Mac's Live did, once it has answered.
                    run(cmd) { [weak self] r in
                        // Never under the lock (the hook may answer right away).
                        DispatchQueue.global().async { self?.reportLiveRun(id: id, r, to: peer) }
                    }
                } else {
                    onLiveCommand?(cmd)
                }
            }
            sendBody(.liveAck(id: id), to: peer)
        case let .liveAck(id):
            guard link.peer == peer else { return peer }
            // A repeated ack (the command was sent again) must not hide what the backup's Live did.
            if var p = pendingLive[id], ["waiting", "missing", "unconfirmed"].contains(p.delivery) {
                p.delivery = "delivered"; pendingLive[id] = p
            }
        case let .liveStatus(on):
            guard link.peer == peer else { return peer }
            peerLive = on
        case let .remoteSummary(phones, watch):
            guard link.peer == peer else { return peer }
            peerRemote = RemoteSummary(phones: Int(phones), watch: WatchLevel(rawValue: watch) ?? .absent)
        case let .desk(d):
            guard link.peer == peer, link.isConnected else { return peer }
            let (adopt, replies) = deskShare.received(d, me: myID, peer: peer, myName: displayName, peerName: name(of: peer), now: now)
            for r in replies { sendBody(.desk(r), to: peer) }
            if let adopt {
                log("Console settings taken over from \(name(of: peer))")
                onDeskSettings?(adopt)
            }
        case let .roleClaim(ms):
            guard link.peer == peer, link.isConnected else { return peer }
            seenClaim = max(seenClaim, ms)
            let theirsNewer = ms > mainClaim || (ms == mainClaim && peer > myID)
            if theirsNewer {
                if sendKeys || mainClaim > 0 { becomeReceiver() }
            } else if mainClaim > 0 {
                sendBody(.roleClaim(millis: mainClaim), to: peer)    // ours is newer: tell them now
            }
        case .roleHandover:
            guard link.peer == peer, link.isConnected else { return peer }
            claimMainLocked()
        case let .liveResult(id, code):
            guard link.peer == peer else { return peer }
            if var p = pendingLive[id] {
                p.delivery = code == 0 ? "ran" : code == 1 ? "failedLive" : "noLive"
                pendingLive[id] = p
            }
        case let .setSummary(t, sc, h):
            guard link.peer == peer else { return peer }
            var ps = peerSet ?? PeerSet()
            ps.summary(tracks: Int(t), scenes: Int(sc), hash: h)
            peerSet = ps
        case let .setItem(kind, index, name):
            guard link.peer == peer, var ps = peerSet, let k = SetItemKind(rawValue: kind) else { return peer }
            ps.item(kind: k, index: Int(index), name: name)
            peerSet = ps
        case let .cueCount(cueSeq, count):
            guard link.peer == peer else { return peer }
            applyPeerCount(session: packet.session, seq: cueSeq, count: Int(count))
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
        checkLive(now)
        // A key "held" longer than maxProtectedHold probably lost its key-up: end it on both
        // Macs through the engine, so it also leaves the held list sent to the peer.
        for note in engine.heldNotes {
            let k = NoteGuard.Key(channel: engine.channel, note: note)
            if let t = keysGuard.active[k], now - t >= Self.maxProtectedHold {
                for m in engine.release(note: note) { emitLocal(m, fromKeys: true); sendRemote(m) }
                log("Released \(noteName(note)) after \(Int(Self.maxProtectedHold)) s without a key-up")
            }
        }
        // Notes whose keys are still down are not stuck: only the key-up ends them.
        let down = Set(engine.heldNotes.map { NoteGuard.Key(channel: engine.channel, note: $0) })
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
        // Key-ups may never come: do not keep swallowing those keys.
        swallowed.removeAll()
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

    /// Sets the cue keys and tells the other Mac their names.
    public func setCueKeys(_ keys: [CueKey]) {
        lock.lock(); defer { lock.unlock() }
        for off in engine.setCueKeys(keys) { emitLocal(off, fromKeys: true); sendRemote(off) }
        if link.isConnected, let p = link.peer { sendCueNames(to: p) }
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
        var cue: CueStatus? = lastCueWasReceived ? receivedCue : nil
        // A cue that was not confirmed stays on screen (in red) until the next press, even if a
        // later one was confirmed; otherwise the newest sent cue is shown.
        if let c = sentCues.last(where: { $0.delivery == .missing }) ?? (lastCueWasReceived ? nil : sentCues.last) {
            cue = CueStatus(label: c.cue.label, memo: c.cue.memo, note: c.cue.note, count: c.count,
                            delivery: c.delivery, peerName: link.peer.map { name(of: $0) })
        }
        return ConductorSnapshot(link: link.state, latencyMs: link.latencyMs, peerNames: peerNames,
                                 isPaired: channel != nil,
                                 mismatchedPeers: Set(mismatchAt.filter { now - $0.value < 15 }.keys),
                                 heldNotes: engine.heldNotes,
                                 sendKeys: sendKeys, receiveNotes: receiveNotes, keyCapture: keyCapture,
                                 lastCue: cue)
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
        countedSinceReset = true
        lastCueWasReceived = false
        // Cues already settled were shown; a new press starts a fresh view.
        sentCues.removeAll { $0.delivery != .waiting }
        if sentCues.count >= 16 { sentCues.removeFirst() }
        guard link.isConnected, let p = link.peer, case let .noteOn(ch, n, v) = m else {
            sentCues.append(SentCue(cue: cue, count: cueCount, seq: 0, sentAt: now, delivery: .notConnected))
            return
        }
        let s = sendBody(.noteOn(channel: ch, note: n, velocity: v), to: p, copies: redundancy)
        sendBody(.cueCount(seq: s, count: UInt32(cueCount)), to: p, copies: redundancy)
        sentCues.append(SentCue(cue: cue, count: cueCount, seq: s, sentAt: now, delivery: .waiting))
    }

    /// Resend cues that have no answer yet; give up after `cueAnswerTimeout`.
    private func checkCue(_ now: Double) {
        for i in sentCues.indices where sentCues[i].delivery == .waiting {
            let c = sentCues[i]
            let age = now - c.sentAt
            guard link.isConnected, let p = link.peer else { sentCues[i].delivery = .missing; continue }
            if age >= Self.cueAnswerTimeout {
                if peerAnswersCues {
                    sentCues[i].delivery = .missing
                    log("Cue \(c.cue.label) (\(noteName(c.cue.note))): no answer from \(name(of: p)) within \(Int(Self.cueAnswerTimeout * 1000)) ms")
                } else {
                    sentCues[i].delivery = .unconfirmed
                }
                continue
            }
            guard peerAnswersCues, age >= Self.cueResendInterval * Double(c.resends + 1), c.resends < 2 else { continue }
            sentCues[i].resends += 1
            sendBody(.cueCount(seq: c.seq, count: UInt32(c.count)), to: p)
            sendBody(.cueResend(originalSeq: c.seq, channel: engine.channel, note: c.cue.note,
                                velocity: CueKey.velocity, released: c.keyUp || !engine.heldNotes.contains(c.cue.note)), to: p)
        }
    }

    /// The backup played a note-on from the peer: answer it, and show it if it is a cue.
    private func playedCue(session: UInt32, seq: UInt32, channel ch: UInt8, note: UInt8, from peer: String) {
        sendBody(.noteAck(seq: seq), to: peer)
        playedCueSeqs.append(PlayedCue(session: session, seq: seq))
        if playedCueSeqs.count > 64 { playedCueSeqs.removeFirst() }
        let key = NoteGuard.Key(channel: ch, note: note)
        let named = peerCueNames[key]
        // Every note from the other Mac is a cue (1.0 sends nothing else); a name that has not
        // arrived yet only changes the label.
        let played = PlayedCue(session: session, seq: seq)
        // An older cue that arrived late (a resend after a newer one): it plays, but the screen
        // keeps showing the newest cue and its number.
        if let last = lastPlayed, last.session == session, Int32(bitPattern: seq &- last.seq) < 0, lastCueWasReceived {
            peerCounts.removeValue(forKey: played)
            return
        }
        lastPlayed = played
        if let n = peerCounts.removeValue(forKey: played) { cueCount = n } else { cueCount += 1 }
        countedSinceReset = true
        lastCueWasReceived = true
        receivedCue = CueStatus(label: named?.label ?? noteName(note), memo: named?.memo ?? "", note: note,
                                count: cueCount, delivery: .received, peerName: name(of: peer))
    }

    private func sendCueNames(to p: String) {
        for k in engine.cueKeys.values.sorted(by: { $0.note < $1.note }) {
            sendBody(.cueName(channel: engine.channel, note: k.note, label: k.label, memo: k.memo), to: p)
        }
        heartbeatsSinceNames = 0
    }

    /// Start counting again when the link comes up.
    private func linkChanged() {
        let up = link.isConnected
        guard up != wasConnected else { return }
        wasConnected = up
        deskShare.linkChanged()
        guard up else { pendingHello = nil; return }
        resetCues()
        peerAnswersCues = false; peerCueNames.removeAll(); peerEpoch = nil; pendingHello = nil
        linkEpoch &+= 1
        if let p = link.peer {
            // Bit 2: "I start counting again" (for 1.0.0); the new epoch does the same for 1.0.1+.
            sendBody(.features(flags: 3, epoch: linkEpoch), to: p, copies: redundancy)
            sendCueNames(to: p)
            sendDesk(rows: true, to: p)
        }
    }

    private func features() -> PacketBody { .features(flags: 1, epoch: linkEpoch) }

    /// Start counting again. A cue still waiting for its answer is reported as not confirmed
    /// instead of disappearing.
    private var countedSinceReset = false

    // MARK: Live commands from the iPhone (2.0)

    /// The backup runs Live commands forwarded by the main Mac here (called with the lock held:
    /// hand the work to another queue).
    public var onLiveCommand: ((LiveCommand) -> Void)?
    /// 2.2: like `onLiveCommand`, but the hook calls back with what Live did; the main Mac then
    /// knows the command really ran on the backup (not only that it arrived). Used when set.
    public var onLiveCommandRun: ((LiveCommand, @escaping (LiveRun) -> Void) -> Void)?

    public enum LiveRun: UInt8, Sendable { case ran = 0, refused = 1, noAnswer = 2 }

    private func reportLiveRun(id: UInt32, _ r: LiveRun, to peer: String) {
        lock.lock(); defer { lock.unlock() }
        guard link.peer == peer, link.isConnected else { return }
        sendBody(.liveResult(id: id, code: r.rawValue), to: peer, copies: redundancy)
    }
    private var ranLiveCommands: [PlayedCue] = []
    private struct PendingLive { var cmd: LiveCommand; var sentAt: Double; var resends = 0; var delivery = "waiting" }
    private var pendingLive: [UInt32: PendingLive] = [:]
    private var liveCommandID: UInt32 = 0

    /// Whether this Mac's Live answers (TwinKeysBridge); told to the other Mac with each heartbeat.
    private var localLive: Bool?
    /// Whether the other Mac's Live answers, as it last told us (nil: unknown or not linked).
    private var peerLive: Bool?
    /// Fader, pan, tempo, mute and solo values set while the backup was not linked: the newest one
    /// per control is sent when the link is back, so the two Lives do not stay apart. Clip and scene
    /// launches are never sent late.
    private var unsentLatest: [String: LiveCommand] = [:]
    private var wasLinkedForLive = false

    // MARK: Switching to the backup (2.3)

    /// This Mac's claim to be the main; 0: no claim. Compared across Macs (the higher wins). It
    /// is the wall-clock time in ms (as 2.2.0 sends it), but always above every claim seen from the
    /// other Mac, so a later claim wins even when this Mac's clock is behind.
    private var mainClaim: UInt64 = 0
    /// The highest claim the other Mac has sent.
    private var seenClaim: UInt64 = 0
    /// Seconds since 1970 (both Macs keep network time, so claims compare across Macs).
    public var wallClock: () -> Double = { Date().timeIntervalSince1970 }
    /// Called (with the lock held: hand the work to another queue) when this Mac becomes the
    /// main (true) or stops being it because the other Mac claimed it (false).
    public var onRoleChange: ((Bool) -> Void)?

    public var claimsMain: Bool { lock.lock(); defer { lock.unlock() }; return mainClaim > 0 }

    /// "Make this Mac the main": send keys, stop playing the other Mac's notes, and tell the
    /// other Mac (if it comes back it stops sending keys).
    public func claimMain() {
        lock.lock(); defer { lock.unlock() }
        claimMainLocked()
    }

    /// "Return to main": this Mac only receives again and asks the other Mac to be the main.
    /// Only while linked (otherwise the other Mac never hears it and both Macs would only
    /// receive): returns false and changes nothing when not linked.
    @discardableResult
    public func handOverMain() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard link.isConnected, let p = link.peer else {
            log("Return to Main refused: not linked to the other Mac")
            return false
        }
        becomeReceiver()
        sendBody(.roleHandover, to: p, copies: redundancy)
        return true
    }

    private func claimMainLocked() {
        mainClaim = max(UInt64(max(0, wallClock()) * 1000), mainClaim + 1, seenClaim + 1)
        sendKeys = true
        receiveNotes = false
        for m in peerGuard.releaseAll() { midi?.send(m.bytes) }
        if link.isConnected, let p = link.peer { sendBody(.roleClaim(millis: mainClaim), to: p, copies: redundancy) }
        log("This Mac is now the main Mac")
        onRoleChange?(true)
    }

    private func becomeReceiver() {
        if sendKeys { apply(.sendingTurnedOff, peer: link.isConnected ? link.peer : nil) }
        sendKeys = false
        receiveNotes = true
        mainClaim = 0
        log("The other Mac is the main Mac now: this Mac only receives")
        onRoleChange?(false)
    }

    /// This Mac's Live set (names only) and the other Mac's as it has told us (2.1 set check).
    private var localSet: SetSummary?
    private var peerSet: PeerSet?
    /// Next name to send (tracks first, then scenes), a few per heartbeat.
    private var setCursor = 0
    static let setItemsPerHeartbeat = 8

    /// nil while this Mac's Live does not answer (then nothing is compared).
    public func setLocalSet(_ s: SetSummary?) {
        lock.lock(); defer { lock.unlock() }
        if s != localSet { localSet = s; setCursor = 0 }
    }

    /// How this Mac's set differs from the other Mac's, or nil (same, or not known yet).
    public var setDiff: SetDiff? {
        lock.lock(); defer { lock.unlock() }
        guard link.isConnected, let localSet else { return nil }
        return SetDiff.compare(mine: localSet, peer: peerSet)
    }

    /// With each heartbeat: the summary, and the next few names (round and round, so a lost
    /// packet is repaired on the next pass).
    private func sendSet(to p: String) {
        guard let s = localSet else { return }
        sendBody(.setSummary(tracks: UInt16(clamping: s.tracks.count), scenes: UInt16(clamping: s.scenes.count), hash: s.hash), to: p)
        let total = s.tracks.count + s.scenes.count
        guard total > 0 else { return }
        for _ in 0..<min(Self.setItemsPerHeartbeat, total) {
            if setCursor >= total { setCursor = 0 }
            let i = setCursor
            setCursor += 1
            if i < s.tracks.count {
                sendBody(.setItem(kind: SetItemKind.track.rawValue, index: UInt16(clamping: i), name: s.tracks[i]), to: p)
            } else {
                let j = i - s.tracks.count
                sendBody(.setItem(kind: SetItemKind.scene.rawValue, index: UInt16(clamping: j), name: s.scenes[j]), to: p)
            }
        }
    }

    public func setLiveConnected(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        localLive = on
    }

    public var peerLiveConnected: Bool? {
        lock.lock(); defer { lock.unlock() }
        return link.isConnected ? peerLive : nil
    }

    // MARK: Connection display (docs/design-links.md)

    /// This Mac's iPhones and their Apple Watch; told to the other Mac with each heartbeat.
    private var localRemote: RemoteSummary?
    /// The other Mac's, as it last told us (nil: not linked, or a version without it).
    private var peerRemote: RemoteSummary?

    /// The approved iPhones connected to this Mac and their watch. A change is sent at once.
    public func setRemoteSummary(_ s: RemoteSummary) {
        lock.lock(); defer { lock.unlock() }
        guard s != localRemote else { return }
        localRemote = s
        if link.isConnected, let p = link.peer { sendRemoteSummary(to: p) }
    }

    /// The other Mac's iPhones (the backup shows "iPhone connected to the main Mac").
    public var peerRemoteSummary: RemoteSummary? {
        lock.lock(); defer { lock.unlock() }
        return link.isConnected ? peerRemote : nil
    }

    private func sendRemoteSummary(to p: String) {
        guard let s = localRemote else { return }
        sendBody(.remoteSummary(phones: UInt8(clamping: s.phones), watch: s.watch.rawValue), to: p)
    }

    // MARK: Console settings shared between the Macs (2.4)

    /// The sharing of the console settings (packet `desk`).
    private var deskShare = DeskShare()
    /// Called (with the lock held: hand the work to another queue) with the other Mac's newer
    /// console settings, taken over (this Mac's `moveDeskWhenConfirming` kept).
    public var onDeskSettings: ((DeskSettings) -> Void)?

    /// This Mac's console settings (normalized to this Mac and the linked one). A change of the
    /// shared part is sent to the other Mac at once.
    public func setDeskSettings(_ s: DeskSettings) {
        lock.lock(); defer { lock.unlock() }
        if deskShare.setLocal(s), link.isConnected, let p = link.peer { sendDesk(rows: true, to: p) }
    }

    /// This Mac's own console link; told to the other Mac with each heartbeat and when it changes.
    public func setDeskStatus(_ st: DeskPeerStatus) {
        lock.lock(); defer { lock.unlock() }
        if deskShare.setStatus(st), link.isConnected, let p = link.peer { sendDesk(rows: false, to: p) }
    }

    /// The other Mac's console link as it told us (nil: not linked, or a version without it).
    public var peerDeskStatus: DeskPeerStatus? {
        lock.lock(); defer { lock.unlock() }
        return link.isConnected ? deskShare.peerStatus : nil
    }

    private func sendDesk(rows: Bool, to p: String) {
        sendBody(.desk(deskShare.summary(me: myID, peer: p)), to: p)
        if rows { for r in deskShare.rows(me: myID, peer: p) { sendBody(.desk(r), to: p) } }
    }

    /// The control a "latest value counts" command sets, or nil for one-shot commands.
    static func latestKey(_ cmd: LiveCommand) -> String? {
        switch cmd {
        case let .setVolume(t, _): return "v\(t)"
        case let .setPan(t, _): return "p\(t)"
        case let .setSend(t, k, _): return "send\(k)/\(t)"
        case .setTempo: return "tempo"
        case let .setMute(t, _): return "m\(t)"
        case let .setSolo(t, _): return "s\(t)"
        default: return nil
        }
    }

    /// Main Mac: forwards a Live command to the backup (same resend rules as cues).
    /// Returns its id, or nil when not linked.
    @discardableResult
    public func forwardLive(_ cmd: LiveCommand) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        guard cmd.isValid else { return nil }
        guard link.isConnected, let p = link.peer else {
            if let k = Self.latestKey(cmd), unsentLatest.count < 512 || unsentLatest[k] != nil { unsentLatest[k] = cmd }
            return nil
        }
        // A newer value replaces one still waiting to catch up (the rest go out on the next tick).
        if let k = Self.latestKey(cmd) { unsentLatest[k] = nil }
        return sendLive(cmd, to: p)
    }

    private func sendLive(_ cmd: LiveCommand, to p: String) -> UInt32 {
        liveCommandID &+= 1
        let id = liveCommandID
        // Only the newest value of a fader counts: drop older ones still waiting.
        if cmd.isContinuous { pendingLive = pendingLive.filter { !Self.sameControl($0.value.cmd, cmd) || $0.value.delivery != "waiting" } }
        pendingLive[id] = PendingLive(cmd: cmd, sentAt: clock())
        if pendingLive.count > 64, let oldest = pendingLive.keys.min() { pendingLive.removeValue(forKey: oldest) }
        sendBody(.liveCommand(id: id, cmd), to: p, copies: redundancy)
        return id
    }

    /// "waiting", "delivered" (arrived), "ran" / "failedLive" / "noLive" (what the backup's Live did,
    /// 2.2 backups), "missing" (no answer in time), "unconfirmed" (old backup), "unknown".
    /// The backup has said all it will about a Live command (or never will): no need to wait.
    /// "delivered" waits for its liveResult (2.2+ backups send one).
    public static func isSettledLiveDelivery(_ d: String) -> Bool {
        !["waiting", "delivered"].contains(d)
    }

    public func liveDelivery(_ id: UInt32) -> String {
        lock.lock(); defer { lock.unlock() }
        return pendingLive[id]?.delivery ?? "unknown"
    }

    private static func sameControl(_ a: LiveCommand, _ b: LiveCommand) -> Bool {
        switch (a, b) {
        case let (.setVolume(t1, _), .setVolume(t2, _)), let (.setPan(t1, _), .setPan(t2, _)): return t1 == t2
        case let (.setSend(t1, k1, _), .setSend(t2, k2, _)): return t1 == t2 && k1 == k2
        case (.setTempo, .setTempo): return true
        default: return false
        }
    }

    private func checkLive(_ now: Double) {
        guard let p = link.peer, link.isConnected else {
            for k in pendingLive.keys where pendingLive[k]!.delivery == "waiting" { pendingLive[k]!.delivery = "missing" }
            wasLinkedForLive = false
            peerLive = nil
            peerSet = nil
            peerRemote = nil
            return
        }
        if !wasLinkedForLive {
            wasLinkedForLive = true
            // Back in touch: bring the backup's faders, tempo, mute and solo up to date.
            let catchUp = unsentLatest.sorted { $0.key < $1.key }.map(\.value)
            unsentLatest.removeAll()
            if !catchUp.isEmpty { log("Remote: sending \(catchUp.count) mixer/tempo change(s) made while the backup was not linked") }
            for c in catchUp { _ = sendLive(c, to: p) }
        }
        for (id, var c) in pendingLive where c.delivery == "waiting" {
            let age = now - c.sentAt
            if age >= Self.cueAnswerTimeout {
                c.delivery = peerAnswersCues ? "missing" : "unconfirmed"
            } else if peerAnswersCues, age >= Self.cueResendInterval * Double(c.resends + 1), c.resends < 2, !c.cmd.isContinuous {
                c.resends += 1
                sendBody(.liveCommand(id: id, c.cmd), to: p)
            }
            pendingLive[id] = c
        }
        // Forget settled commands after a while.
        pendingLive = pendingLive.filter { $0.value.delivery == "waiting" || now - $0.value.sentAt < 10 }
    }
    /// The main Mac's count for its cues (by its session and note-on seq), applied when the cue plays.
    private var peerCounts: [PlayedCue: Int] = [:]
    private var lastPlayed: PlayedCue?

    /// The main Mac told its count for a cue: show that number (it may arrive before or after the note).
    private func applyPeerCount(session: UInt32, seq: UInt32, count: Int) {
        let key = PlayedCue(session: session, seq: seq)
        if lastPlayed == key, var c = receivedCue {
            c.count = count; receivedCue = c; cueCount = count
        } else {
            peerCounts[key] = count
            if peerCounts.count > 32 { peerCounts.removeAll() }
        }
    }

    private func resetCues() {
        countedSinceReset = false
        cueCount = 0; receivedCue = nil; lastCueWasReceived = false
        sentCues = sentCues.filter { $0.delivery == .waiting || $0.delivery == .missing }
        for i in sentCues.indices { sentCues[i].delivery = .missing }
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
                sendBody(.held(channel: engine.channel, notes: on ? engine.heldNotes : []), to: p)
                sendBody(features(), to: p)
                if let localLive { sendBody(.liveStatus(connected: localLive), to: p) }
                sendRemoteSummary(to: p)
                if mainClaim > 0 { sendBody(.roleClaim(millis: mainClaim), to: p) }
                sendSet(to: p)
                sendDesk(rows: false, to: p)
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
