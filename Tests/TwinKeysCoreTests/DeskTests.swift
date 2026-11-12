import XCTest
@testable import TwinKeysCore

// 2.4: moving a Yamaha console's faders from the backup Mac (docs/design-v2.4-ql.md).

final class DeskModelTests: XCTestCase {
    func testModelsAndChannelLimits() {
        XCTAssertEqual(DeskModel.allCases.count, 7)
        let expected: [DeskModel: (Int, Int, Bool, Bool)] = [
            .ql1: (32, 8, false, true), .ql5: (64, 8, false, true), .dm3: (16, 1, true, true),
            .dm7: (120, 0, true, true), .dm7Compact: (72, 0, true, true),
            .dm5: (60, 0, true, false), .dm5Compact: (48, 0, true, false),
        ]
        for m in DeskModel.allCases {
            let e = expected[m]!
            XCTAssertEqual(m.inputChannels, e.0, "\(m)")
            XCTAssertEqual(m.stereoInChannels, e.1, "\(m)")
            XCTAssertEqual(m.hasStereoIn, e.1 > 0, "\(m)")
            XCTAssertEqual(m.supportsOSC, e.2, "\(m)")
            XCTAssertEqual(m.readVerified, e.3, "\(m)")
            XCTAssertEqual(m.channelLimit(.input), e.0)
            XCTAssertEqual(m.channelLimit(.stereoIn), e.1)
        }
        XCTAssertEqual(DeskModel.dm3.displayName, "DM3 / DM3 Standard")
        XCTAssertEqual(DeskModel.dm3.shortName, "DM3")
        XCTAssertEqual(DeskModel.dm7Compact.displayName, "DM7 Compact")
        XCTAssertEqual(DeskModel.dm5Compact.shortName, "DM5 Compact")
        XCTAssertTrue(DeskModel.dm3.oscUsesYIndex)
        XCTAssertFalse(DeskModel.dm7.oscUsesYIndex)
    }

    func testChannelAddresses() {
        XCTAssertEqual(DeskChannel(.input, 4).addresses, [FaderAddress(.input, x: 3)])
        XCTAssertEqual(DeskChannel(.stereoIn, 1).addresses, [FaderAddress(.stereoIn, x: 0), FaderAddress(.stereoIn, x: 1)])
        XCTAssertEqual(DeskChannel(.stereoIn, 3).addresses, [FaderAddress(.stereoIn, x: 4), FaderAddress(.stereoIn, x: 5)])
        XCTAssertEqual(FaderAddress(.stereoIn, x: 5).channel, DeskChannel(.stereoIn, 3))
        XCTAssertEqual(FaderAddress(.input, x: 0).channel, DeskChannel(.input, 1))
        XCTAssertEqual(DeskChannel(.stereoIn, 2).description, "ST IN 2")
        XCTAssertEqual(DeskChannel(.input, 9).description, "Ch 9")
    }
}

final class DeskLevelTests: XCTestCase {
    func testTextAndClamp() {
        XCTAssertEqual(DeskLevel.text(-600), "-6.0 dB")
        XCTAssertEqual(DeskLevel.text(0), "0.0 dB")
        XCTAssertEqual(DeskLevel.text(1000), "+10.0 dB")
        XCTAssertEqual(DeskLevel.text(-1250), "-12.5 dB")
        XCTAssertEqual(DeskLevel.text(-32768), "-∞ dB")
        XCTAssertEqual(DeskLevel.number(-655), "-6.6")
        XCTAssertEqual(DeskLevel.clamped(5000), 1000)
        XCTAssertEqual(DeskLevel.clamped(-20000), -13800)
        XCTAssertEqual(DeskLevel.clamped(-32768), -32768)
        XCTAssertEqual(DeskLevel.clamped(-40000), -32768)
    }

    func testParse() {
        XCTAssertEqual(DeskLevel.parse("-6"), -600)
        XCTAssertEqual(DeskLevel.parse(" -6.0 dB "), -600)
        XCTAssertEqual(DeskLevel.parse("\u{2212}12,5"), -1250)
        XCTAssertEqual(DeskLevel.parse("+3"), 300)
        XCTAssertEqual(DeskLevel.parse("20"), 1000)
        XCTAssertEqual(DeskLevel.parse("-200"), -13800)
        XCTAssertEqual(DeskLevel.parse("-inf"), -32768)
        XCTAssertEqual(DeskLevel.parse("-∞"), -32768)
        XCTAssertNil(DeskLevel.parse(""))
        XCTAssertNil(DeskLevel.parse("loud"))
    }
}

final class FaderTaperTests: XCTestCase {
    func testBreakpoints() {
        XCTAssertEqual(FaderTaper.position(1000), 1.0, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.position(-1000), 0.6, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.position(-4000), 0.2, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.position(-13800), 0.0, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.position(-32768), 0.0)
        XCTAssertEqual(FaderTaper.position(0), 0.8, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.position(-2500), 0.4, accuracy: 1e-12)
        XCTAssertEqual(FaderTaper.level(atPosition: 1), 1000)
        XCTAssertEqual(FaderTaper.level(atPosition: 0.6), -1000)
        XCTAssertEqual(FaderTaper.level(atPosition: 0.2), -4000)
        XCTAssertEqual(FaderTaper.level(atPosition: 0.8), 0)
        XCTAssertEqual(FaderTaper.level(atPosition: 0), -32768)
        XCTAssertEqual(FaderTaper.level(atPosition: -0.5), -32768)
        XCTAssertEqual(FaderTaper.level(atPosition: 2), 1000)
        XCTAssertEqual(FaderTaper.level(atPosition: .nan), -32768)
    }

    func testRoundTripAndRange() {
        var previous = -Double.infinity
        for v in stride(from: -13800, through: 1000, by: 25) {
            let p = FaderTaper.position(v)
            XCTAssertGreaterThanOrEqual(p, previous)        // the higher the level, the higher the fader
            previous = p
            if v > -13800 { XCTAssertEqual(FaderTaper.level(atPosition: p), v, accuracy: 1) }
        }
        for i in 0...1000 {
            let v = FaderTaper.level(atPosition: Double(i) / 1000)
            XCTAssertTrue(v == -32768 || (-13800...1000).contains(v), "\(v)")
        }
    }

