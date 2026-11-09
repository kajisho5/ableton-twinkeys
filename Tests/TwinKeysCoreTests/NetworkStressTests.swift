import XCTest
@testable import TwinKeysCore

/// Seeded random simulation of two Macs over a lossy, duplicating, reordering network.
final class NetworkStressTests: XCTestCase {
    struct RNG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 {
            s &+= 0x9E3779B97F4A7C15; var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func p(_ x: Double) -> Bool { Double.random(in: 0..<1, using: &self) < x }
        mutating func d(_ a: Double, _ b: Double) -> Double { Double.random(in: a..<b, using: &self) }
    }
    struct Flight { var at: Double; var order: Int; var bytes: [UInt8]; var toBackup: Bool }
    struct Press { var session: UInt32; var seq: UInt32; var t: Double; var clean: Bool; var count = 0; var played = 0; var delivered = false }

    final class Sim {
        var rng: RNG; var now = 0.0; var events: [String] = []; var failures: [String] = []
        let secret = PairingSecret(keyBytes: Array(repeating: 7, count: 32))
        let mainID = UUID(), backupID = UUID()
        let mainMIDI = ConductorTests.FakeMIDI(), backupMIDI = ConductorTests.FakeMIDI()
        let mainNet = ConductorTests.FakeNet(), backupNet = ConductorTests.FakeNet()
        var main: Conductor!, backup: Conductor!
        var mainSession: UInt32 = 100, backupSession: UInt32 = 900
        var mainNonces: [[UInt8]] = [], backupNonces: [[UInt8]] = []
        var autoOff: Double
        var loss = [0.0, 0.0], outageUntil = [0.0, 0.0], dup = 0.0, reorder = 0.0
        var flights: [Flight] = [], order = 0, nextTick = [0.0, 0.0]
        var held: Set<UInt16> = [], presses: [Press] = [], disturb: [Double] = []
        var needsConnect = [false, false], stableSince: Double?
        let keys = [KeyNames.up, KeyNames.down, KeyNames.left]

        init(seed: UInt64) { rng = RNG(s: seed); autoOff = 0; autoOff = rng.p(0.5) ? 0 : 10 }
        func ev(_ s: String) { events.append(String(format: "%.3f ", now) + s) }
        func fail(_ s: String) { failures.append(String(format: "%.3f ", now) + s) }
        var netClean: Bool { loss == [0, 0] && reorder == 0 && now >= outageUntil[0] && now >= outageUntil[1] }

        func make(backupSide b: Bool) -> Conductor {
            let n = (0..<16).map { _ in UInt8.random(in: 0...255, using: &rng) }
            var s = AppSettings(); s.autoNoteOffSeconds = autoOff
            if b { s.sendKeys = false; backupSession += 1; backupNonces.append(n) } else { s.receiveNotes = false; mainSession += 1; mainNonces.append(n) }
            let c = Conductor(instanceID: b ? backupID : mainID, displayName: b ? "Backup" : "Main", settings: s,
                              midi: b ? backupMIDI : mainMIDI, net: b ? backupNet : mainNet,
                              session: b ? backupSession : mainSession,
                              clock: { [unowned self] in now }, nanos: { [unowned self] in UInt64(now * 1e9) })
            c.setPairing(secret, nonce: n)
            if ProcessInfo.processInfo.environment["STRESS_VERBOSE"] != nil { c.log = { [unowned self] in self.ev((b ? "B: " : "M: ") + $0) } }
            return c
        }
        func c(_ b: Bool) -> Conductor { b ? backup : main }
        func peerID(_ b: Bool) -> String { (b ? mainID : backupID).uuidString }

