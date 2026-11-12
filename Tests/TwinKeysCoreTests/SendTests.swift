import Foundation
import XCTest
@testable import TwinKeysCore

/// Mixer sends (Send A and Send B): the command, the Bridge state and the backup catch-up.
final class SendTests: XCTestCase {
    func testSendCommandRoundTripsAndValidates() throws {
        let c = LiveCommand.setSend(track: 4, send: 1, value: 0.25)
        XCTAssertEqual(c.encoded(), [14, 0, 4, 1] + withUnsafeBytes(of: 0.25.bitPattern.bigEndian) { Array($0) })
        for c in [c, .setSend(track: 0, send: 0, value: 0), .setSend(track: 9999, send: 1, value: 1)] {
            XCTAssertTrue(c.isValid)
            XCTAssertEqual(LiveCommand.decode(c.encoded()), c)
            let p = Packet(session: 1, seq: 2, body: .liveCommand(id: 5, c))
            XCTAssertEqual(try Packet.decode(p.encode()), p)
            XCTAssertLessThanOrEqual(p.encode().count + SecureChannel.tagSize, WireProtocol.maxPacketSize)
        }
        // Only Send A / Send B, never the master, values 0...1.
        for bad: LiveCommand in [.setSend(track: 0, send: 2, value: 0.5), .setSend(track: 0, send: -1, value: 0.5),
                                 .setSend(track: -1, send: 0, value: 0.5), .setSend(track: 0, send: 0, value: 1.01),
                                 .setSend(track: 0, send: 0, value: -0.01), .setSend(track: 0, send: 0, value: .nan),
                                 .setSend(track: 0, send: 0, value: .infinity)] {
            XCTAssertFalse(bad.isValid, "\(bad)")
            XCTAssertNil(LiveCommand.decode(bad.encoded()), "\(bad)")
        }
        XCTAssertNil(LiveCommand.decode([14, 0, 4, 1, 0, 0]))   // cut short
        XCTAssertNil(LiveCommand.decode([14, 0, 4]))
        XCTAssertTrue(c.isContinuous)
        XCTAssertFalse(c.allowedWhileLocked)
    }

    func testSendCommandForTheBridgeAndTheIPhoneLink() throws {
        let json = LiveCommand.setSend(track: 3, send: 1, value: 0.5).bridgeJSON(id: 7, structure: 42)
        XCTAssertEqual(json["cmd"] as? String, "set_send")
        XCTAssertEqual(json["id"] as? Int, 7)
        XCTAssertEqual(json["track"] as? Int, 3)
        XCTAssertEqual(json["send"] as? Int, 1)
        XCTAssertEqual(json["value"] as? Double, 0.5)
        XCTAssertEqual(json["structure"] as? Int, 42)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: json))
        let m = RemoteMessage.command(id: 3, .setSend(track: 2, send: 0, value: 0.75))
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(m)), m)
    }

    func testBridgeTracksCarrySends() {
        var s = LiveState()
        let u = s.apply(bridge: ["type": "tracks", "start": 0, "items": [
            ["index": 0, "name": "Music", "sends": [0.25, 0.5]],
            ["index": 1, "name": "One return", "sends": [0.3]],
            ["index": 2, "name": "No returns", "sends": [Double]()],
            ["index": 3, "name": "Older script"],
            ["index": 4, "name": "Odd", "sends": [0.1, 0.2, 0.3]],
            ["index": 5, "name": "Bad", "sends": [NSNull(), 0.4] as [Any]],
            ["index": 6, "name": "Out of range", "sends": [1.5, -0.5]],
        ] as [[String: Any]]])
        XCTAssertEqual(s.tracks.map(\.sends), [[0.25, 0.5], [0.3], [], [], [0.1, 0.2], [], [1, 0]])
        guard case let .tracks(list, _)? = u else { return XCTFail("no tracks update") }
        XCTAssertEqual(list.map(\.sends), s.tracks.map(\.sends))
        var phone = LiveState()
        phone.apply(u!)
        XCTAssertEqual(phone.tracks, s.tracks)
    }

    func testTrackWithoutSendsStillDecodes() throws {
        let t = LiveTrack(index: 2, name: "SE", volume: 0.7, mute: true, playingSlot: 3, sends: [0.4, 0.1])
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(LiveTrack.self, from: data), t)
        // A Mac from before sends sends no "sends" key: the track decodes, with no sends.
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(old.removeValue(forKey: "sends"))
        let back = try JSONDecoder().decode(LiveTrack.self, from: JSONSerialization.data(withJSONObject: old))
        var want = t
        want.sends = []
        XCTAssertEqual(back, want)
        // Other fields are still required.
        old.removeValue(forKey: "name")
        XCTAssertThrowsError(try JSONDecoder().decode(LiveTrack.self, from: JSONSerialization.data(withJSONObject: old)))
        // The whole update an iPhone receives.
        let u = LiveUpdate.tracks([t], LiveState.MasterStrip())
        XCTAssertEqual(try JSONDecoder().decode(LiveUpdate.self, from: JSONEncoder().encode(u)), u)
    }

    func testSendHasItsOwnCatchUpKey() {
        let a = LiveCommand.setSend(track: 2, send: 0, value: 0.3)
        XCTAssertEqual(Conductor.latestKey(a), "send0/2")
        let others: [LiveCommand] = [.setSend(track: 2, send: 1, value: 0.3), .setSend(track: 20, send: 0, value: 0.3),
                                     .setVolume(track: 2, value: 0.3), .setPan(track: 2, value: 0.3),
                                     .setSolo(track: 2, on: true), .setMute(track: 2, on: true), .setTempo(120)]
        let keys = others.compactMap { Conductor.latestKey($0) }
        XCTAssertEqual(keys.count, others.count)
        XCTAssertFalse(keys.contains("send0/2"))
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(Conductor.latestKey(.setSend(track: 2, send: 0, value: 0.9)), "send0/2")
    }
}

