import XCTest
@testable import TwinKeysCore

final class LinkTests: XCTestCase {
    typealias L = LinkStateMachine

    func testRetryDelayGrowsToFiveSeconds() {
        XCTAssertEqual((1...6).map { L.retryDelay(attempt: $0) }, [1, 2, 4, 5, 5, 5])
    }

    func testConnectHandshakeAndHeartbeat() {
        var l = L()
        XCTAssertEqual(l.connect(to: "B", now: 0), [.sendHello(peer: "B")])
        XCTAssertEqual(l.state, .connecting(peer: "B", attempt: 1, nextRetryAt: 1))
        _ = l.receivedHelloAck(from: "B", now: 0.01)
        XCTAssertEqual(l.state, .connected(peer: "B"))
        XCTAssertEqual(l.tick(now: 0.1), [.sendHeartbeat(peer: "B")])
        XCTAssertEqual(l.tick(now: 0.5), [])
        XCTAssertEqual(l.tick(now: 1.1), [.sendHeartbeat(peer: "B")])
        l.receivedHeartbeatAck(from: "B", rtt: 0.002, now: 1.11)
        l.receivedHeartbeatAck(from: "B", rtt: 0.010, now: 1.12)
        l.receivedHeartbeatAck(from: "B", rtt: 0.003, now: 1.13)
        XCTAssertEqual(l.latencyMs!, 3, accuracy: 0.0001)  // median
    }

    func testRetriesWithBackoffUntilAnswered() {
        var l = L()
        _ = l.connect(to: "B", now: 0)
        XCTAssertEqual(l.tick(now: 0.9), [])
        XCTAssertEqual(l.tick(now: 1.0), [.sendHello(peer: "B")])   // attempt 2, next in 2s
        XCTAssertEqual(l.tick(now: 2.9), [])
        XCTAssertEqual(l.tick(now: 3.0), [.sendHello(peer: "B")])   // attempt 3, next in 4s
        XCTAssertEqual(l.tick(now: 6.9), [])
        XCTAssertEqual(l.tick(now: 7.0), [.sendHello(peer: "B")])   // attempt 4, next in 5s
        XCTAssertEqual(l.tick(now: 12.0), [.sendHello(peer: "B")])  // capped at 5s
        XCTAssertEqual(l.tick(now: 17.0), [.sendHello(peer: "B")])
        _ = l.receivedHelloAck(from: "B", now: 17.1)
        XCTAssertTrue(l.isConnected)
    }

    func testLossAfterThreeSecondsSilenceThenReconnect() {
        var l = L()
        _ = l.connect(to: "B", now: 0)
        _ = l.receivedHelloAck(from: "B", now: 0)
        _ = l.tick(now: 0)
        _ = l.receivedHeartbeat(from: "B", timestampNanos: 1, now: 1.0)
        XCTAssertEqual(l.tick(now: 3.9), [.sendHeartbeat(peer: "B")])   // 2.9s silence: still connected
        XCTAssertTrue(l.isConnected)
        let a = l.tick(now: 4.0)                                        // 3.0s silence
        XCTAssertEqual(a, [.safety(.connectionLost, peer: "B"), .log("Lost connection to B; reconnecting"), .sendHello(peer: "B")])
        XCTAssertEqual(l.state, .connecting(peer: "B", attempt: 1, nextRetryAt: 5))
        XCTAssertNil(l.latencyMs)
        // The peer comes back by itself (it also retries): its hello reconnects us.
        XCTAssertEqual(l.receivedHello(from: "B", now: 6), [.sendHelloAck(peer: "B"), .log("Connected to B")])
        XCTAssertTrue(l.isConnected)
    }

    func testAnyPacketKeepsLinkAlive() {
        var l = L()
        _ = l.connect(to: "B", now: 0); _ = l.receivedHelloAck(from: "B", now: 0)
        l.receivedOther(from: "B", now: 2.5)
        XCTAssertFalse(l.tick(now: 5.0).contains(.safety(.connectionLost, peer: "B")))
        XCTAssertTrue(l.tick(now: 5.5).contains(.safety(.connectionLost, peer: "B")))
    }