        func collect() {
            for (_, x) in mainNet.outbox { enqueue(x, true) }; mainNet.outbox.removeAll()
            for (_, x) in backupNet.outbox { enqueue(x, false) }; backupNet.outbox.removeAll()
        }
        func enqueue(_ x: [UInt8], _ toB: Bool) {
            let d = toB ? 0 : 1
            if now < outageUntil[d] || rng.p(loss[d]) { return }
            for _ in 0..<(rng.p(dup) ? 2 : 1) {
                let delay = 0.002 + (rng.p(reorder) ? rng.d(0, 0.25) : 0)
                flights.append(Flight(at: now + delay, order: order, bytes: x, toBackup: toB)); order += 1
            }
        }
        func be32(_ x: [UInt8], _ i: Int) -> UInt32 { x[i..<i+4].reduce(0) { $0 << 8 | UInt32($1) } }
        func deliver() {
            let due = flights.filter { $0.at <= now }.sorted { ($0.at, $0.order) < ($1.at, $1.order) }
            flights.removeAll { $0.at <= now }
            for f in due {
                if f.bytes[3] <= 3, ProcessInfo.processInfo.environment["STRESS_VERBOSE"] != nil { ev("deliver type \(f.bytes[3]) sess \(be32(f.bytes, 4)) toBackup \(f.toBackup)") }
                if f.toBackup {
                    let before = backupMIDI.sent.count
                    backup.receive(f.bytes, knownPeer: mainID.uuidString)
                    let ons = backupMIDI.sent[before...].filter { $0[0] == 0x90 && $0[2] > 0 }.count
                    if ons > 0 { attribute(f.bytes, ons) }
                } else {
                    let pe = String(describing: Mirror(reflecting: main!).children.first { $0.label == "peerEpoch" }!.value)
                    let r = main.receive(f.bytes, knownPeer: backupID.uuidString)
                    if f.bytes[3] == 0x13, ProcessInfo.processInfo.environment["STRESS_VERBOSE"] != nil { ev("M features sess \(be32(f.bytes, 4)) seq \(be32(f.bytes, 8)) ok \(r != nil) peerEpoch before \(pe) count \(main.snapshot().lastCue?.count ?? -1)") }
                    if ProcessInfo.processInfo.environment["STRESS_VERBOSE2"] != nil { ev("M<- type \(f.bytes[3]) sess \(be32(f.bytes, 4)) seq \(be32(f.bytes, 8)) ok \(r != nil) \(main.snapshot().link)") }
                    if f.bytes[3] == 0x14 { observeDelivered() }
                }
                collect()
            }
        }
        func attribute(_ x: [UInt8], _ ons: Int) {
            let session = be32(x, 4); var seq = be32(x, 8)
            if x[3] == 0x16 {
                var orig: UInt32?
                for m in mainNonces { for b in backupNonces {
                    if let p = try? SecureChannel(secret: secret, myNonce: b).open(x, peerNonce: m),
                       case let .cueResend(o, _, _, _, _) = p.body { orig = o } } }
                guard let o = orig else { return fail("undecodable resend played") }
                seq = o
            }
            guard let i = presses.firstIndex(where: { $0.session == session && $0.seq == seq }) else { return fail("note-on not from any press (type \(x[3]))") }
            presses[i].played += ons
            ev("backup played press \(i) count \(presses[i].count) -> backup count \(backup.snapshot().lastCue?.count ?? -1)")
            if presses[i].played > 1 { fail("press \(i) (seq \(seq)) played \(presses[i].played)x on backup") }
        }
        func sentCues() -> [(seq: UInt32, d: CueStatus.Delivery)] {
            guard let arr = Mirror(reflecting: main!).children.first(where: { $0.label == "sentCues" })?.value else { return [] }
            return Mirror(reflecting: arr).children.map { e in
                let m = Dictionary(uniqueKeysWithValues: Mirror(reflecting: e.value).children.map { ($0.label!, $0.value) })
                return (m["seq"] as! UInt32, m["delivery"] as! CueStatus.Delivery)
            }
        }
        func observeDelivered() {
            for c in sentCues() { if case .delivered = c.d, let i = presses.firstIndex(where: { $0.session == mainSession && $0.seq == c.seq }), !presses[i].delivered {
                presses[i].delivered = true
                if presses[i].played == 0 { fail("press \(i) shown delivered but never played") }
            } }
        }
        func key(_ k: UInt16, down: Bool, rep: Bool = false) {
            let mark = mainNet.outbox.count
            main.handleKey(KeyInput(keycode: k, isDown: down, isRepeat: rep))
            ev("key \(k) \(down ? (rep ? "repeat" : "down") : "up")")
            if down, !rep, let x = mainNet.outbox[mark...].first(where: { $0.bytes[3] == 0x10 })?.bytes {
                let ok = netClean && stableSince.map { now - $0 >= 1.5 } == true
                presses.append(Press(session: mainSession, seq: be32(x, 8), t: now, clean: ok, count: main.snapshot().lastCue?.count ?? -1))
            }
            collect()
        }
        func randomKey() {
            let k = keys[Int.random(in: 0..<keys.count, using: &rng)]
            if held.contains(k) {
                if rng.p(0.2) { key(k, down: true, rep: true) } else { held.remove(k); key(k, down: false) }
            } else { held.insert(k); key(k, down: true) }
        }
        func chaos() {
            if rng.p(0.004) {
                disturb.append(now)
                if rng.p(0.3) { loss = [0, 0]; dup = 0; reorder = 0 } else {
                    loss = [rng.p(0.3) ? 0 : rng.d(0, 0.4), rng.p(0.3) ? 0 : rng.d(0, 0.4)]
                    dup = rng.d(0, 0.2); reorder = rng.d(0, 0.3)
                }
                ev("net loss \(loss) dup \(dup) reorder \(reorder)")
            }
            if rng.p(0.001) {
                let len = rng.d(0.5, 5), dir = Int.random(in: 0...2, using: &rng)
                if dir != 1 { outageUntil[0] = now + len }; if dir != 0 { outageUntil[1] = now + len }
                disturb.append(now); ev("outage dir \(dir) for \(len)")
            }
            if rng.p(0.0008) {
                let b = rng.p(0.5); c(b).disconnect(); needsConnect[b ? 1 : 0] = true
                disturb.append(now); ev("\(b ? "backup" : "main") disconnect"); collect()
            }
            for side in 0...1 where needsConnect[side] && rng.p(0.003) {
                needsConnect[side] = false; c(side == 1).connect(to: peerID(side == 1))
                ev("\(side == 1 ? "backup" : "main") connect"); collect()
            }
            if rng.p(0.0006) { restart(backupSide: rng.p(0.5)) }
        }
        func restart(backupSide b: Bool) {
            let clean = rng.p(0.5); disturb.append(now)
            if clean { c(b).prepareForQuit(); collect() }
            // A crashed app's virtual MIDI port goes away with its notes: not the new instance's to end.
            else if b { backupMIDI.sent.append([0xFF, 0, 0]) }
            if b { backup = make(backupSide: true) } else { main = make(backupSide: false); held.removeAll() }
            ev("\(b ? "backup" : "main") restart clean=\(clean)")
            if clean || rng.p(0.5) { c(b).connect(to: peerID(b)); needsConnect[b ? 1 : 0] = false; collect() }
        }
        func run(_ seconds: Double, chaotic: Bool) {
            let end = now + seconds
            while now < end - 1e-9 {
                now += 0.005
                deliver()
                let up = main.snapshot().link == .connected(peer: backupID.uuidString) && backup.snapshot().link == .connected(peer: mainID.uuidString)
                stableSince = up ? (stableSince ?? now) : nil
                if now >= nextTick[0] { main.tick(); collect(); nextTick[0] = now + rng.d(0.05, 0.1) }
                if now >= nextTick[1] { backup.tick(); collect(); nextTick[1] = now + rng.d(0.05, 0.1) }
                if chaotic { chaos(); if rng.p(0.025) { randomKey() } }
            }
        }
        func simulate(seconds: Double) {
            main = make(backupSide: false); backup = make(backupSide: true)
            main.connect(to: backupID.uuidString); collect()
            run(seconds, chaotic: true)
            // Heal: clean network, release keys, reconnect what was manually disconnected.
            loss = [0, 0]; dup = 0; reorder = 0; outageUntil = [0, 0]; disturb.append(now); ev("heal")
            for k in held.sorted() { key(k, down: false) }; held.removeAll()
            for side in 0...1 where needsConnect[side] { needsConnect[side] = false; c(side == 1).connect(to: peerID(side == 1)); collect() }
            // The app does not reconnect on launch: if both ended up idle, the person presses Connect.
            if main.snapshot().link == .idle, backup.snapshot().link == .idle { main.connect(to: backupID.uuidString); collect() }
            run(12, chaotic: false)
            // 1: nothing left sounding on the backup.
            var on = Set<UInt8>()
            for m in backupMIDI.sent {
                if m[0] == 0xFF || (m[0] & 0xF0 == 0xB0 && m[1] == 123) { on.removeAll() } else if m[0] == 0x90, m[2] > 0 { on.insert(m[1]) } else if m[0] & 0xF0 == 0x80 || m[0] & 0xF0 == 0x90 { on.remove(m[1]) }
            }
            if !on.isEmpty { fail("stuck notes on backup \(on.sorted()) (autoOff \(autoOff))") }
            if sentCues().contains(where: { $0.d == .waiting }) { fail("cue still waiting after settle") }
            // 3b: presses on a clean, stable link are played once and confirmed.
            for (i, p) in presses.enumerated() where p.clean && !disturb.contains(where: { $0 >= p.t - 0.01 && $0 <= p.t + 0.5 }) {
                if p.played != 1 || !p.delivered { fail("clean press \(i) at \(p.t): played \(p.played) delivered \(p.delivered)") }
            }
            // 4: linked again, and counts agree after one more press.
            if main.snapshot().link != .connected(peer: backupID.uuidString) || backup.snapshot().link != .connected(peer: mainID.uuidString) {
                return fail("not linked after settle: main \(main.snapshot().link) backup \(backup.snapshot().link)")
            }
            key(KeyNames.down, down: true); run(0.1, chaotic: false); key(KeyNames.down, down: false); run(1, chaotic: false)
            let m = main.snapshot().lastCue, b = backup.snapshot().lastCue
            // Since 1.0.2 the backup shows the main's count, so the numbers are equal.
            let start = presses.lastIndex(where: { $0.count == 1 && $0.session == mainSession }) ?? 0
            let lost = presses[start...].filter { $0.played == 0 }.count
            if m?.count != b?.count || b?.delivery != .received {
                fail("counts differ (lost in epoch \(lost)): main \(String(describing: m)) backup \(String(describing: b))") }
            if case .delivered = m?.delivery {} else { fail("final press not delivered: \(String(describing: m?.delivery))") }
        }
    }