    func testInterpolationMovesEvenlyAlongTheFader() {
        XCTAssertEqual(FaderTaper.interpolate(from: -32768, to: -600, fraction: 0), -32768)
        XCTAssertEqual(FaderTaper.interpolate(from: -32768, to: -600, fraction: 1), -600)
        XCTAssertEqual(FaderTaper.interpolate(from: -600, to: -32768, fraction: 1), -32768)
        // Half way from −∞ to 0 dB (position 0.8) is position 0.4 = −25 dB, not −69 dB.
        XCTAssertEqual(FaderTaper.interpolate(from: -32768, to: 0, fraction: 0.5), -2500)
        XCTAssertEqual(FaderTaper.interpolate(from: 1000, to: -1000, fraction: 0.5), 0)
    }
}

final class DeskRCPTests: XCTestCase {
    func testCommands() {
        XCTAssertEqual(DeskRCP.get(FaderAddress(.input, x: 3)), "get MIXER:Current/InCh/Fader/Level 3 0\n")
        XCTAssertEqual(DeskRCP.set(FaderAddress(.input, x: 3), -500), "set MIXER:Current/InCh/Fader/Level 3 0 -500\n")
        XCTAssertEqual(DeskRCP.set(FaderAddress(.stereoIn, x: 1), -32768), "set MIXER:Current/StInCh/Fader/Level 1 0 -32768\n")
        XCTAssertEqual(DeskRCP.set(FaderAddress(.input, x: 0), 5000), "set MIXER:Current/InCh/Fader/Level 0 0 1000\n")
        XCTAssertEqual(DeskRCP.keepalive, "scpmode keepalive 10000\n")
        XCTAssertEqual(DeskRCP.ping, "devstatus runmode\n")
    }

    func testParseLevels() {
        let in3 = FaderAddress(.input, x: 3)
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level 3 0 -1000"), .level(in3, value: -1000, source: .get))
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level 3 0 -1000 \"-10.00\""), .level(in3, value: -1000, source: .get))
        XCTAssertEqual(DeskRCP.parse("  OK   get\tMIXER:Current/InCh/Fader/Level  3  0  -1000\r"), .level(in3, value: -1000, source: .get))
        XCTAssertEqual(DeskRCP.parse("OK set MIXER:Current/InCh/Fader/Level 3 0 -500 \"-5.00\""), .level(in3, value: -500, source: .set))
        XCTAssertEqual(DeskRCP.parse("OKm set MIXER:Current/InCh/Fader/Level 3 0 1000 \"10.00\""), .level(in3, value: 1000, source: .setAdjusted))
        XCTAssertEqual(DeskRCP.parse("NOTIFY set MIXER:Current/InCh/Fader/Level 3 0 -500 \"-5.00\""), .level(in3, value: -500, source: .notify))
        XCTAssertEqual(DeskRCP.parse("NOTIFY set MIXER:Current/StInCh/Fader/Level 5 0 -32768 \"-Inf\""),
                       .level(FaderAddress(.stereoIn, x: 5), value: -32768, source: .notify))
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level 0 0 -20000"), .level(FaderAddress(.input, x: 0), value: -13800, source: .get))
    }

    func testParseOtherLines() {
        XCTAssertEqual(DeskRCP.parse("ERROR get UnknownAddress"), .error(command: "get", code: "UnknownAddress"))
        XCTAssertEqual(DeskRCP.parse("ERROR set InvalidArgument"), .error(command: "set", code: "InvalidArgument"))
        XCTAssertEqual(DeskRCP.parse("ERROR set MIXER:Current/InCh/Fader/Level 3 0 Busy"), .error(command: "set", code: "Busy"))
        XCTAssertEqual(DeskRCP.parse("ERROR WrongFormat"), .error(command: "WrongFormat", code: ""))
        XCTAssertEqual(DeskRCP.parse("OK scpmode keepalive 10000"), .ok(command: "scpmode"))
        XCTAssertEqual(DeskRCP.parse("OK devstatus runmode \"normal\""), .ok(command: "devstatus"))
        // Another parameter, a Y other than 0, a broken number: not a fader level.
        XCTAssertEqual(DeskRCP.parse("NOTIFY set MIXER:Current/InCh/Fader/On 3 0 1"), .notify)
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level 3 1 -1000"), .ok(command: "get"))
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level x 0 -1000"), .ok(command: "get"))
        XCTAssertEqual(DeskRCP.parse("OK get MIXER:Current/InCh/Fader/Level 3 0"), .ok(command: "get"))
        XCTAssertEqual(DeskRCP.parse("hello"), .unknown("hello"))
        XCTAssertEqual(DeskRCP.parse(""), .unknown(""))
    }

    func testTokenizeKeepsQuotedText() {
        XCTAssertEqual(DeskRCP.tokenize("OK get A 1 0 2 \"two words\" tail"), ["OK", "get", "A", "1", "0", "2", "two words", "tail"])
        XCTAssertEqual(DeskRCP.tokenize("a \"\" b"), ["a", "", "b"])
    }
}

final class DeskOSCTests: XCTestCase {
    func testMessageBytes() {
        let m = DeskOSC.message("/a", int32: -500)
        XCTAssertEqual(m, [0x2F, 0x61, 0, 0, 0x2C, 0x69, 0, 0, 0xFF, 0xFF, 0xFE, 0x0C])
        XCTAssertEqual(DeskOSC.string("/abc"), [0x2F, 0x61, 0x62, 0x63, 0, 0, 0, 0])   // always null-terminated
        let full = DeskOSC.message("/yosc:req/set/MIXER:Current/InCh/Fader/Level/1/1", int32: -32768)
        XCTAssertEqual(full.count % 4, 0)
        XCTAssertEqual(Array(full.suffix(4)), [0xFF, 0xFF, 0x80, 0x00])
        XCTAssertEqual(Array(full.suffix(8).prefix(4)), [0x2C, 0x69, 0, 0])
    }

