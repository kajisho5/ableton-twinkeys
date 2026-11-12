import Crypto
import XCTest
@testable import TwinKeysCore

final class RemoteApprovalTests: XCTestCase {
    let secret = PairingSecret(keyBytes: Array(repeating: 9, count: 32))

    func testLockMessageRoundTrips() throws {
        for m: RemoteMessage in [.lock(true), .lock(false)] {
            let back = try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(m))
            XCTAssertEqual(back, m)
        }
        // Through the sealed channel too.
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        _ = try server.receive(client.clientHello(deviceID: "d", deviceName: "n"))
        _ = try client.receive(server.serverHello(serverID: "m", serverName: "m"))
        XCTAssertEqual(try server.receive(client.seal(.lock(true))), [.message(.lock(true))])
    }

    func testDeviceNamesAreSanitised() {
        XCTAssertEqual(RemoteClientHello.sanitizedName("Stage iPhone"), "Stage iPhone")
        XCTAssertEqual(RemoteClientHello.sanitizedName("Stage\niPhone\u{0007}"), "StageiPhone")
        XCTAssertEqual(RemoteClientHello.sanitizedName("abc\u{202E}lmth.exe"), "abclmth.exe", "no right-to-left override")
        XCTAssertEqual(RemoteClientHello.sanitizedName("  \u{0000}\t "), "iPhone")
        XCTAssertEqual(RemoteClientHello.sanitizedName("ステージの iPhone"), "ステージの iPhone")
        XCTAssertEqual(RemoteClientHello.sanitizedName("👨‍👩‍👧 phone"), "👨‍👩‍👧 phone", "emoji sequences stay")
        XCTAssertEqual(RemoteClientHello.sanitizedName(String(repeating: "x", count: 500)).count, 64)
    }

    func testServerSanitisesTheHelloName() throws {
        let server = RemoteSession(serverWith: secret), client = RemoteSession(clientWith: secret, deviceKey: .init())
        guard case let .clientHello(hello, _)? = try server.receive(client.clientHello(deviceID: "d", deviceName: "Evil\n\nAllow it\u{202E}")).first
        else { return XCTFail("no hello") }
        XCTAssertEqual(hello.deviceName, "EvilAllow it")
        XCTAssertEqual(server.peerHello?.deviceName, "EvilAllow it")
    }

    func testOneQuestionAtATime() {
        var g = RemoteApprovalGate()
        guard case let .ask(t1) = g.request(deviceID: "a", now: 0) else { return XCTFail() }
        XCTAssertEqual(g.request(deviceID: "b", now: 1), .busy)
        XCTAssertEqual(g.request(deviceID: "a", now: 1), .busy)
        XCTAssertTrue(g.finish(token: t1, allowed: true, now: 2))
        XCTAssertFalse(g.finish(token: t1, allowed: false, now: 2), "a second answer is ignored")
        guard case let .ask(t2) = g.request(deviceID: "b", now: 3) else { return XCTFail() }
        XCTAssertNotEqual(t1, t2)
        XCTAssertFalse(g.finish(token: t1, allowed: true, now: 4), "an old answer never applies to a newer question")
        XCTAssertEqual(g.openToken, t2)
    }

    func testRefusedDeviceWaitsBeforeAskingAgain() {
        var g = RemoteApprovalGate()
        guard case let .ask(t) = g.request(deviceID: "a", now: 0) else { return XCTFail() }
        g.finish(token: t, allowed: false, now: 5)
        XCTAssertEqual(g.request(deviceID: "a", now: 30), .coolingDown)
        guard case let .ask(tb) = g.request(deviceID: "b", now: 30) else { return XCTFail("other devices can still ask") }
        g.finish(token: tb, allowed: true, now: 31)
        XCTAssertEqual(g.request(deviceID: "b", now: 32).isAsk, true, "allowed devices get no pause")
    }

    func testQuestionTimesOut() {
        var g = RemoteApprovalGate()
        guard case let .ask(t) = g.request(deviceID: "a", now: 0) else { return XCTFail() }
        XCTAssertFalse(g.isExpired(token: t, now: 59))
        XCTAssertTrue(g.isExpired(token: t, now: 60))
        // A missed timer: the next request closes the old question and the old device pauses.
        guard case .ask = g.request(deviceID: "b", now: 61) else { return XCTFail() }
        XCTAssertFalse(g.finish(token: t, allowed: true, now: 61))
        XCTAssertEqual(g.request(deviceID: "c", now: 100), .busy)
        g.finish(token: g.openToken!, allowed: true, now: 100)
        XCTAssertEqual(g.request(deviceID: "a", now: 100), .coolingDown)
        XCTAssertTrue(g.request(deviceID: "a", now: 122).isAsk)
    }
}

private extension RemoteApprovalGate.Decision {
    var isAsk: Bool { if case .ask = self { return true } else { return false } }
}