    func testIncomingHelloWhenIdleConnectsPassively() {
        var l = L()
        XCTAssertEqual(l.receivedHello(from: "A", now: 0), [.sendHelloAck(peer: "A"), .log("Connected to A")])
        XCTAssertEqual(l.state, .connected(peer: "A"))
        // A second hello from the same peer just gets another ack.
        XCTAssertEqual(l.receivedHello(from: "A", now: 1), [.sendHelloAck(peer: "A")])
    }

    func testHelloFromThirdPartyIsIgnoredInOneToOneMode() {
        var l = L()
        _ = l.receivedHello(from: "A", now: 0)
        XCTAssertEqual(l.receivedHello(from: "C", now: 1), [.log("Ignored hello from C while linked to A")])
        XCTAssertEqual(l.peer, "A")
    }

    func testManualDisconnectSendsNotesOffBothSidesAndBye() {
        var l = L()
        _ = l.connect(to: "B", now: 0); _ = l.receivedHelloAck(from: "B", now: 0)
        XCTAssertEqual(l.disconnect(), [.safety(.manualDisconnect, peer: "B"), .sendBye(peer: "B"), .log("Disconnected from B")])
        XCTAssertEqual(l.state, .idle)
        XCTAssertEqual(l.tick(now: 100), [])   // no reconnect after a manual disconnect
        XCTAssertEqual(l.disconnect(), [])
    }

    func testManualDisconnectIsNotUndoneByLateHellos() {
        var l = L()
        _ = l.connect(to: "B", now: 0); _ = l.receivedHelloAck(from: "B", now: 0)
        _ = l.disconnect()
        // The Bye was lost and B keeps retrying: answer with Bye, stay idle.
        XCTAssertEqual(l.receivedHello(from: "B", now: 5), [.sendBye(peer: "B"), .log("Ignored hello from B after a manual disconnect")])
        XCTAssertEqual(l.state, .idle)
        // Another Mac can still connect.
        XCTAssertEqual(l.receivedHello(from: "C", now: 6), [.sendHelloAck(peer: "C"), .log("Connected to C")])
        _ = l.disconnect()
        // Connecting again by hand clears the block.
        _ = l.connect(to: "B", now: 7)
        _ = l.receivedHelloAck(from: "B", now: 7.1)
        XCTAssertTrue(l.isConnected)
    }

    func testSwitchingPeerDeclinesTheOldOne() {
        var l = L()
        _ = l.connect(to: "A", now: 0); _ = l.receivedHelloAck(from: "A", now: 0)
        _ = l.connect(to: "B", now: 1); _ = l.receivedHelloAck(from: "B", now: 1)
        // A missed the Bye and keeps sending hellos: it gets Bye again, even while linked to B.
        XCTAssertEqual(l.receivedHello(from: "A", now: 2).first, .sendBye(peer: "A"))
        _ = l.disconnect()
        XCTAssertEqual(l.receivedHello(from: "A", now: 3).first, .sendBye(peer: "A"))
        XCTAssertEqual(l.state, .idle)
    }

    func testByeStopsWithoutReconnect() {
        var l = L()
        _ = l.receivedHello(from: "A", now: 0)
        XCTAssertEqual(l.receivedBye(from: "A"), [.safety(.peerSaidBye, peer: "A"), .log("A disconnected")])
        XCTAssertEqual(l.state, .idle)
        XCTAssertEqual(l.tick(now: 10), [])
    }

    func testSwitchingPeerLeavesOldOneCleanly() {
        var l = L()
        _ = l.connect(to: "B", now: 0); _ = l.receivedHelloAck(from: "B", now: 0)
        XCTAssertEqual(l.connect(to: "C", now: 1),
                       [.safety(.manualDisconnect, peer: "B"), .sendBye(peer: "B"), .sendHello(peer: "C")])
    }

    func testStaleAckFromOtherPeerIgnored() {
        var l = L()
        _ = l.connect(to: "B", now: 0)
        XCTAssertEqual(l.receivedHelloAck(from: "X", now: 0.1), [])
        XCTAssertFalse(l.isConnected)
    }
}