    func testYamahaAddresses() {
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.input, 1), model: .dm3), ["/yosc:req/set/MIXER:Current/InCh/Fader/Level/1/1"])
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.input, 9), model: .dm7), ["/yosc:req/set/MIXER:Current/InCh/Fader/Level/9"])
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.input, 48), model: .dm5Compact), ["/yosc:req/set/MIXER:Current/InCh/Fader/Level/48"])
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.stereoIn, 1), model: .dm3),
                       ["/yosc:req/set/MIXER:Current/StInCh/Fader/Level/1/1", "/yosc:req/set/MIXER:Current/StInCh/Fader/Level/2/1"])
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.input, 1), model: .ql5), [])        // QL has no OSC
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.stereoIn, 1), model: .dm7), [])     // DM7 has no ST IN
        XCTAssertEqual(DeskYamahaOSC.addresses(DeskChannel(.input, 17), model: .dm3), [])       // beyond the model
        XCTAssertEqual(DeskYamahaOSC.messages(DeskChannel(.input, 2), value: 0, model: .dm7),
                       [DeskOSC.message("/yosc:req/set/MIXER:Current/InCh/Fader/Level/2", int32: 0)])
    }
}

final class DeskSettingsTests: XCTestCase {
    func testDefaultsAreOff() throws {
        let d = DeskSettings()
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.trigger, .confirm)
        XCTAssertEqual(d.fade, 0.5)
        XCTAssertTrue(d.pullMainToMinusInfinity)
        XCTAssertTrue(d.useFixedLevels)
        XCTAssertTrue(d.moveDeskWhenConfirming)
        XCTAssertFalse(AppSettings().desk.enabled)
        // Old settings files have no "desk": the feature stays off.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"send_keys": false}"#.utf8))
        XCTAssertEqual(old.desk, DeskSettings())
        XCTAssertFalse(old.sendKeys)
    }

    func testRoundTripAndLenientDecoding() throws {
        var a = AppSettings()
        a.desk.enabled = true
        a.desk.model = .dm7Compact
        a.desk.host = "192.168.0.128"
        a.desk.rows = [DeskRow(mainChannel: 1, backupChannel: 9, fixedLevel: -600, name: "Music L")]
        a.desk.trigger = .automatic
        a.desk.fade = 2
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.desk, a.desk)

        let json = #"{"desk": {"enabled": true, "model": "dm9", "fade": 0.7, "trigger": "sometimes", "host": " 10.0.0.2 ", "#
            + #""rows": [{"kind": "stereo_in", "main_channel": 1, "backup_channel": 2}, {"main_channel": "x"}, "#
            + #"{"main_channel": 3, "backup_channel": 4, "fixed_level": 99999}]}}"#
        let d = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).desk
        XCTAssertTrue(d.enabled)
        XCTAssertEqual(d.model, .ql5)               // unknown model: the default
        XCTAssertEqual(d.fade, 0.5)                 // nearest offered fade
        XCTAssertEqual(d.trigger, .confirm)
        XCTAssertEqual(d.host, "10.0.0.2")
        XCTAssertEqual(d.rows.count, 2)             // the broken row is dropped, not the others
        XCTAssertEqual(d.rows[0].kind, .stereoIn)
        XCTAssertEqual(d.rows[1].fixedLevel, 1000)
        XCTAssertEqual(d.rows[1].kind, .input)

        let broken = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"desk": 5, "language": "ja"}"#.utf8))
        XCTAssertEqual(broken.desk, DeskSettings())
        XCTAssertEqual(broken.language, "ja")       // the rest of the file still loads
    }

    func testFadesAndHosts() {
        XCTAssertEqual(DeskSettings.nearestFade(0), 0)
        XCTAssertEqual(DeskSettings.nearestFade(0.4), 0.5)
        XCTAssertEqual(DeskSettings.nearestFade(1.4), 1)
        XCTAssertEqual(DeskSettings.nearestFade(9), 2)
        XCTAssertEqual(DeskSettings.nearestFade(.nan), 0.5)
        XCTAssertTrue(DeskSettings.isValidHost("192.168.0.128"))
        XCTAssertTrue(DeskSettings.isValidHost("10.0.0.1"))
        for bad in ["", "192.168.0", "192.168.0.256", "a.b.c.d", "192.168.0.1 ", "1..2.3", "１.2.3.4", "1.2.3.4.5", "0001.2.3.4"] {
            XCTAssertFalse(DeskSettings.isValidHost(bad), bad)
        }
    }

    func testProblems() {
        let ok = [DeskRow(mainChannel: 1, backupChannel: 9), DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2)]
        XCTAssertEqual(DeskSettings.problems(rows: ok, model: .ql5), [])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 1, backupChannel: 65)], model: .ql5),
                       [.channelOutOfRange(row: 1, channel: DeskChannel(.input, 65), limit: 64)])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 0, backupChannel: 2)], model: .ql5),
                       [.channelOutOfRange(row: 1, channel: DeskChannel(.input, 0), limit: 64)])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2)], model: .dm7), [.noStereoIn(row: 1)])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2)], model: .dm3),
                       [.channelOutOfRange(row: 1, channel: DeskChannel(.stereoIn, 2), limit: 1)])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 3, backupChannel: 3)], model: .ql1), [.sameChannel(row: 1)])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 1, backupChannel: 9), DeskRow(mainChannel: 9, backupChannel: 10)], model: .ql1),
                       [.usedTwice(DeskChannel(.input, 9))])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 1, backupChannel: 2, fixedLevel: -32768)], model: .ql1),
                       [.fixedLevelMinusInfinity(row: 1)])
        // The same numbers as an input and as a stereo input are different channels.
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 1, backupChannel: 2), DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2)], model: .ql5), [])
        XCTAssertEqual(DeskSettings.problems(rows: [DeskRow(mainChannel: 120, backupChannel: 119)], model: .dm7), [])
        XCTAssertFalse(DeskSettings.problems(rows: [DeskRow(mainChannel: 61, backupChannel: 1)], model: .dm5).isEmpty)
        XCTAssertFalse(DeskSettings.problems(rows: [DeskRow(mainChannel: 49, backupChannel: 1)], model: .dm5Compact).isEmpty)
    }

    func testNewRowUsesFreeChannels() {
        var s = DeskSettings()
        s.model = .dm3
        let r1 = s.newRow()!
        XCTAssertEqual([r1.mainChannel, r1.backupChannel], [1, 2])
        s.rows = [r1, DeskRow(mainChannel: 3, backupChannel: 9)]
        let r2 = s.newRow()!
        XCTAssertEqual([r2.mainChannel, r2.backupChannel], [4, 5])
        s.rows = (0..<8).map { DeskRow(mainChannel: 2 * $0 + 1, backupChannel: 2 * $0 + 2) }
        XCTAssertNil(s.newRow())                     // all 16 DM3 inputs used
    }
}

