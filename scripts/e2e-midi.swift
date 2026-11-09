// End-to-end check of the receiving side, run on a macOS CI runner while TwinKeys is running:
//  1. The CoreMIDI source "TwinKeys" exists (what a DAW sees as a MIDI input).
//  2. A fake second Mac (this script) advertises itself with Bonjour, says hello to TwinKeys
//     over UDP and sends note-on / note-off packets.
//  3. The same notes come out of the "TwinKeys" MIDI source.
// Usage: swift scripts/e2e-midi.swift   (exit code 0 = pass)
import CoreMIDI
import Foundation
import Network

func fail(_ msg: String) -> Never { print("FAIL: \(msg)"); exit(1) }
// Never hang the CI job.
DispatchQueue.global().asyncAfter(deadline: .now() + 60) { fail("timeout after 60 s") }
func step(_ msg: String) { print("== \(msg)") }

// MARK: 1. Find the TwinKeys MIDI source

func sourceNames() -> [(MIDIEndpointRef, String)] {
    (0..<MIDIGetNumberOfSources()).compactMap { i in
        let src = MIDIGetSource(i)
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == noErr, let n = name else { return nil }
        return (src, n.takeRetainedValue() as String)
    }
}

var client = MIDIClientRef()
guard MIDIClientCreateWithBlock("e2e" as CFString, &client, nil) == noErr else { fail("MIDIClientCreate") }

var twinKeys: MIDIEndpointRef?
for _ in 0..<40 {
    let matches = sourceNames().filter { $0.1 == "TwinKeys" }
    if matches.count > 1 { fail("more than one MIDI source named TwinKeys (another instance still running?)") }
    if let s = matches.first { twinKeys = s.0; break }
    Thread.sleep(forTimeInterval: 0.25)
}
step("MIDI sources: \(sourceNames().map(\.1))")
guard let source = twinKeys else { fail("no MIDI source named TwinKeys") }
print("PASS: MIDI source \"TwinKeys\" exists")

let received = NSMutableArray()
var inPort = MIDIPortRef()
let status = MIDIInputPortCreateWithProtocol(client, "e2e-in" as CFString, ._1_0, &inPort) { list, _ in
    for packet in list.unsafeSequence() {
        let count = Int(packet.pointee.wordCount)
        let words = withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self).prefix(count)) }
        for w in words where (w >> 28) == 0x2 {       // MIDI 1.0 channel voice message
            let bytes = [UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF)]
            DispatchQueue.main.async { received.add(bytes) }
        }
    }
}
guard status == noErr else { fail("MIDIInputPortCreate \(status)") }
guard MIDIPortConnectSource(inPort, source, nil) == noErr else { fail("MIDIPortConnectSource") }

// MARK: 2. Pretend to be another Mac

let myID = UUID()
let session = UInt32.random(in: 1...UInt32.max)
var seq: UInt32 = 0
func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
func packet(_ type: UInt8, _ payload: [UInt8]) -> Data {
    seq += 1
    return Data([0x54, 0x4B, 1, type] + be32(session) + be32(seq) + payload)
}
let u = myID.uuid
let idBytes: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
let name = Array("CI Test Mac".utf8)
let hello = { packet(0x01, idBytes + [UInt8(name.count)] + name) }

let queue = DispatchQueue(label: "e2e")
// Advertise ourselves: TwinKeys only accepts hellos from Macs it can see on Bonjour.
let listener = try! NWListener(using: .udp)
var txt = NWTXTRecord()
txt["id"] = myID.uuidString; txt["v"] = "1"; txt["modes"] = "s"; txt["boot"] = UUID().uuidString
listener.service = NWListener.Service(name: "CI Test Mac", type: "_twinkeys._udp", domain: nil, txtRecord: txt)
listener.newConnectionHandler = { $0.start(queue: queue) }
listener.start(queue: queue)

// Find TwinKeys on Bonjour.
let found = DispatchSemaphore(value: 0)
let targetLock = NSLock()
var target: NWEndpoint?
let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_twinkeys._udp", domain: nil), using: NWParameters())
browser.stateUpdateHandler = { print("   browser state: \($0)") }
listener.stateUpdateHandler = { print("   listener state: \($0)") }
browser.browseResultsChangedHandler = { results, _ in
    print("   browse results: \(results.map { "\($0.endpoint)" })")
    for r in results {
        if case let .bonjour(t) = r.metadata, t.dictionary["id"] != myID.uuidString {
            targetLock.lock()
            if target == nil { target = r.endpoint; found.signal() }
            targetLock.unlock()
        }
    }
}
browser.start(queue: queue)
step("browsing for TwinKeys…")
guard found.wait(timeout: .now() + 20) == .success else { fail("TwinKeys not found on Bonjour") }
targetLock.lock(); let endpoint = target!; targetLock.unlock()
print("PASS: TwinKeys found on Bonjour: \(endpoint)")

let conn = NWConnection(to: endpoint, using: .udp)
let acked = DispatchSemaphore(value: 0)
func receiveLoop() {
    conn.receiveMessage { data, _, _, error in
        if let d = data, d.count >= 4, d[3] == 0x02 { acked.signal() }   // HelloAck
        if error == nil { receiveLoop() }
    }
}
conn.start(queue: queue)
receiveLoop()

// TwinKeys may need a moment to see our Bonjour record: keep saying hello until it answers.
var linked = false
for _ in 0..<20 {
    conn.send(content: hello(), completion: .idempotent)
    if acked.wait(timeout: .now() + 1) == .success { linked = true; break }
}
guard linked else { fail("no HelloAck from TwinKeys") }
print("PASS: linked (HelloAck received)")

// MARK: 3. Send notes and expect them on the TwinKeys MIDI source
// UDP may drop a packet: resend each step until its result shows up on the MIDI source.

func got() -> [[UInt8]] {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    return received.compactMap { $0 as? [UInt8] }
}
func sendUntil(_ data: () -> Data, _ expected: [UInt8], _ what: String) {
    for _ in 0..<15 {
        conn.send(content: data(), completion: .idempotent)
        for _ in 0..<3 { if got().contains(expected) { return } }
    }
    fail("\(what) did not come out of the TwinKeys source; got \(got())")
}
sendUntil({ packet(0x10, [0, 60, 100]) }, [0x90, 60, 100], "note on")
sendUntil({ packet(0x11, [0, 60]) }, [0x80, 60, 0], "note off")
conn.send(content: packet(0x03, []), completion: .idempotent)              // bye
print("Received from TwinKeys port: \(got())")
print("PASS: note on/off from the network came out of the TwinKeys MIDI source")
exit(0)
