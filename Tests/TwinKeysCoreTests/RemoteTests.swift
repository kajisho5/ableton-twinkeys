import Crypto
import XCTest
@testable import TwinKeysCore

final class RemoteTests: XCTestCase {
    let secret = PairingSecret(keyBytes: Array(repeating: 9, count: 32))

    func handshake(server: RemoteSession, client: RemoteSession) throws -> (String, String) {
        let ch = client.clientHello(deviceID: "dev-1", deviceName: "Stage iPhone")
        guard case let .clientHello(hello, serverCode)? = try server.receive(ch).first else { XCTFail("no hello"); return ("", "") }
        XCTAssertEqual(hello.deviceName, "Stage iPhone")
        let sh = try server.serverHello(serverID: "mac-1", serverName: "Main Stage Mac")
        guard case let .serverHello(_, clientCode)? = try client.receive(sh).first else { XCTFail("no server hello"); return ("", "") }
        return (serverCode, clientCode)
    }

    func testHandshakeAndMessagesBothWays() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: key)
        let (a, b) = try handshake(server: server, client: client)
        XCTAssertEqual(a, b, "both show the same confirm code")
        XCTAssertEqual(a.count, 4)
        let m = RemoteMessage.command(id: 1, .fireScene(4))
        XCTAssertEqual(try server.receive(client.seal(m)), [.message(m)])
        let r = RemoteMessage.result(id: 1, ok: true, error: nil, backup: "delivered")
        XCTAssertEqual(try client.receive(server.seal(r)), [.message(r)])
        // Split and joined frames still decode.
        let two = try client.seal(.ping(1)) + client.seal(.ping(2))
        var got: [RemoteSession.Event] = []
        for byte in two { got += try server.receive([byte]) }
        XCTAssertEqual(got, [.message(.ping(1)), .message(.ping(2))])
    }

    func testWrongPairingCodeIsRefused() throws {
        let server = RemoteSession(serverWith: secret)
        let client = RemoteSession(clientWith: PairingSecret(keyBytes: Array(repeating: 1, count: 32)), deviceKey: .init())
        XCTAssertThrowsError(try server.receive(client.clientHello(deviceID: "x", deviceName: "x"))) {
            XCTAssertEqual($0 as? RemoteError, .wrongPairingCode)
        }
    }

    func testReplayedOrForgedFramesAreRefused() throws {
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = try handshake(server: server, client: client)
        let f = try client.seal(.command(id: 1, .stopAll))
        _ = try server.receive(f)
        XCTAssertThrowsError(try server.receive(f)) { XCTAssertEqual($0 as? RemoteError, .outOfOrder) }
        var g = try client.seal(.command(id: 2, .play)); g[g.count - 1] ^= 1
        XCTAssertThrowsError(try server.receive(g)) { XCTAssertEqual($0 as? RemoteError, .decryptFailed) }
    }

    func testAnotherDeviceKeyCannotUseTheChannel() throws {
        // Someone copies a real client hello (same id and public key) but has another private key.
        let real = Curve25519.KeyAgreement.PrivateKey()
        let server = RemoteSession(serverWith: secret)
        let copied = RemoteSession(clientWith: secret, deviceKey: real).clientHello(deviceID: "dev-1", deviceName: "x")
        _ = try server.receive(copied)
        let sh = try server.serverHello(serverID: "m", serverName: "m")
        let thief = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = thief.clientHello(deviceID: "dev-1", deviceName: "x")
        // The thief's session does not even accept the server hello (it is bound to the real hello).
        XCTAssertThrowsError(try thief.receive(sh))
    }

    func testApprovalNeedsSameIDAndKey() throws {
        let k = Curve25519.KeyAgreement.PrivateKey()
        let h = RemoteClientHello(version: 1, deviceID: "a", deviceName: "n", devicePublicKey: k.publicKey.rawRepresentation, nonce: Data(count: 16))
        let ok = [ApprovedDevice(id: "a", name: "n", publicKey: k.publicKey.rawRepresentation)]
        XCTAssertTrue(ApprovedDevice.isApproved(h, in: ok))
        XCTAssertFalse(ApprovedDevice.isApproved(h, in: [ApprovedDevice(id: "a", name: "n", publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)]))
        XCTAssertFalse(ApprovedDevice.isApproved(h, in: [ApprovedDevice(id: "b", name: "n", publicKey: k.publicKey.rawRepresentation)]))
    }

    func testLiveCommandsRoundTripAndValidate() {
        let all: [LiveCommand] = [.fireScene(3), .fireClip(track: 2, scene: 7), .stopTrack(1), .stopAll, .play, .stop, .continuePlaying,
                                  .setTempo(124.5), .setVolume(track: -1, value: 0.85), .setPan(track: 3, value: -0.5),
                                  .setMute(track: 2, on: true), .setSolo(track: 0, on: false), .selectScene(9)]
        for c in all {
            XCTAssertEqual(LiveCommand.decode(c.encoded()), c)
            let p = Packet(session: 1, seq: 2, body: .liveCommand(id: 5, c))
            XCTAssertEqual(try Packet.decode(p.encode()), p)
            XCTAssertLessThanOrEqual(p.encode().count + SecureChannel.tagSize, WireProtocol.maxPacketSize)
        }
        XCTAssertFalse(LiveCommand.setTempo(5000).isValid)
        XCTAssertFalse(LiveCommand.setVolume(track: 0, value: .nan).isValid)
        XCTAssertNil(LiveCommand.decode([9, 0, 1] + Array(repeating: 0xFF, count: 8)))  // NaN volume
        XCTAssertFalse(LiveCommand.setVolume(track: 1, value: 0.5).allowedWhileLocked)
        XCTAssertTrue(LiveCommand.fireScene(1).allowedWhileLocked)
    }

    func testBridgeMessagesBuildTheState() {
        var s = LiveState()
        s.apply(bridge: ["type": "song", "tempo": 124.0, "playing": true, "beat": "17.3.1", "selected_scene": 2, "tracks": 2, "scenes": 3])
        s.apply(bridge: ["type": "scenes", "start": 0, "items": [["index": 0, "name": "Intro", "color": "#FF0000"], ["index": 2, "name": "M1", "playing": true]]])
        s.apply(bridge: ["type": "tracks", "start": 0, "master": ["volume": 0.8], "items": [["index": 1, "name": "SE", "volume": 0.6, "mute": true]]])
        s.apply(bridge: ["type": "clips", "track": 1, "items": [["scene": 2, "has_clip": true, "name": "Applause", "is_playing": true, "length_beats": 16.0]]])
        s.apply(bridge: ["type": "progress", "items": [[1, 10.0, 16.0]]])
        XCTAssertEqual(s.song.tempo, 124); XCTAssertTrue(s.song.playing); XCTAssertEqual(s.song.beat, "17.3.1")
        XCTAssertEqual(s.scenes.map(\.name), ["Intro", "", "M1"])
        XCTAssertEqual(s.tracks.count, 2); XCTAssertTrue(s.tracks[1].mute); XCTAssertEqual(s.master.volume, 0.8)
        XCTAssertEqual(s.clips[1][2].name, "Applause"); XCTAssertFalse(s.clips[1][0].hasClip)
        XCTAssertEqual(s.secondsLeft(track: 1)!, 6 * 60 / 124, accuracy: 0.001)
        XCTAssertEqual(formatTimeLeft(42.2), "-0:43")
        XCTAssertNil(s.apply(bridge: ["type": "bogus"]))
        XCTAssertNil(s.apply(bridge: ["type": "clips", "track": -5, "items": []]))
        // The iPhone side applies the same updates and ends up equal.
        var phone = LiveState()
        phone.apply(.full(s))
        XCTAssertEqual(phone, s)
    }
}

