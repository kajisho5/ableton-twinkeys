import Foundation
import XCTest
@testable import TwinKeysCore

/// QLab mode: OSC 1.0 and SLIP (docs/design-qlab.md 8.1), the dictionary's replies and updates.
final class QLabOSCTests: XCTestCase {
    func testStringsArePaddedToFourBytesWithAtLeastOneNul() {
        XCTAssertEqual(OSC.paddedString("abc"), Array("abc".utf8) + [0])
        XCTAssertEqual(OSC.paddedString("abcd"), Array("abcd".utf8) + [0, 0, 0, 0])
        XCTAssertEqual(OSC.paddedString(""), [0, 0, 0, 0])
        let m = OSCMessage("/workspace/WS-1/go")
        XCTAssertEqual(m.encoded().count % 4, 0)
        XCTAssertEqual(m.encoded().map { String(format: "%02x", $0) }.joined(), "2f776f726b73706163652f57532d312f676f00002c000000")
    }

    func testEveryArgumentTypeRoundTrips() {
        let m = OSCMessage("/x", [.string("雨の音"), .int(-7), .float(1.25), .bool(true), .bool(false), .blob([1, 2, 3, 4, 5]), .string("")])
        let b = m.encoded()
        XCTAssertEqual(b.count % 4, 0)
        XCTAssertEqual(OSCMessage.decode(b), m)
        // Big-endian int.
        let i = OSCMessage("/i", [.int(1)]).encoded()
        XCTAssertEqual(Array(i.suffix(4)), [0, 0, 0, 1])
    }

    func testMalformedMessagesAreRejected() {
        XCTAssertNil(OSCMessage.decode([]))
        XCTAssertNil(OSCMessage.decode(Array("noslash".utf8) + [0]))
        XCTAssertNil(OSCMessage.decode(Array("/a".utf8) + [0]))                       // padding cut
        XCTAssertNil(OSCMessage.decode(OSC.paddedString("/a") + OSC.paddedString(",i") + [0, 0]))   // int cut
        XCTAssertNil(OSCMessage.decode(OSC.paddedString("/a") + OSC.paddedString(",q")))            // unknown type
        XCTAssertNil(OSCMessage.decode(OSC.paddedString("/a") + OSC.paddedString(",b") + [0, 0, 0, 9, 1]))  // blob too long
        // No type tag string at all: OSC 1.0 allows it.
        XCTAssertEqual(OSCMessage.decode(OSC.paddedString("/a")), OSCMessage("/a"))
    }

    func testSLIPEscapesAndSurvivesAnyChunking() {
        let packet: [UInt8] = [1, SLIP.end, 2, SLIP.esc, 3]
        let framed = SLIP.encode(packet)
        XCTAssertEqual(framed, [0xC0, 1, 0xDB, 0xDC, 2, 0xDB, 0xDD, 3, 0xC0])
        let stream = framed + SLIP.encode(OSCMessage("/b", [.int(5)]).encoded()) + [SLIP.end, SLIP.end]
        for size in 1...stream.count {
            var d = SLIPDecoder(), got: [[UInt8]] = []
            for start in stride(from: 0, to: stream.count, by: size) {
                got += d.feed(Array(stream[start..<min(stream.count, start + size)]))
            }
            XCTAssertEqual(got.count, 2, "chunk \(size)")
            XCTAssertEqual(got.first, packet)
            XCTAssertEqual(got.last.flatMap(OSCMessage.decode), OSCMessage("/b", [.int(5)]))
        }
    }

    func testSLIPDropsAnOversizedPacketAndCarriesOn() {
        var d = SLIPDecoder()
        var big = [SLIP.end] + [UInt8](repeating: 7, count: SLIPDecoder.maxPacket + 10) + [SLIP.end]
        big += SLIP.encode([9])
        XCTAssertEqual(d.feed(big), [[9]])
    }

    // MARK: Replies and updates

    func testReplyJSON() throws {
        let m = OSCMessage("/reply/workspace/W/cue/playhead/uniqueID",
                           [.string("{\"workspace_id\":\"W\",\"address\":\"/workspace/W/cue/playhead/uniqueID\",\"status\":\"ok\",\"data\":\"C-13\"}")])
        let r = try XCTUnwrap(QLabReply(m))
        XCTAssertEqual(r.address, "/workspace/W/cue/playhead/uniqueID")
        XCTAssertEqual(r.status, "ok")
        XCTAssertEqual(r.string, "C-13")
        XCTAssertNil(QLabReply(OSCMessage("/update/workspace/W")))
        // Without JSON: the address from the OSC address.
        XCTAssertEqual(QLabReply(OSCMessage("/reply/workspace/W/go"))?.address, "/workspace/W/go")
    }