    func testZDebug() {
        let sim = Sim(seed: 1); sim.backup = nil
        sim.main = sim.make(backupSide: false); sim.backup = sim.make(backupSide: true)
        sim.backup.log = { print("B", sim.now, $0) }; sim.main.log = { print("M", sim.now, $0) }
        sim.main.connect(to: sim.backupID.uuidString); sim.collect(); sim.run(2, chaotic: false)
        sim.key(KeyNames.down, down: true); sim.run(0.1, chaotic: false); sim.key(KeyNames.down, down: false); sim.run(1, chaotic: false)
        print(sim.main.snapshot().lastCue as Any, sim.backup.snapshot().lastCue as Any, sim.backupMIDI.sent)
    }
    func testRandomizedTwoMacs() {
        let seeds = Int(ProcessInfo.processInfo.environment["STRESS_SEEDS"] ?? "500")!
        let first = UInt64(ProcessInfo.processInfo.environment["STRESS_FIRST"] ?? "1")!
        var failed = 0
        for seed in first..<(first + UInt64(seeds)) {
            let sim = Sim(seed: seed)
            sim.simulate(seconds: Double(3 + seed % 6))
            guard !sim.failures.isEmpty else { continue }
            failed += 1
            if failed <= 50 || ProcessInfo.processInfo.environment["STRESS_VERBOSE"] != nil {
                print("SEED \(seed) FAIL:\n  " + sim.failures.prefix(4).joined(separator: "\n  "))
                if ProcessInfo.processInfo.environment["STRESS_VERBOSE"] != nil { print("  events:\n    " + sim.events.joined(separator: "\n    ")) }
            }
        }
        XCTAssertEqual(failed, 0, "\(failed) of \(seeds) seeds failed")
    }
}