/// Live commands forwarded from the main Mac to the backup.
extension CueTests {
    func testLiveCommandRunsOnceOnTheBackupEvenIfResent() throws {
        let t = self
        var ran: [LiveCommand] = []
        t.backup.onLiveCommand = { ran.append($0) }
        t.connect(); t.tick(1.1)
        var dropping = true
        t.dropFromBackup = []
        t.backupToMainUp = true
        // Lose the backup's answer once so the main resends.
        t.dropFromBackupFn = { b in if dropping && b[3] == 0x19 { dropping = false; return true }; return false }
        let id = try XCTUnwrap(t.main.forwardLive(.fireScene(4)))
        t.pump(); t.tick(0.4)
        XCTAssertEqual(ran, [.fireScene(4)])
        XCTAssertEqual(t.main.liveDelivery(id), "delivered")
    }

    func testLiveCommandWithoutAnswerIsMissing() throws {
        let t = self
        t.backup.onLiveCommand = { _ in }
        t.connect(); t.tick(1.1)
        t.mainToBackupUp = false
        let id = try XCTUnwrap(t.main.forwardLive(.stopAll))
        t.tick(0.4)
        XCTAssertEqual(t.main.liveDelivery(id), "missing")
    }

    func testLiveCommandNotLinkedReturnsNil() {
        let t = self
        XCTAssertNil(t.main.forwardLive(.play))
    }

    func testCueButtonFromThePhone() {
        let t = self
        t.connect()
        t.main.setKeyCapture(false)       // works without key capture
        XCTAssertTrue(t.main.pressCue(keycode: KeyNames.down)); t.pump()
        XCTAssertEqual(t.backupMIDI.sent.filter { $0 == [0x90, 37, 127] }.count, 1)
        XCTAssertFalse(t.main.pressCue(keycode: 0x00), "not a cue key")
    }
}