final class DeskPlannerTests: XCTestCase {
    let rows = [
        DeskRow(mainChannel: 1, backupChannel: 9, name: "Music L"),
        DeskRow(mainChannel: 2, backupChannel: 10, name: "Music R"),
        DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2, fixedLevel: -1200, name: "Amb"),
    ]
    let main: [DeskChannel: Int] = [DeskChannel(.input, 1): -600, DeskChannel(.input, 2): -600, DeskChannel(.stereoIn, 1): -1200]

    func testInstantTakeover() throws {
        let r = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: main, backupLevels: [:], fade: 0, pullMainToMinusInfinity: true)
        XCTAssertEqual(r.plan.steps.count, 1)
        XCTAssertEqual(r.plan.steps[0].at, 0)
        XCTAssertEqual(r.plan.targets, [
            DeskChannel(.input, 9): -600, DeskChannel(.input, 10): -600, DeskChannel(.stereoIn, 2): -1200,
            DeskChannel(.input, 1): -32768, DeskChannel(.input, 2): -32768, DeskChannel(.stereoIn, 1): -32768,
        ])
        XCTAssertTrue(r.levelsWereRead)
        XCTAssertEqual(r.mainBefore[DeskChannel(.input, 1)], -600)
        XCTAssertTrue(r.backupBefore.isEmpty)
    }

    func testFadeStepsEvery50msInFaderPosition() throws {
        let r = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: main,
                                         backupLevels: [DeskChannel(.input, 9): -32768], fade: 0.5, pullMainToMinusInfinity: true)
        let steps = r.plan.steps
        XCTAssertEqual(steps.count, 10)
        for (i, s) in steps.enumerated() { XCTAssertEqual(s.at, 0.05 * Double(i + 1), accuracy: 1e-9) }
        XCTAssertEqual(r.plan.duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(steps.last!.writes.count, 6)                     // every channel's final level
        let backup9 = steps.compactMap { $0.writes.first { $0.channel == DeskChannel(.input, 9) }?.value }
        let main1 = steps.compactMap { $0.writes.first { $0.channel == DeskChannel(.input, 1) }?.value }
        XCTAssertEqual(backup9.count, 10)
        XCTAssertEqual(backup9, backup9.sorted())                       // only up
        XCTAssertEqual(main1, main1.sorted(by: >))                      // only down
        XCTAssertEqual(backup9.last, -600)
        XCTAssertEqual(main1.last, -32768)
        // Even steps along the fader: k/10 of the way to −6 dB's position.
        let target = FaderTaper.position(-600)
        for (k, v) in backup9.enumerated() {
            XCTAssertEqual(FaderTaper.position(v), target * Double(k + 1) / 10, accuracy: 0.001)
        }
        for s in steps { for w in s.writes { XCTAssertTrue(w.value == -32768 || (-13800...1000).contains(w.value)) } }
        // The main channel is never pulled to −∞ before the backup has arrived.
        XCTAssertTrue(main1.dropLast().allSatisfy { $0 > -32768 })
    }

    func testLongerFadesAndUnchangedChannels() throws {
        for (fade, n) in [(1.0, 20), (2.0, 40)] {
            let r = try DeskPlanner.takeover(rows: [rows[0]], model: .ql5, mainLevels: main, backupLevels: nil, fade: fade, pullMainToMinusInfinity: false)
            XCTAssertEqual(r.plan.steps.count, n)
            XCTAssertEqual(r.plan.duration, fade, accuracy: 1e-9)
            XCTAssertEqual(Set(r.plan.steps.flatMap(\.writes).map(\.channel)), [DeskChannel(.input, 9)])   // main untouched
        }
        // Nothing to move but the final level: one step.
        let p = DeskPlanner.fade([DeskMove(DeskChannel(.input, 1), from: -600, to: -600)], over: 0.5)
        XCTAssertEqual(p.steps, [DeskStep(at: 0.5, writes: [DeskWrite(DeskChannel(.input, 1), -600)])])
        XCTAssertEqual(DeskPlanner.fade([], over: 1).steps, [])
    }

    func testUnreadableUsesFixedLevelsAndCutsMainAtTheEnd() throws {
        let r = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: nil, backupLevels: nil, fade: 0.5, pullMainToMinusInfinity: true)
        XCTAssertFalse(r.levelsWereRead)
        XCTAssertEqual(r.plan.targets[DeskChannel(.input, 9)], 0)
        XCTAssertEqual(r.plan.targets[DeskChannel(.stereoIn, 2)], -1200)
        XCTAssertEqual(r.mainBefore[DeskChannel(.stereoIn, 1)], -1200)
        // Where the main channel is now is not known: it is not faded (never raised by a guess).
        for s in r.plan.steps.dropLast() { XCTAssertFalse(s.writes.contains { $0.channel == DeskChannel(.input, 1) }) }
        XCTAssertTrue(r.plan.steps.last!.writes.contains(DeskWrite(DeskChannel(.input, 1), -32768)))
    }

    func testRejectsBadRowsAndMissingLevels() {
        XCTAssertThrowsError(try DeskPlanner.takeover(rows: [], model: .ql5, mainLevels: nil, backupLevels: nil, fade: 0, pullMainToMinusInfinity: true)) {
            XCTAssertEqual($0 as? DeskPlanError, .noRows)
        }
        XCTAssertThrowsError(try DeskPlanner.takeover(rows: [DeskRow(mainChannel: 1, backupChannel: 33)], model: .ql1, mainLevels: nil,
                                                      backupLevels: nil, fade: 0, pullMainToMinusInfinity: true)) {
            XCTAssertEqual($0 as? DeskPlanError, .invalidRows([.channelOutOfRange(row: 1, channel: DeskChannel(.input, 33), limit: 32)]))
        }
        XCTAssertThrowsError(try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: [DeskChannel(.input, 1): 0],
                                                      backupLevels: nil, fade: 0, pullMainToMinusInfinity: true)) {
            XCTAssertEqual($0 as? DeskPlanError, .missingLevel(DeskChannel(.input, 2)))
        }
        XCTAssertThrowsError(try DeskPlanner.takeover(rows: [rows[2]], model: .dm7, mainLevels: nil, backupLevels: nil, fade: 0, pullMainToMinusInfinity: true))
    }

    func testRestoreUndoesTheTakeover() throws {
        let backup: [DeskChannel: Int] = [DeskChannel(.input, 9): -32768, DeskChannel(.input, 10): -2000]
        let r = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: main, backupLevels: backup, fade: 1, pullMainToMinusInfinity: true)
        let undo = DeskPlanner.restore(r, current: nil)
        XCTAssertEqual(undo.duration, 1, accuracy: 1e-9)
        XCTAssertEqual(undo.targets, [
            DeskChannel(.input, 9): -32768, DeskChannel(.input, 10): -2000,
            DeskChannel(.stereoIn, 2): -32768,                                  // not read: assumed down before
            DeskChannel(.input, 1): -600, DeskChannel(.input, 2): -600, DeskChannel(.stereoIn, 1): -1200,
        ])
        // Fades start where the faders are now when that is read.
        let now = DeskPlanner.restore(r, current: [DeskChannel(.input, 9): -300])
        let first9 = now.steps.first!.writes.first { $0.channel == DeskChannel(.input, 9) }!.value
        XCTAssertLessThan(first9, -300)
        // Main channels not pulled: the restore leaves them alone.
        let noPull = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: main, backupLevels: nil, fade: 0, pullMainToMinusInfinity: false)
        XCTAssertEqual(Set(DeskPlanner.restore(noPull, current: nil).targets.keys), [DeskChannel(.input, 9), DeskChannel(.input, 10), DeskChannel(.stereoIn, 2)])
        // Unreadable: the main channels come back to the fixed level.
        let fixed = try DeskPlanner.takeover(rows: rows, model: .ql5, mainLevels: nil, backupLevels: nil, fade: 0, pullMainToMinusInfinity: true)
        XCTAssertEqual(DeskPlanner.restore(fixed, current: nil).targets[DeskChannel(.input, 1)], 0)
    }
}