    func testUpdates() {
        XCTAssertEqual(QLabUpdate(OSCMessage("/update/workspace/W")), .workspace("W"))
        XCTAssertEqual(QLabUpdate(OSCMessage("/update/workspace/W/cue_id/C1")), .cue(workspace: "W", cue: "C1"))
        XCTAssertEqual(QLabUpdate(OSCMessage("/update/workspace/W/cueList/L/playbackPosition", [.string("C2")])),
                       .playbackPosition(workspace: "W", list: "L", cue: "C2"))
        XCTAssertEqual(QLabUpdate(OSCMessage("/update/workspace/W/cueList/L/playbackPosition")),
                       .playbackPosition(workspace: "W", list: "L", cue: nil))
        XCTAssertEqual(QLabUpdate(OSCMessage("/update/workspace/W/disconnect")), .disconnect("W"))
        XCTAssertNil(QLabUpdate(OSCMessage("/update/workspace/W/dashboard")))
        XCTAssertNil(QLabUpdate(OSCMessage("/reply/x")))
    }

    func testCueListsAreFlattenedWithGroupDepth() throws {
        let json = """
        [{"uniqueID":"L","listName":"Main","cues":[
          {"uniqueID":"a","number":"1","name":"開演前の確認","listName":"開演前の確認","type":"Memo"},
          {"uniqueID":"g","number":"10","name":"第1場","type":"Group","cues":[
            {"uniqueID":"b","number":"12","name":"","listName":"雨の音（遠く）","type":"Audio","duration":200}]}]}]
        """
        let lists = QLabParse.cueLists(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, "Main")
        XCTAssertEqual(lists[0].cues.map(\.number), ["1", "10", "12"])
        XCTAssertEqual(lists[0].cues.map(\.depth), [0, 0, 1])
        XCTAssertEqual(lists[0].cues[2].name, "雨の音（遠く）")
        XCTAssertEqual(lists[0].cues[2].type, .audio)
        XCTAssertEqual(lists[0].cues[2].duration, 200)
        XCTAssertEqual(lists[0].cues[1].type, .group)
    }

    func testConnectAnswerWithPermissions() {
        XCTAssertNil(QLabEngine.permissions("ok"))
        XCTAssertEqual(QLabEngine.permissions("ok:view|control"), [.view, .control])
        XCTAssertEqual(QLabEngine.permissions("ok:view"), [.view])
    }

    func testTimeLeftIsDurationMinusElapsed() {
        let r = QLabRunningCue(uniqueID: "x", number: "12", name: "", type: .audio, elapsed: 132, duration: 200, paused: false)
        XCTAssertEqual(r.left, 68)
        XCTAssertEqual(r.fraction!, 0.66, accuracy: 0.001)
        let loop = QLabRunningCue(uniqueID: "y", number: "11.5", name: "", type: .audio, elapsed: 5, duration: 0, paused: false)
        XCTAssertNil(loop.left)
        XCTAssertEqual(formatQLabDuration(200), "3:20")
        XCTAssertEqual(formatQLabDuration(3725), "1:02:05")
    }

    func testCueKeySettingsKeepTheQLabAction() throws {
        var k = CueKey(keycode: 0x00, note: 50, qlab: QLabKeyAction(.goCue, cue: "90"))
        let json = String(decoding: try JSONEncoder().encode(k), as: UTF8.self)
        XCTAssertTrue(json.contains("\"action\":\"goCue\""), json)
        XCTAssertEqual(try JSONDecoder().decode(CueKey.self, from: Data(json.utf8)), k)
        // A key from an older settings file: the default for its key (Space = GO), A = nothing.
        let old = try JSONDecoder().decode(CueKey.self, from: Data("{\"keycode\":49,\"note\":40}".utf8))
        XCTAssertNil(old.qlab)
        XCTAssertEqual(old.qlabAction, QLabKeyAction(.go))
        XCTAssertNil(CueKey(keycode: 0x00, note: 1).qlabAction)
        // "none" chosen for Space stays none.
        k = CueKey(keycode: KeyNames.space, note: 40, qlab: QLabKeyAction(nil))
        let back = try JSONDecoder().decode(CueKey.self, from: JSONEncoder().encode(k))
        XCTAssertNil(back.qlabAction?.command(expect: nil))
        // An unknown action name reads as none.
        let odd = try JSONDecoder().decode(CueKey.self, from: Data("{\"keycode\":0,\"note\":1,\"qlab\":{\"action\":\"fly\"}}".utf8))
        XCTAssertNil(odd.qlabAction?.action)
    }

