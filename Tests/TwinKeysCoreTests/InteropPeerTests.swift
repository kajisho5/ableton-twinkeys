#if canImport(Darwin)
import Darwin
#endif
import Foundation
import XCTest
@testable import TwinKeysCore

/// Links this Mac code (the Swift Conductor) with the Windows version's C# core over real UDP on
/// 127.0.0.1 (docs/design-windows.md 6.6). The C# side is windows/src/TwinKeys.PeerCli started with
/// `--script interop`; the macOS CI job "interop" in .github/workflows/windows.yml runs both.
///
/// Runs only when TWINKEYS_INTEROP_PEER=host:port is set; otherwise it is skipped, so a plain
/// `swift test` is unchanged. Test-only: nothing here is used by the app.
///
/// The flow: Swift says hello, the C# peer answers; Swift presses ↓ (note 37) and waits until the
/// C# side confirms it; the C# side then presses ↑ (note 36), which must come out of this side's
/// MIDI with its name and the shared count (2); Swift disconnects (the peer sees the goodbye).
final class InteropPeerTests: XCTestCase {
    #if canImport(Darwin)
    final class Recorder: MIDIOutput {
        private let lock = NSLock()
        private var sent: [[UInt8]] = []
        func send(_ bytes: [UInt8]) {
            lock.lock(); sent.append(bytes); lock.unlock()
        }
        func contains(_ m: [UInt8]) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return sent.contains(m)
        }
    }

    /// A plain IPv4 UDP socket that sends every packet to one address (the C# peer).
    final class UDPSink: PacketSink {
        let fd: Int32
        private var dest = sockaddr_in()

        init?(host: String, port: UInt16) {
            let socketFD = socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP))
            fd = socketFD
            guard socketFD >= 0 else { return nil }
            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            local.sin_family = sa_family_t(AF_INET)
            local.sin_port = 0
            local.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &local) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = port.bigEndian
            guard bound == 0, inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return nil }   // deinit closes the socket
            var tv = timeval(tv_sec: 0, tv_usec: 100_000)
            _ = setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        deinit { close(fd) }

        func send(_ bytes: [UInt8], to peer: String) {
            var d = dest
            let socketFD = fd
            _ = bytes.withUnsafeBytes { buf in
                withUnsafePointer(to: &d) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(socketFD, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        func resetRoute(to peer: String) {}

        /// One datagram, or nil after the 0.1 s receive timeout.
        func receive() -> [UInt8]? {
            var buf = [UInt8](repeating: 0, count: 2048)
            let socketFD = fd
            let n = buf.withUnsafeMutableBytes { recv(socketFD, $0.baseAddress, $0.count, 0) }
            return n > 0 ? Array(buf[0..<n]) : nil
        }
    }

    /// Shared between the test and its two helper threads.
    final class Flags {
        private let lock = NSLock()
        private var _stop = false
        private var _bound: String?
        var stop: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _stop }
            set { lock.lock(); _stop = newValue; lock.unlock() }
        }
        var bound: String? {
            get { lock.lock(); defer { lock.unlock() }; return _bound }
            set { lock.lock(); _bound = newValue; lock.unlock() }
        }
    }
    #endif

    func testLinkWithTheWindowsCore() throws {
        #if canImport(Darwin)
        guard let target = ProcessInfo.processInfo.environment["TWINKEYS_INTEROP_PEER"] else {
            throw XCTSkip("Set TWINKEYS_INTEROP_PEER=127.0.0.1:47901 while windows/src/TwinKeys.PeerCli runs with --script interop")
        }
        let parts = target.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]) else { return XCTFail("TWINKEYS_INTEROP_PEER must be host:port") }
        let sink = try XCTUnwrap(UDPSink(host: String(parts[0]), port: port), "UDP socket")
        let midi = Recorder()
        let start = Date()
        var settings = AppSettings()
        settings.sendKeys = true
        settings.receiveNotes = true
        let conductor = Conductor(instanceID: UUID(), displayName: "CI Mac (Swift)", settings: settings, midi: midi, net: sink,
                                  clock: { Date().timeIntervalSince(start) },
                                  nanos: { UInt64(Date().timeIntervalSince(start) * 1e9) })
        conductor.log = { print("swift: \($0)") }
        conductor.setPairing(PairingSecret(code: "K7MQ2-WX9TP"))

        let placeholder = PeerInfo.manualPrefix + target
        let flags = Flags()
        let receiver = Thread {
            while !flags.stop {
                guard let data = sink.receive() else { continue }
                if let peer = conductor.receive(data, knownPeer: flags.bound ?? placeholder) { flags.bound = peer }
            }
        }
        let ticker = Thread {
            while !flags.stop {
                conductor.tick()
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        receiver.start()
        ticker.start()
        defer { flags.stop = true; Thread.sleep(forTimeInterval: 0.3) }

        func waitUntil(_ seconds: Double, _ what: String, _ ok: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if ok() { print("PASS: \(what)"); return true }
                Thread.sleep(forTimeInterval: 0.02)
            }
            XCTFail("timed out: \(what); state: \(conductor.snapshot())")
            return false
        }

        conductor.connect(to: placeholder)
        guard waitUntil(15, "linked with the C# peer", {
            if case .connected = conductor.snapshot().link { return true }
            return false
        }) else { return }

        conductor.handleKey(KeyInput(keycode: KeyNames.down, isDown: true))
        Thread.sleep(forTimeInterval: 0.03)
        conductor.handleKey(KeyInput(keycode: KeyNames.down, isDown: false))
        guard waitUntil(5, "the C# peer confirmed the cue ↓", {
            if case .delivered? = conductor.snapshot().lastCue?.delivery { return true }
            return false
        }) else { return }

        guard waitUntil(15, "the C# peer's cue ↑ (note 36) played here with its name and the shared count", {
            guard midi.contains([0x90, 36, 127]), let cue = conductor.snapshot().lastCue else { return false }
            return cue.delivery == .received && cue.label == "↑" && cue.count == 2
        }) else { return }

        Thread.sleep(forTimeInterval: 0.5)
        conductor.disconnect()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(conductor.snapshot().link, .idle)
        #else
        throw XCTSkip("macOS only (BSD sockets)")
        #endif
    }
}