/// A console that answers DeskLink the way the reports say a QL5 / DM7 does.
struct FakeConsole {
    var levels: [FaderAddress: Int] = [:]
    var canRead = true
    var answers = true
    /// Channels whose `set` the console ignores (to check the read-back).
    var stuck: Set<FaderAddress> = []
    var refuseSets = false
    var sent: [String] = []
    var osc: [[UInt8]] = []

    /// Answers for one batch of actions.
    mutating func answer(_ actions: [DeskLink.Action]) -> [String] {
        var out: [String] = []
        for a in actions {
            switch a {
            case let .send(line):
                sent.append(line)
                guard answers else { continue }
                let t = line.split(separator: " ").map(String.init).map { $0.trimmingCharacters(in: .newlines) }
                if t[0] == "get" {
                    guard canRead else { out.append("ERROR get UnknownAddress"); continue }
                    let addr = FaderAddress(t[1].contains("StInCh") ? .stereoIn : .input, x: Int(t[2])!)
                    out.append("OK get \(t[1]) \(t[2]) 0 \(levels[addr] ?? -32768) \"x\"")
                } else if t[0] == "set" {
                    if refuseSets { out.append("ERROR set InvalidArgument"); continue }
                    let addr = FaderAddress(t[1].contains("StInCh") ? .stereoIn : .input, x: Int(t[2])!)
                    if !stuck.contains(addr) { levels[addr] = Int(t[4])! }
                    out.append("OK set \(t[1]) \(t[2]) 0 \(levels[addr] ?? -32768) \"x\"")
                } else if t[0] == "scpmode" {
                    out.append("OK scpmode keepalive 10000")
                } else if t[0] == "devstatus" {
                    out.append("OK devstatus runmode \"normal\"")
                }
            case let .sendOSC(b):
                osc.append(b)
            default:
                break
            }
        }
        return out
    }
}

final class DeskLinkTests: XCTestCase {
    var link: DeskLink!
    var console = FakeConsole()
    var now = 100.0
    var log: [String] = []
    var closes = 0
    var opens = 0