    func testSettingsDefaultToAbletonLive() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s.target, .live)
        XCTAssertTrue(s.qlab.followPlayhead)
        XCTAssertTrue(s.qlab.refuseStaleGo)
        XCTAssertFalse(s.qlab.notesInQLabMode)
        var t = AppSettings()
        t.target = .both; t.qlab.workspaceName = "sample-show"
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.target, .both)
        XCTAssertEqual(back.qlab.workspaceName, "sample-show")
        // A broken qlab section does not lose the file.
        let broken = try JSONDecoder().decode(AppSettings.self, from: Data("{\"target\":\"qlab\",\"qlab\":7}".utf8))
        XCTAssertEqual(broken.target, .qlab)
        XCTAssertEqual(broken.qlab, QLabSettings())
    }
}

/// The decisions of design 5.3.
final class QLabPlannerTests: XCTestCase {
    let ws = "W"
    let cues = [QLabCue(uniqueID: "u12", number: "12", name: "雨の音（遠く）", type: .audio),
                QLabCue(uniqueID: "u13", number: "13", name: "雷鳴 1", type: .audio),
                QLabCue(uniqueID: "uJ", number: "第2場", name: "", type: .group),
                QLabCue(uniqueID: "uS", number: "1 A", name: "", type: .audio)]

    func testBackupGoesWhenStandingByOnTheSameCue() {
        let p = QLabPlanner.plan(QLabCommand(action: .go, expect: "13"), workspace: ws, cues: cues,
                                 playhead: QLabCueRef(uniqueID: "u13", number: "13"), asBackup: true)
        XCTAssertEqual(p, .send([OSCMessage("/workspace/W/go")], code: .ok))
    }

    func testBackupOnAnotherCueGoesTheMainsCueByUniqueID() {
        let p = QLabPlanner.plan(QLabCommand(action: .go, expect: "13"), workspace: ws, cues: cues,
                                 playhead: QLabCueRef(uniqueID: "u12", number: "12"), asBackup: true)
        XCTAssertEqual(p, .send([OSCMessage("/workspace/W/cue_id/u13/go")], code: .corrected))
    }

    func testBackupWithoutTheCuePlaysNothing() {
        let p = QLabPlanner.plan(QLabCommand(action: .go, expect: "99"), workspace: ws, cues: cues,
                                 playhead: QLabCueRef(uniqueID: "u12", number: "12"), asBackup: true)
        XCTAssertEqual(p, .refuse(.noSuchCue))
    }

    func testNumbersWithSpacesOrJapaneseAreUsedThroughTheUniqueID() {
        // OSC addresses cannot hold them (design 3.1): /cue_id/{uid} instead of /cue/{number}.
        XCTAssertEqual(QLabPlanner.plan(QLabCommand(action: .goCue, cueNumber: "第2場"), workspace: ws, cues: cues, playhead: nil, asBackup: false),
                       .send([OSCMessage("/workspace/W/cue_id/uJ/go")], code: .ok))
        XCTAssertEqual(QLabPlanner.plan(QLabCommand(action: .setPlayhead, cueNumber: "1 A"), workspace: ws, cues: cues, playhead: nil, asBackup: false),
                       .send([OSCMessage("/workspace/W/playheadID/uS")], code: .ok))
    }

    func testMainGoIsPlainAndStopIsHardStop() {
        XCTAssertEqual(QLabPlanner.plan(QLabCommand(action: .go, expect: "12"), workspace: ws, cues: cues, playhead: nil, asBackup: false),
                       .send([OSCMessage("/workspace/W/go")], code: .ok))
        XCTAssertEqual(QLabPlanner.plan(QLabCommand(action: .hardStop), workspace: ws, cues: cues, playhead: nil, asBackup: false),
                       .send([OSCMessage("/workspace/W/hardStop")], code: .ok))
        XCTAssertEqual(QLabPlanner.plan(QLabCommand(action: .goCue), workspace: ws, cues: cues, playhead: nil, asBackup: false), .refuse(.noSuchCue))
    }