/// Sends set while the backup was away reach it later; a newer value replaces one still waiting.
extension CueTests {
    func testSendChangesMadeWhileUnlinkedReachTheBackupLater() {
        let t = self
        var ran: [LiveCommand] = []
        t.backup.onLiveCommand = { ran.append($0) }
        t.connect(); t.tick(1.1)
        t.mainToBackupUp = false; t.backupToMainUp = false
        t.tick(8)
        XCTAssertNil(t.main.forwardLive(.setSend(track: 1, send: 0, value: 0.2)))
        XCTAssertNil(t.main.forwardLive(.setSend(track: 1, send: 0, value: 0.4)))   // only the newest counts
        XCTAssertNil(t.main.forwardLive(.setSend(track: 1, send: 1, value: 0.7)))   // Send B is its own control
        XCTAssertNil(t.main.forwardLive(.setVolume(track: 1, value: 0.6)))
        t.mainToBackupUp = true; t.backupToMainUp = true
        t.tick(8)
        XCTAssertEqual(Set(ran.map { "\($0)" }), Set([LiveCommand.setSend(track: 1, send: 0, value: 0.4),
                                                      .setSend(track: 1, send: 1, value: 0.7),
                                                      .setVolume(track: 1, value: 0.6)].map { "\($0)" }))
    }

    func testNewerSendValueReplacesTheOneWaiting() throws {
        let t = self
        t.connect(); t.tick(1.1)
        let first = try XCTUnwrap(t.main.forwardLive(.setSend(track: 3, send: 1, value: 0.2)))
        let second = try XCTUnwrap(t.main.forwardLive(.setSend(track: 3, send: 1, value: 0.3)))
        XCTAssertEqual(t.main.liveDelivery(first), "unknown")     // dropped: same send of the same track
        XCTAssertEqual(t.main.liveDelivery(second), "waiting")
        let otherSend = try XCTUnwrap(t.main.forwardLive(.setSend(track: 3, send: 0, value: 0.5)))
        let otherTrack = try XCTUnwrap(t.main.forwardLive(.setSend(track: 4, send: 1, value: 0.5)))
        _ = try XCTUnwrap(t.main.forwardLive(.setVolume(track: 3, value: 0.5)))
        for id in [second, otherSend, otherTrack] { XCTAssertEqual(t.main.liveDelivery(id), "waiting") }
        t.tick(1)
        for id in [second, otherSend, otherTrack] { XCTAssertEqual(t.main.liveDelivery(id), "delivered") }
    }
}