    func settings(_ model: DeskModel = .ql5, rows: [DeskRow]? = nil) -> DeskSettings {
        var s = DeskSettings()
        s.enabled = true
        s.model = model
        s.host = "192.168.0.128"
        s.rows = rows ?? [DeskRow(mainChannel: 1, backupChannel: 9), DeskRow(mainChannel: 2, backupChannel: 10),
                          DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 2)]
        return s
    }

    /// Performs actions the way the transport does, with the fake console answering at once.
    func run(_ actions: [DeskLink.Action]) {
        var queue = actions
        while !queue.isEmpty {
            let batch = queue
            queue = []
            for a in batch {
                switch a {
                case .open: opens += 1
                case .close: closes += 1
                case let .log(m): log.append(m)
                default: break
                }
            }
            for line in console.answer(batch) { queue += link.received(line: line, now: now) }
        }
    }

    func start(_ s: DeskSettings? = nil) {
        link = DeskLink(settings: s ?? settings())
        run(link.start(now: now))
        run(link.connected(now: now))
    }

    func advance(_ seconds: Double, step: Double = 0.025) {
        let end = now + seconds
        while now < end - 1e-9 {
            now = min(end, now + step)
            run(link.tick(now: now))
        }
    }

    override func setUp() {
        console = FakeConsole()
        console.levels = [FaderAddress(.input, x: 0): -600, FaderAddress(.input, x: 1): -600,
                          FaderAddress(.stereoIn, x: 0): -1200, FaderAddress(.stereoIn, x: 1): -1200,
                          FaderAddress(.input, x: 8): -32768, FaderAddress(.input, x: 9): -32768]
        log = []; closes = 0; opens = 0; now = 100
    }

    func testConnectReadsAssignedChannelsMainFirst() {
        link = DeskLink(settings: settings())
        XCTAssertEqual(link.start(now: now).first, .open)
        XCTAssertEqual(link.status(now: now), .connecting)
        let a = link.connected(now: now)
        let lines = a.compactMap { if case let .send(l) = $0 { return l }; return nil }
        XCTAssertEqual(lines.first, DeskRCP.keepalive)
        XCTAssertEqual(Array(lines.dropFirst()), [
            DeskRCP.get(FaderAddress(.input, x: 0)), DeskRCP.get(FaderAddress(.input, x: 1)),
            DeskRCP.get(FaderAddress(.input, x: 8)), DeskRCP.get(FaderAddress(.input, x: 9)),
            DeskRCP.get(FaderAddress(.stereoIn, x: 0)), DeskRCP.get(FaderAddress(.stereoIn, x: 1)),
            DeskRCP.get(FaderAddress(.stereoIn, x: 2)), DeskRCP.get(FaderAddress(.stereoIn, x: 3)),
        ])
        XCTAssertEqual(link.status(now: now), .checking)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.checking))
        run(a)
        XCTAssertEqual(link.reading, .ok)
        XCTAssertEqual(link.status(now: now), .reading)
        XCTAssertEqual(link.channelLevel(DeskChannel(.input, 1))?.value, -600)
        XCTAssertEqual(link.readiness(now: now, automatic: true), .ready(.rcp, readLevels: true))
        let snap = link.snapshot(now: now)
        XCTAssertEqual(snap.levels[DeskChannel(.stereoIn, 1)], -1200)
        XCTAssertTrue(snap.fresh.contains(DeskChannel(.input, 2)))
        XCTAssertFalse(snap.needsLink)
    }

    func testFollowsNotifyAndPolls() {
        start()
        run(link.received(line: "NOTIFY set MIXER:Current/InCh/Fader/Level 0 0 -300 \"-3.00\"", now: now))
        XCTAssertEqual(link.channelLevel(DeskChannel(.input, 1))?.value, -300)
        console.sent = []
        advance(1.0)
        // Main channels every second; every channel every 5 s.
        XCTAssertEqual(Set(console.sent), Set([0, 1].map { DeskRCP.get(FaderAddress(.input, x: $0)) }
                                                + [0, 1].map { DeskRCP.get(FaderAddress(.stereoIn, x: $0)) }))
        console.sent = []
        advance(4.0)
        XCTAssertTrue(console.sent.contains(DeskRCP.get(FaderAddress(.input, x: 8))))
        XCTAssertTrue(console.sent.contains(DeskRCP.ping))
        XCTAssertEqual(link.status(now: now), .reading)          // polling keeps the levels fresh
    }

    func testLevelsGoStaleWhenTheConsoleStopsAnswering() {
        start()
        console.answers = false
        advance(1.9)
        XCTAssertEqual(link.status(now: now), .reading)
        advance(0.2)
        XCTAssertEqual(link.status(now: now), .stale)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.stale))
        // Questions are not piled up while unanswered.
        let gets = console.sent.filter { $0 == DeskRCP.get(FaderAddress(.input, x: 0)) }.count
        XCTAssertLessThanOrEqual(gets, 2)
        // Nothing at all for 12 s: the link is down and comes back with backoff.
        advance(10)
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(link.status(now: now), .notReachable)
        guard case let .waiting(failures, retryAt) = link.connection else { return XCTFail() }
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(retryAt, 113, accuracy: 0.03)            // silent since 100: down at 112, retry 1 s later
        advance(1.05)
        XCTAssertEqual(opens, 2)
        guard case .connecting(attempt: 2, _) = link.connection else { return XCTFail("\(link.connection)") }
    }

    func testRetryBackoffAndConnectTimeout() {
        link = DeskLink(settings: settings())
        run(link.start(now: now))
        XCTAssertEqual([1, 2, 3, 4, 5, 9].map(DeskLink.retryDelay), [1, 2, 4, 5, 5, 5])
        advance(5.0)                                            // no answer in 5 s
        guard case .waiting(failures: 1, _) = link.connection else { return XCTFail() }
        XCTAssertEqual(link.status(now: now), .notReachable)
        advance(1.0)
        run(link.connectionFailed(now: now, refused: false))
        guard case let .waiting(failures: 2, retryAt) = link.connection else { return XCTFail() }
        XCTAssertEqual(retryAt - now, 2, accuracy: 1e-9)
        XCTAssertEqual(link.connectionFailed(now: now, refused: false), [])   // already waiting
    }

    func testUnreadableConsoleUsesFixedLevels() {
        console.canRead = false
        start()
        XCTAssertEqual(link.reading, .unsupported)
        XCTAssertEqual(link.status(now: now), .fixedLevels(unconfirmed: false))
        XCTAssertEqual(link.readiness(now: now, automatic: true), .ready(.rcp, readLevels: false))   // QL: RCP set
        var s = settings(.ql5)
        s.useFixedLevels = false
        run(link.configure(s, now: now))
        XCTAssertEqual(link.status(now: now), .cannotRead)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.unreadable))
        // No polling once levels cannot be read; the ping goes on.
        console.sent = []
        advance(5)
        XCTAssertEqual(console.sent, [DeskRCP.ping])
    }

    func testNoAnswerToGetWithin3sMeansUnreadable() {
        link = DeskLink(settings: settings(.dm5, rows: [DeskRow(mainChannel: 1, backupChannel: 9)]))
        run(link.start(now: now))
        _ = link.connected(now: now)                         // the console never answers the gets
        advance(2.9)
        XCTAssertEqual(link.reading, .unknown)
        advance(0.2)
        XCTAssertEqual(link.reading, .unsupported)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .ready(.osc, readLevels: false))   // DM: OSC
    }

    func testRefusedRCPPortOnDMFallsBackToOSCButNotAutomatically() {
        link = DeskLink(settings: settings(.dm5, rows: [DeskRow(mainChannel: 1, backupChannel: 9)]))
        run(link.start(now: now))
        run(link.connectionFailed(now: now, refused: true))
        XCTAssertEqual(link.status(now: now), .fixedLevels(unconfirmed: true))
        XCTAssertEqual(link.readiness(now: now, automatic: false), .ready(.osc, readLevels: false))
        XCTAssertEqual(link.readiness(now: now, automatic: true), .notReady(.notConnected))
        advance(1.1)                                         // retrying keeps the state
        XCTAssertEqual(link.status(now: now), .fixedLevels(unconfirmed: true))
        // QL has no OSC: a refused port means the console cannot be moved.
        link = DeskLink(settings: settings(.ql1, rows: [DeskRow(mainChannel: 1, backupChannel: 9)]))
        run(link.start(now: now))
        run(link.connectionFailed(now: now, refused: true))
        XCTAssertEqual(link.status(now: now), .notReachable)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.notConnected))
    }

    func testTakeoverFadesReadsBackAndRestores() {
        start()
        let (r, a) = link.startTakeover(now: now, automatic: false)
        XCTAssertEqual(r, .ready(.rcp, readLevels: true))
        run(a)
        XCTAssertTrue(link.snapshot(now: now).move!.running)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.busy))
        advance(0.5)
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 8)], -600)        // Ch 9 up to where Ch 1 was
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 9)], -600)
        XCTAssertEqual(console.levels[FaderAddress(.stereoIn, x: 2)], -1200)    // ST IN 2, both halves
        XCTAssertEqual(console.levels[FaderAddress(.stereoIn, x: 3)], -1200)
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 0)], -32768)      // Ch 1 down to −∞
        XCTAssertEqual(console.levels[FaderAddress(.stereoIn, x: 1)], -32768)
        // Only fader levels were written.
        XCTAssertTrue(console.sent.allSatisfy { $0.hasPrefix("get ") || $0.hasPrefix("set MIXER:Current/InCh/Fader/Level ")
            || $0.hasPrefix("set MIXER:Current/StInCh/Fader/Level ") || $0 == DeskRCP.ping || $0 == DeskRCP.keepalive })
        XCTAssertEqual(link.snapshot(now: now).move?.check, .waiting)
        advance(0.4)
        XCTAssertEqual(link.snapshot(now: now).move?.check, .ok)
        XCTAssertEqual(link.readiness(now: now, automatic: true), .notReady(.alreadyMoved))
        XCTAssertTrue(link.snapshot(now: now).canRestore)
        XCTAssertTrue(link.snapshot(now: now).needsLink)
        // Taking over again does nothing (the automatic one runs once).
        let again = link.startTakeover(now: now, automatic: true)
        XCTAssertEqual(again.0, .notReady(.alreadyMoved))
        XCTAssertNil(link.refusal)

        let (rr, ra) = link.startRestore(now: now)
        XCTAssertEqual(rr, .ready(.rcp, readLevels: true))
        run(ra)
        advance(0.9)
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 0)], -600)
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 8)], -32768)
        XCTAssertEqual(console.levels[FaderAddress(.stereoIn, x: 0)], -1200)
        XCTAssertEqual(console.levels[FaderAddress(.stereoIn, x: 2)], -32768)
        XCTAssertNil(link.takeover)
        XCTAssertEqual(link.snapshot(now: now).move?.kind, .restore)
        XCTAssertEqual(link.snapshot(now: now).move?.check, .ok)
        link.dismiss()
        XCTAssertNil(link.move)
        XCTAssertFalse(link.snapshot(now: now).needsLink)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .ready(.rcp, readLevels: true))
    }

    func testInstantTakeoverIsSentRightAway() {
        var s = settings()
        s.fade = 0
        start(s)
        let (_, a) = link.startTakeover(now: now, automatic: true)
        let sets = a.compactMap { if case let .send(l) = $0, l.hasPrefix("set") { return l }; return nil }
        XCTAssertEqual(sets.count, 8)        // 3 backup + 3 main channels, the stereo ones twice
        run(a)
        XCTAssertEqual(console.levels[FaderAddress(.input, x: 9)], -600)
    }

    func testReadBackReportsMismatches() {
        start()
        console.stuck = [FaderAddress(.input, x: 9)]           // Ch 10 does not move
        run(link.startTakeover(now: now, automatic: false).1)
        advance(1.0)
        XCTAssertEqual(link.snapshot(now: now).move?.check,
                       .mismatches([DeskMismatch(channel: DeskChannel(.input, 10), expected: -600, problem: .level(-32768))]))
    }

    func testReadBackWithoutAnswers() {
        start()
        run(link.startTakeover(now: now, automatic: false).1)
        advance(0.5)
        console.answers = false
        advance(2.5)
        guard case let .mismatches(m) = link.snapshot(now: now).move?.check else { return XCTFail() }
        XCTAssertEqual(m.count, 6)
        XCTAssertTrue(m.allSatisfy { $0.problem == .noAnswer })
    }

    func testOlderPollAnswersDoNotCountAsReadBack() {
        var s = settings(rows: [DeskRow(mainChannel: 1, backupChannel: 9)])
        s.fade = 0
        start(s)
        console.answers = false
        // Ch 1 is kept fresh by hand; the 5 s poll of Ch 9 stays unanswered.
        for _ in 0..<5 {
            advance(1.0)
            run(link.received(line: "OK get MIXER:Current/InCh/Fader/Level 0 0 -600", now: now))
        }
        XCTAssertEqual(link.status(now: now), .reading)
        run(link.startTakeover(now: now, automatic: false).1)
        advance(0.325)                                               // read-back questions go out
        XCTAssertEqual(link.snapshot(now: now).move?.check, .waiting)
        run(link.received(line: "OK get MIXER:Current/InCh/Fader/Level 8 0 -32768", now: now))   // the old poll's answer
        XCTAssertEqual(link.snapshot(now: now).move?.check, .waiting)
        run(link.received(line: "OK get MIXER:Current/InCh/Fader/Level 8 0 -600", now: now))
        run(link.received(line: "OK get MIXER:Current/InCh/Fader/Level 0 0 -32768", now: now))
        XCTAssertEqual(link.snapshot(now: now).move?.check, .ok)
    }

    func testOSCTakeoverOnUnreadableDM() {
        console.canRead = false
        var s = settings(.dm3, rows: [DeskRow(mainChannel: 1, backupChannel: 9, fixedLevel: -300),
                                      DeskRow(kind: .stereoIn, mainChannel: 1, backupChannel: 1)])
        s.rows[1] = DeskRow(mainChannel: 2, backupChannel: 10)
        start(s)
        XCTAssertEqual(link.status(now: now), .fixedLevels(unconfirmed: false))
        let (r, a) = link.startTakeover(now: now, automatic: true)
        XCTAssertEqual(r, .ready(.osc, readLevels: false))
        run(a)
        advance(0.5)
        XCTAssertFalse(console.sent.contains { $0.hasPrefix("set") })         // nothing over RCP
        XCTAssertTrue(console.osc.contains(DeskOSC.message("/yosc:req/set/MIXER:Current/InCh/Fader/Level/9/1", int32: -300)))
        XCTAssertTrue(console.osc.contains(DeskOSC.message("/yosc:req/set/MIXER:Current/InCh/Fader/Level/1/1", int32: -32768)))
        XCTAssertEqual(link.snapshot(now: now).move?.check, .notPossible)
        XCTAssertFalse(link.snapshot(now: now).move!.readLevels)
    }

    func testQLWithoutReadingWritesFixedLevelsOverRCPAndReportsRefusals() {
        console.canRead = false
        console.refuseSets = true
        start(settings(.ql1, rows: [DeskRow(mainChannel: 1, backupChannel: 9)]))
        let (r, a) = link.startTakeover(now: now, automatic: false)
        XCTAssertEqual(r, .ready(.rcp, readLevels: false))
        run(a)
        advance(1)
        XCTAssertTrue(console.sent.contains(DeskRCP.set(FaderAddress(.input, x: 8), 0)))
        XCTAssertEqual(link.snapshot(now: now).move?.check,
                       .mismatches([DeskMismatch(channel: DeskChannel(.input, 1), expected: -32768, problem: .refused),
                                    DeskMismatch(channel: DeskChannel(.input, 9), expected: 0, problem: .refused)]))
    }

    func testConnectionLostMidFade() {
        var s = settings()
        s.fade = 2
        start(s)
        run(link.startTakeover(now: now, automatic: false).1)
        advance(0.5)
        run(link.connectionFailed(now: now, refused: false))
        XCTAssertEqual(link.snapshot(now: now).move?.check, .interrupted)
        XCTAssertFalse(link.snapshot(now: now).move!.running)
        XCTAssertTrue(link.snapshot(now: now).canRestore)                      // still undoable later
        XCTAssertEqual(link.startRestore(now: now).0, .notReady(.notConnected))
        XCTAssertEqual(link.refusal, DeskRefusal(reason: .notConnected, automatic: false, restore: true))
    }

    func testRefusalsAreKeptForTheWindow() {
        link = DeskLink(settings: settings())
        run(link.start(now: now))
        let (r, _) = link.startTakeover(now: now, automatic: true)
        XCTAssertEqual(r, .notReady(.notConnected))
        XCTAssertEqual(link.snapshot(now: now).refusal, DeskRefusal(reason: .notConnected, automatic: true, restore: false))
        XCTAssertTrue(link.snapshot(now: now).needsLink)
        link.dismiss()
        XCTAssertNil(link.snapshot(now: now).refusal)
        XCTAssertEqual(link.startRestore(now: now).0, .notReady(.nothingToRestore))

        var empty = settings(rows: [])
        link = DeskLink(settings: empty)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.noRows))
        empty.rows = [DeskRow(mainChannel: 1, backupChannel: 1)]
        link = DeskLink(settings: empty)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.invalidRows))
        empty.enabled = false
        link = DeskLink(settings: empty)
        XCTAssertEqual(link.readiness(now: now, automatic: false), .notReady(.off))
        XCTAssertEqual(link.startTakeover(now: now, automatic: true).0, .notReady(.off))
        XCTAssertNil(link.refusal)                             // nothing to show while the feature is off
    }

    func testErrorsForSingleChannelsAndOtherLines() {
        start()
        // The console cannot read one channel later on: that channel is no longer known.
        run(link.tick(now: now + 1.0))
        run(link.received(line: "ERROR get InvalidArgument", now: now + 1.0))
        XCTAssertEqual(link.reading, .ok)
        XCTAssertEqual(link.received(line: "OK scpmode keepalive 10000", now: now + 1.0), [])
        XCTAssertEqual(link.received(line: "ERROR scpmode UnknownCommand", now: now + 1.0), [])
        XCTAssertEqual(link.received(line: "garbage ! !", now: now + 1.0), [])
        XCTAssertEqual(link.lastHeard, now + 1.0)
        // Lines while not connected are ignored.
        run(link.connectionFailed(now: now + 1, refused: false))
        XCTAssertEqual(link.received(line: "OK get MIXER:Current/InCh/Fader/Level 0 0 0", now: now + 1), [])
        XCTAssertEqual(link.channelLevel(DeskChannel(.input, 1))?.value, -600)
    }

    func testConfigureRestartsForAnotherConsole() {
        start()
        run(link.startTakeover(now: now, automatic: false).1)
        advance(1)
        XCTAssertNotNil(link.takeover)
        var s = settings()
        s.rows.append(DeskRow(mainChannel: 3, backupChannel: 11))
        let a = link.configure(s, now: now)
        XCTAssertEqual(a, [])                                  // same console: just read the new channels
        console.sent = []
        advance(0.03)
        XCTAssertTrue(console.sent.contains(DeskRCP.get(FaderAddress(.input, x: 2))))
        XCTAssertNotNil(link.takeover)
        s.host = "192.168.0.129"
        let b = link.configure(s, now: now)
        XCTAssertEqual(b.first, .close)
        XCTAssertTrue(b.contains(.open))
        XCTAssertNil(link.takeover)                            // never undo on another console
        s.enabled = false
        XCTAssertEqual(link.configure(s, now: now), [.close])
        XCTAssertEqual(link.connection, .stopped)
    }

    func testMatchesTolerance() {
        XCTAssertTrue(DeskLink.matches(-600, -600))
        XCTAssertTrue(DeskLink.matches(-500, -600))
        XCTAssertTrue(DeskLink.matches(-700, -600))
        XCTAssertFalse(DeskLink.matches(-701, -600))
        XCTAssertTrue(DeskLink.matches(-32768, -32768))
        XCTAssertFalse(DeskLink.matches(-13800, -32768))
        XCTAssertFalse(DeskLink.matches(-32768, -13800))
    }
}