    func testGoIsRefusedWhenNextChanged() {
        var g = QLabGoGuard()
        let ph = QLabCueRef(uniqueID: "u13", number: "13")
        XCTAssertEqual(QLabPlanner.mainCheck(QLabCommand(action: .go, expect: "12"), playhead: ph, refuseStale: true, guardState: &g, now: 0),
                       .nextChanged(now: "13"))
        // Off in the settings: sent.
        XCTAssertEqual(QLabPlanner.mainCheck(QLabCommand(action: .go, expect: "11"), playhead: ph, refuseStale: false, guardState: &g, now: 1), .ok)
        // Without expect (a cue key): no check.
        XCTAssertEqual(QLabPlanner.mainCheck(QLabCommand(action: .go), playhead: ph, refuseStale: true, guardState: &g, now: 2), .ok)
    }

    func testDoublePressCountsOnce() {
        var g = QLabGoGuard()
        let ph = QLabCueRef(uniqueID: "u13", number: "13")
        let go = QLabCommand(action: .go, expect: "13")
        XCTAssertEqual(QLabPlanner.mainCheck(go, playhead: ph, refuseStale: true, guardState: &g, now: 10), .ok)
        // The second tap saw the same "next" (QLab has moved on): a double press, not "next changed".
        XCTAssertEqual(QLabPlanner.mainCheck(go, playhead: QLabCueRef(uniqueID: "u14", number: "14"), refuseStale: true, guardState: &g, now: 10.2), .doublePress)
        XCTAssertEqual(QLabPlanner.mainCheck(go, playhead: ph, refuseStale: true, guardState: &g, now: 10.6), .ok)
        // Panic is never merged.
        XCTAssertEqual(QLabPlanner.mainCheck(QLabCommand(action: .panic), playhead: ph, refuseStale: true, guardState: &g, now: 10.61), .ok)
        XCTAssertEqual(QLabPlanner.mainCheck(QLabCommand(action: .panic), playhead: ph, refuseStale: true, guardState: &g, now: 10.62), .ok)
    }

    func testFollowWaitsAfterAGoAndSkipsWhatIsAlreadyThere() {
        let ph = QLabCueRef(uniqueID: "u12", number: "12")
        XCTAssertEqual(QLabPlanner.follow(mainNumber: "13", playhead: ph, cues: cues, workspace: ws, lastGoAt: 0, now: 5),
                       OSCMessage("/workspace/W/playheadID/u13"))
        XCTAssertNil(QLabPlanner.follow(mainNumber: "13", playhead: ph, cues: cues, workspace: ws, lastGoAt: 4.8, now: 5))
        XCTAssertNil(QLabPlanner.follow(mainNumber: "12", playhead: ph, cues: cues, workspace: ws, lastGoAt: 0, now: 5))
        XCTAssertNil(QLabPlanner.follow(mainNumber: "99", playhead: ph, cues: cues, workspace: ws, lastGoAt: 0, now: 5))
        XCTAssertNil(QLabPlanner.follow(mainNumber: nil, playhead: ph, cues: cues, workspace: ws, lastGoAt: 0, now: 5))
    }

    func testResendsRunOnce() {
        var seen = QLabSeenCommands()
        let k = QLabSeenCommands.key(session: 1, id: 5)
        XCTAssertTrue(seen.first(k))
        XCTAssertFalse(seen.first(k))
        XCTAssertNil(seen.result(k))
        seen.setResult(k, .corrected)
        XCTAssertEqual(seen.result(k), .corrected)
        XCTAssertTrue(seen.first(QLabSeenCommands.key(session: 2, id: 5)))   // a new session of the main Mac
        for i in 0..<300 { _ = seen.first(QLabSeenCommands.key(session: 3, id: UInt32(i))) }
        XCTAssertTrue(seen.first(k))       // forgotten after 256 others
    }
}

/// Packets 0x23–0x26 and the cue list comparison.
final class QLabWireTests: XCTestCase {
    func roundTrip(_ body: PacketBody) throws -> PacketBody {
        let bytes = Packet(session: 3, seq: 4, body: body).encode()
        XCTAssertLessThanOrEqual(bytes.count + SecureChannel.tagSize, WireProtocol.maxPacketSize)
        return try Packet.decode(bytes).body
    }

    func testCommandsResultsStatesAndItemsRoundTrip() throws {
        for b: PacketBody in [.qlabCommand(id: 1, QLabCommand(action: .go, expect: "11.5")),
                              .qlabCommand(id: 2, QLabCommand(action: .goCue, cueNumber: "第2場")),
                              .qlabCommand(id: UInt32.max, QLabCommand(action: .resume)),
                              .qlabResult(id: 9, code: 1),
                              .qlabState(QLabLinkState(state: .viewOnly, permissions: [.view], showMode: false, follow: true, target: .both,
                                                       running: 300, cueCount: 70000, listHash: 1, keysHash: 2, playhead: "13")),
                              .qlabItem(index: 2, number: "12", type: 1, name: "雨の音（遠く）")] {
            var expected = b
            if case var .qlabState(s) = b { s.running = 255; s.cueCount = 65535; expected = .qlabState(s) }
            XCTAssertEqual(try roundTrip(b), expected)
        }
    }

    func testLongTextsAreCutOnACharacter() throws {
        let long = String(repeating: "雷", count: 30)          // 90 bytes
        guard case let .qlabItem(_, n, _, name) = try roundTrip(.qlabItem(index: 0, number: long, type: 0, name: long)) else { return XCTFail() }
        XCTAssertEqual(n, String(repeating: "雷", count: 8))     // 24 bytes
        XCTAssertEqual(name, String(repeating: "雷", count: 21))  // 63 of 64 bytes
        // A command whose number is too long is not valid (it could not be matched on the backup).
        XCTAssertFalse(QLabCommand(action: .goCue, cueNumber: long).isValid)
    }

    func testBrokenPayloadsAreRejected() {
        func h(_ t: UInt8) -> [UInt8] { [0x54, 0x4B, 2, t, 0, 0, 0, 1, 0, 0, 0, 2] }
        for bad in [h(0x23) + [0, 0, 0, 1, 99, 0, 0],          // unknown action
                    h(0x23) + [0, 0, 0, 1, 6, 0, 0],           // goCue without a number
                    h(0x23) + [0, 0, 0, 1, 1, 30] + [UInt8](repeating: 0x31, count: 30) + [0],
                    h(0x24) + [0, 0, 0],
                    h(0x25) + [6, 0, 0],
                    h(0x26) + [0, 1, 5, 0x31]] {
            XCTAssertThrowsError(try Packet.decode(bad))
        }
    }

    func testCueListComparison() {
        let mine = [QLabCue(uniqueID: "a", number: "1", name: "開演前の確認", type: .memo),
                    QLabCue(uniqueID: "b", number: "2", name: "客入れ BGM", type: .audio)]
        let summary = QLabCueSummary(mine)
        var peer = QLabPeerCues()
        peer.summary(count: 2, hash: summary.hash)
        XCTAssertNil(QLabCueDiff.compare(mine: summary, peer: peer))
        XCTAssertNil(QLabCueDiff.compare(mine: summary, peer: nil))
        // The backup has one cue renamed and one more.
        peer.summary(count: 3, hash: 1)
        peer.item(index: 0, .init(number: "1", type: .memo, name: "開演前の確認"))
        peer.item(index: 1, .init(number: "2", type: .audio, name: "客入れ BGM v2"))
        var d = QLabCueDiff.compare(mine: summary, peer: peer)
        XCTAssertEqual(d?.differences, 1)
        XCTAssertEqual(d?.complete, false)
        peer.item(index: 2, .init(number: "3", type: .fade, name: "F.O."))
        d = QLabCueDiff.compare(mine: summary, peer: peer)
        XCTAssertEqual(d?.differences, 2)
        XCTAssertEqual(d?.complete, true)
        XCTAssertEqual(d?.rows.last?.main, nil)
        XCTAssertEqual(d?.rows.last?.backup, "3 FADE F.O.")
        XCTAssertEqual(d?.mainCount, 2)
        XCTAssertEqual(d?.backupCount, 3)
        // The hash covers the type too.
        XCTAssertNotEqual(QLabCueSummary([QLabCue(uniqueID: "a", number: "1", name: "x", type: .audio)]).hash,
                          QLabCueSummary([QLabCue(uniqueID: "a", number: "1", name: "x", type: .fade)]).hash)
    }

    func testCueListPiecesMergeOnTheIPhone() {
        let cues = (0..<450).map { QLabCue(uniqueID: "u\($0)", number: "\($0)", name: "", type: .audio) }
        let pieces = QLabCueList.pieces(workspace: "W", listName: "Main", cues: cues)
        XCTAssertEqual(pieces.count, 3)
        var list: [QLabCue] = []
        for p in pieces { list = QLabCueList.merge(p, into: list) }
        XCTAssertEqual(list, cues)
        // A missing piece: the list stays as it was until the next full send.
        XCTAssertEqual(QLabCueList.merge(pieces[2], into: Array(cues.prefix(10))), Array(cues.prefix(10)))
        XCTAssertEqual(QLabCueList.merge(QLabCueList.pieces(workspace: "W", listName: "Main", cues: [])[0], into: cues), [])
    }
}
