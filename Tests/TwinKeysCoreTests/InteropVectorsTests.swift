import Crypto
import Foundation
import XCTest
@testable import TwinKeysCore

/// Shared test vectors for the Windows version (docs/design-windows.md 6.6).
///
/// The files in `shared/test-vectors/` hold fixed inputs and the bytes this Mac code makes from
/// them. The Windows code (windows/tests/TwinKeys.Interop.Tests) reads the same files and must
/// produce the same bytes, so the two can talk to each other.
///
/// - Normally this test checks that the committed files still match what the Swift code makes
///   (a change to the wire format makes CI fail here, and then on the Windows side).
/// - With `TWINKEYS_WRITE_VECTORS=1` it writes the files instead:
///   `TWINKEYS_WRITE_VECTORS=1 swift test --filter InteropVectorsTests`
///
/// Every value here is made up (the pairing code K7MQ2-WX9TP is the CI test code, not a real one).
final class InteropVectorsTests: XCTestCase {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/test-vectors", isDirectory: true)

    static let instanceID = UUID(uuidString: "8F0C2B7E-4D3A-4B8E-9C11-2A6F5E0D9B34")!
    static let nonceA: [UInt8] = (0..<16).map { UInt8(0x10 + $0) }
    static let nonceB: [UInt8] = (0..<16).map { UInt8(0xA0 + $0) }
    static let code = "K7MQ2-WX9TP"

    // MARK: Helpers

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    static func keyBytes(_ k: SymmetricKey) -> [UInt8] { k.withUnsafeBytes { Array($0) } }

    static func describe(_ c: LiveCommand) -> [String: Any] {
        switch c {
        case let .fireScene(s): return ["op": "fireScene", "scene": s]
        case let .fireClip(t, s): return ["op": "fireClip", "track": t, "scene": s]
        case let .stopTrack(t): return ["op": "stopTrack", "track": t]
        case .stopAll: return ["op": "stopAll"]
        case .play: return ["op": "play"]
        case .stop: return ["op": "stop"]
        case .continuePlaying: return ["op": "continuePlaying"]
        case let .setTempo(b): return ["op": "setTempo", "bpm": b]
        case let .setVolume(t, v): return ["op": "setVolume", "track": t, "value": v]
        case let .setPan(t, v): return ["op": "setPan", "track": t, "value": v]
        case let .setSend(t, k, v): return ["op": "setSend", "track": t, "send": k, "value": v]
        case let .setMute(t, on): return ["op": "setMute", "track": t, "on": on]
        case let .setSolo(t, on): return ["op": "setSolo", "track": t, "on": on]
        case let .selectScene(s): return ["op": "selectScene", "scene": s]
        }
    }

    /// The packet body as plain JSON values (64-bit numbers as decimal strings).
    static func describe(_ body: PacketBody) -> [String: Any] {
        switch body {
        case let .hello(id, nonce, name):
            return ["type": "hello", "instance_id": id.uuidString, "nonce": hex(nonce), "name": name]
        case let .helloAck(id, nonce, name):
            return ["type": "helloAck", "instance_id": id.uuidString, "nonce": hex(nonce), "name": name]
        case .bye: return ["type": "bye"]
        case let .noteOn(ch, note, vel): return ["type": "noteOn", "channel": Int(ch), "note": Int(note), "velocity": Int(vel)]
        case let .noteOff(ch, note): return ["type": "noteOff", "channel": Int(ch), "note": Int(note)]
        case .allNotesOff: return ["type": "allNotesOff"]
        case let .heartbeat(t): return ["type": "heartbeat", "timestamp_nanos": String(t)]
        case let .heartbeatAck(t): return ["type": "heartbeatAck", "timestamp_nanos": String(t)]
        case let .held(ch, notes): return ["type": "held", "channel": Int(ch), "notes": notes.map { Int($0) }]
        case let .features(flags, epoch):
            var d: [String: Any] = ["type": "features", "flags": Int(flags)]
            if let epoch { d["epoch"] = Int(epoch) }
            return d
        case let .noteAck(seq): return ["type": "noteAck", "seq": Int(seq)]
        case let .cueName(ch, note, label, memo):
            return ["type": "cueName", "channel": Int(ch), "note": Int(note), "label": label, "memo": memo]
        case let .cueResend(orig, ch, note, vel, released):
            return ["type": "cueResend", "original_seq": Int(orig), "channel": Int(ch), "note": Int(note),
                    "velocity": Int(vel), "released": released]
        case let .cueCount(seq, count): return ["type": "cueCount", "seq": Int(seq), "count": Int(count)]
        case let .liveCommand(id, c): return ["type": "liveCommand", "id": Int(id), "command": describe(c)]
        case let .liveAck(id): return ["type": "liveAck", "id": Int(id)]
        case let .liveStatus(on): return ["type": "liveStatus", "connected": on]
        case let .setSummary(t, s, h): return ["type": "setSummary", "tracks": Int(t), "scenes": Int(s), "hash": Int(h)]
        case let .setItem(kind, index, name): return ["type": "setItem", "kind": Int(kind), "index": Int(index), "name": name]
        case let .liveResult(id, code): return ["type": "liveResult", "id": Int(id), "code": Int(code)]
        case let .roleClaim(ms): return ["type": "roleClaim", "millis": String(ms)]
        case .roleHandover: return ["type": "roleHandover"]
        case let .remoteSummary(phones, watch): return ["type": "remoteSummary", "phones": Int(phones), "watch": Int(watch)]
        case .desk: return ["type": "desk"]
        case let .qlabCommand(id, c):
            var d: [String: Any] = ["type": "qlabCommand", "id": Int(id), "action": Int(c.action.rawValue)]
            if let n = c.cueNumber { d["cue"] = n }
            if let e = c.expect { d["expect"] = e }
            return d
        case let .qlabResult(id, code): return ["type": "qlabResult", "id": Int(id), "code": Int(code)]
        case let .qlabState(st):
            var d: [String: Any] = ["type": "qlabState", "state": Int(st.state.rawValue), "permissions": Int(st.permissions.rawValue),
                                    "show_mode": st.showMode, "follow": st.follow, "target": st.target.rawValue, "running": st.running,
                                    "cues": st.cueCount, "list_hash": Int(st.listHash), "keys_hash": Int(st.keysHash)]
            if let ph = st.playhead { d["playhead"] = ph }
            return d
        case let .qlabItem(index, number, type, name):
            return ["type": "qlabItem", "index": Int(index), "number": number, "cue_type": Int(type), "name": name]
        }
    }

    // MARK: QLab mode (docs/design-qlab.md 6.2, 9 phase 3)

    /// OSC messages as TwinKeys sends them to QLab, and SLIP frames.
    static let oscCases: [(String, OSCMessage)] = [
        ("go", OSCMessage("/workspace/WS-1/go")),
        ("connect_passcode", OSCMessage("/workspace/WS-1/connect", [.string("1234")])),
        ("always_reply", OSCMessage("/workspace/WS-1/alwaysReply", [.int(1)])),
        ("values_for_keys", OSCMessage("/workspace/WS-1/cue_id/C-12/valuesForKeys", [.string("[\"currentDuration\"]")])),
        ("float_and_bools", OSCMessage("/test", [.float(1.5), .bool(true), .bool(false), .int(-2)])),
        ("reply", OSCMessage("/reply/workspace/WS-1/go", [.string("{\"status\":\"ok\"}")])),
    ]

    static let qlabPacketCases: [(name: String, session: UInt32, seq: UInt32, body: PacketBody)] = [
        ("qlabCommand_go", 1, 30, .qlabCommand(id: 7, QLabCommand(action: .go, expect: "13"))),
        ("qlabCommand_goCue", 1, 31, .qlabCommand(id: 8, QLabCommand(action: .goCue, cueNumber: "90"))),
        ("qlabCommand_panic", 1, 32, .qlabCommand(id: 9, QLabCommand(action: .panic))),
        ("qlabResult_corrected", 2, 30, .qlabResult(id: 7, code: QLabResultCode.corrected.rawValue)),
        ("qlabState", 2, 31, .qlabState(QLabLinkState(state: .ready, permissions: [.view, .control], showMode: true, follow: true,
                                                       target: .qlab, running: 2, cueCount: 48, listHash: 0xCAFE_BABE,
                                                       keysHash: 0x0102_0304, playhead: "13"))),
        ("qlabState_no_playhead", 2, 32, .qlabState(QLabLinkState(state: .connecting, target: .both))),
        ("qlabItem", 2, 33, .qlabItem(index: 11, number: "12", type: QLabCueType.audio.rawValue, name: "雨の音（遠く）")),
        ("qlabItem_long_name_cut", 2, 34, .qlabItem(index: 300, number: "1.5", type: QLabCueType.group.rawValue, name: String(repeating: "雷", count: 40))),
    ]

    static func describe(_ a: OSCArgument) -> [String: Any] {
        switch a {
        case let .string(s): return ["type": "s", "value": s]
        case let .int(i): return ["type": "i", "value": Int(i)]
        case let .float(f): return ["type": "f", "value": Double(f)]
        case let .bool(b): return ["type": b ? "T" : "F"]
        case let .blob(b): return ["type": "b", "value": hex(b)]
        }
    }

    static func qlabFile() -> [String: Any] {
        let slipCases: [(String, [UInt8])] = [
            ("plain", [0x2F, 0x67, 0x6F, 0x00]),
            ("escapes_end_and_esc", [0x01, 0xC0, 0x02, 0xDB, 0x03]),
            ("only_specials", [0xC0, 0xC0, 0xDB]),
        ]
        return [
            "about": "QLab mode (docs/design-qlab.md): OSC messages and SLIP frames TwinKeys sends to QLab, and the Mac-to-Mac packets 0x23-0x26. TwinKeys for Windows does not drive QLab: it must reject every packet here as unknownType (and so drop it), and accept features with the QLab bit (4) set. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "osc": oscCases.map { c -> [String: Any] in
                ["name": c.0, "address": c.1.address, "args": c.1.arguments.map(describe), "bytes": hex(c.1.encoded()),
                 "slip": hex(SLIP.encode(c.1.encoded()))]
            },
            "slip": slipCases.map { ["name": $0.0, "packet": hex($0.1), "framed": hex(SLIP.encode($0.1))] },
            "packets": qlabPacketCases.map { c -> [String: Any] in
                let bytes = Packet(session: c.session, seq: c.seq, body: c.body).encode()
                return ["name": c.name, "session": Int(c.session), "seq": Int(c.seq), "body": describe(c.body),
                        "bytes": hex(bytes), "size": bytes.count, "windows_error": "unknownType"]
            },
            "features_with_qlab": ["bytes": hex(Packet(session: 1, seq: 40, body: .features(flags: 1 | Conductor.qlabFeature, epoch: 7)).encode()),
                                   "flags": Int(1 | Conductor.qlabFeature), "epoch": 7],
        ]
    }

    static func errorName(_ bytes: [UInt8]) -> String {
        do {
            _ = try Packet.decode(bytes)
            return "none"
        } catch let e as DecodeError {
            switch e {
            case .tooShort: return "tooShort"
            case .badMagic: return "badMagic"
            case .unsupportedVersion: return "unsupportedVersion"
            case .unknownType: return "unknownType"
            case .badPayload: return "badPayload"
            }
        } catch {
            return "other"
        }
    }

    // MARK: Inputs (the Windows tests read these from the JSON files)

    static let packetCases: [(name: String, session: UInt32, seq: UInt32, body: PacketBody)] = [
        ("hello", 0x0102_0304, 1, .hello(instanceID: instanceID, nonce: nonceA, name: "Stage PC")),
        ("helloAck", 0xA1B2_C3D4, 2, .helloAck(instanceID: instanceID, nonce: nonceB, name: "Backup Stage Mac")),
        ("hello_empty_name", 3, 4, .hello(instanceID: instanceID, nonce: nonceA, name: "")),
        ("hello_long_cjk_name_cut_on_character", 5, 6, .hello(instanceID: instanceID, nonce: nonceA, name: String(repeating: "鍵", count: 20))),
        ("hello_emoji_cut_on_grapheme_cluster", 5, 7, .hello(instanceID: instanceID, nonce: nonceA, name: "Stage PC " + String(repeating: "👍🏽", count: 3))),
        ("bye", 7, 8, .bye),
        ("noteOn", 1, 2, .noteOn(channel: 0, note: 60, velocity: 100)),
        ("noteOn_max_values", 0xFFFF_FFFF, 0xFFFF_FFFF, .noteOn(channel: 15, note: 127, velocity: 127)),
        ("noteOff", 1, 3, .noteOff(channel: 0, note: 37)),
        ("allNotesOff", 1, 4, .allNotesOff),
        ("heartbeat", 1, 5, .heartbeat(timestampNanos: 0x0123_4567_89AB_CDEF)),
        ("heartbeatAck", 2, 9, .heartbeatAck(timestampNanos: UInt64.max)),
        ("held", 1, 6, .held(channel: 0, notes: [36, 37, 40])),
        ("held_empty", 1, 7, .held(channel: 3, notes: [])),
        ("features_1_0_0_without_epoch", 1, 8, .features(flags: 3)),
        ("features", 1, 9, .features(flags: 1, epoch: 200)),
        ("noteAck", 2, 10, .noteAck(seq: 0xDEAD_BEEF)),
        ("cueName", 1, 10, .cueName(channel: 0, note: 37, label: "↓", memo: "次のシーン")),
        ("cueName_long_texts_cut", 1, 11, .cueName(channel: 0, note: 38, label: String(repeating: "あ", count: 20), memo: String(repeating: "い", count: 40))),
        ("cueResend_released", 1, 12, .cueResend(originalSeq: 41, channel: 0, note: 37, velocity: 127, released: true)),
        ("cueResend_still_held", 1, 13, .cueResend(originalSeq: 42, channel: 0, note: 36, velocity: 127, released: false)),
        ("cueCount", 1, 14, .cueCount(seq: 41, count: 12)),
        ("liveCommand", 1, 15, .liveCommand(id: 9, .fireClip(track: 2, scene: 5))),
        ("liveAck", 2, 11, .liveAck(id: 9)),
        ("liveStatus", 2, 12, .liveStatus(connected: true)),
        ("setSummary", 2, 13, .setSummary(tracks: 12, scenes: 300, hash: 0xCAFE_BABE)),
        ("setItem", 2, 14, .setItem(kind: 1, index: 299, name: "Finale")),
        ("liveResult", 2, 15, .liveResult(id: 9, code: 2)),
        ("roleClaim", 1, 16, .roleClaim(millis: 1_763_100_000_000)),
        ("roleHandover", 1, 17, .roleHandover),
        ("remoteSummary", 1, 18, .remoteSummary(phones: 1, watch: 2)),
    ]

    static let badPackets: [(name: String, bytes: [UInt8])] = {
        func h(_ type: UInt8) -> [UInt8] { [0x54, 0x4B, 2, type, 0, 0, 0, 1, 0, 0, 0, 2] }
        let ones = [UInt8](repeating: 1, count: 32)
        var list: [(name: String, bytes: [UInt8])] = []
        list.append(("too_short", [0x54, 0x4B, 2]))
        list.append(("header_only_11_bytes", [0x54, 0x4B, 2, 0x20, 0, 0, 0, 1, 0, 0, 0]))
        list.append(("bad_magic", [0x00, 0x4B, 2, 0x20, 0, 0, 0, 0, 0, 0, 0, 0]))
        list.append(("version_1", [0x54, 0x4B, 1, 0x20, 0, 0, 0, 0, 0, 0, 0, 0]))
        list.append(("unknown_type", h(0x77)))
        list.append(("noteOn_note_200", h(0x10) + [0, 200, 100]))
        list.append(("noteOn_channel_16", h(0x10) + [16, 60, 100]))
        list.append(("noteOn_velocity_128", h(0x10) + [0, 60, 128]))
        list.append(("noteOn_cut_short", h(0x10) + [0, 60]))
        list.append(("noteOff_note_128", h(0x11) + [0, 128]))
        list.append(("heartbeat_cut_short", h(0x30) + [1, 2]))
        list.append(("hello_cut_short", h(0x01) + ones))
        list.append(("hello_name_longer_than_32", h(0x01) + ones + [33] + [UInt8](repeating: 0x41, count: 33)))
        list.append(("hello_name_missing_bytes", h(0x02) + ones + [10, 0x41, 0x42]))
        list.append(("held_33_notes", h(0x12) + [0, 33] + [UInt8](repeating: 60, count: 33)))
        list.append(("held_note_out_of_range", h(0x12) + [0, 2, 60, 130]))
        list.append(("held_count_more_than_sent", h(0x12) + [0, 3, 60]))
        list.append(("features_empty", h(0x13)))
        list.append(("noteAck_cut_short", h(0x14) + [0, 0, 1]))
        list.append(("cueName_label_13_bytes", h(0x15) + [0, 37, 13] + [UInt8](repeating: 0x41, count: 13) + [0]))
        list.append(("cueName_memo_61_bytes", h(0x15) + [0, 37, 1, 0x41, 61] + [UInt8](repeating: 0x41, count: 61)))
        list.append(("cueResend_cut_short", h(0x16) + [0, 0, 0, 1, 0, 37, 127]))
        list.append(("cueCount_cut_short", h(0x17) + [0, 0, 0, 1, 0, 0, 0]))
        list.append(("liveCommand_scene_out_of_range", h(0x18) + [0, 0, 0, 1, 1, 0x27, 0x10]))
        list.append(("liveCommand_unknown_op", h(0x18) + [0, 0, 0, 1, 99]))
        list.append(("setItem_kind_2", h(0x1C) + [2, 0, 1, 1, 0x41]))
        list.append(("roleClaim_cut_short", h(0x1E) + [0, 0, 0, 0, 0, 0, 1]))
        list.append(("remoteSummary_cut_short", h(0x21) + [1]))
        return list
    }()

    static let liveCommands: [LiveCommand] = [
        .fireScene(3), .fireClip(track: 2, scene: 5), .stopTrack(1), .stopAll, .play, .stop, .continuePlaying,
        .setTempo(128.5), .setVolume(track: -1, value: 0.85), .setPan(track: 4, value: -0.5),
        .setMute(track: 2, on: true), .setSolo(track: 3, on: false), .selectScene(7), .setSend(track: 4, send: 1, value: 0.25),
    ]

    static let badLiveCommands: [(name: String, bytes: [UInt8])] = {
        func f64(_ v: Double) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.bigEndian) { Array($0) } }
        var list: [(name: String, bytes: [UInt8])] = []
        list.append(("empty", []))
        list.append(("unknown_op", [99]))
        list.append(("fireScene_cut_short", [1, 0]))
        list.append(("fireScene_10000", [1, 0x27, 0x10]))
        list.append(("fireScene_negative", [1, 0xFF, 0xFF]))
        list.append(("setTempo_too_slow", [8] + f64(10)))
        list.append(("setVolume_above_1", [9, 0, 1] + f64(1.5)))
        list.append(("setSend_send_2", [14, 0, 4, 2] + f64(0.5)))
        list.append(("setSend_cut_short", [14, 0, 4, 1, 0, 0]))
        list.append(("setMute_cut_short", [11, 0, 2]))
        return list
    }()

    struct Step {
        var session: UInt32, seq: UInt32, allowLate: Bool
        init(_ session: UInt32, _ seq: UInt32, late: Bool = false) { self.session = session; self.seq = seq; allowLate = late }
    }

    static let sequenceCases: [(name: String, steps: [Step])] = [
        ("duplicates_and_reordered_notes", [Step(7, 10), Step(7, 10), Step(7, 12), Step(7, 11), Step(7, 13)]),
        ("wrap_around", [Step(1, UInt32.max - 1), Step(1, UInt32.max), Step(1, 0), Step(1, 1), Step(1, UInt32.max)]),
        ("restart_drops_old_session", [Step(1, 10), Step(2, 5), Step(1, 11), Step(2, 5), Step(2, 6)]),
        ("new_session_starts_over", [Step(1, 500), Step(2, 0), Step(2, 1)]),
        ("late_order_free_packets_once", [Step(1, 10), Step(1, 12), Step(1, 11), Step(1, 11, late: true), Step(1, 11, late: true),
                                          Step(1, 12, late: true), Step(1, 200), Step(1, 100, late: true), Step(1, 199, late: true),
                                          Step(1, 136, late: true), Step(1, 135, late: true)]),
        ("jump_of_64_or_more_forgets_the_window", [Step(1, 1), Step(1, 2), Step(1, 70), Step(1, 2, late: true), Step(1, 69, late: true), Step(1, 6, late: true)]),
        ("only_8_retired_sessions_are_kept", [Step(1, 1), Step(2, 1), Step(3, 1), Step(4, 1), Step(5, 1), Step(6, 1), Step(7, 1),
                                              Step(8, 1), Step(9, 1), Step(10, 1), Step(1, 5), Step(3, 5), Step(10, 2)]),
    ]

    // MARK: Building the files

    static func pairingFile() -> [String: Any] {
        let rfc: [(String, String, Int, Int)] = [("passwd", "salt", 1, 64), ("Password", "NaCl", 80000, 64)]
        let codes = [code, " k7mq2 wx9tp ", "K7MQ2\u{2010}WX9TP", "K7MQ2\u{FF0D}WX9TP", "Z3H8N-RT4QW", "K7MQ2-WX9T", "K7MQ2-WX9T0", "K7MQ2-WX9TPX", "k7mq2-wx9tl"]
        return [
            "about": "Pairing code -> key K (PBKDF2-HMAC-SHA256, salt \"TwinKeys pairing v2\", 100000 rounds, 32 bytes) -> fingerprint. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "salt": "TwinKeys pairing v2",
            "iterations": Pairing.iterations,
            "alphabet": String(Pairing.alphabet),
            "pbkdf2_rfc7914": rfc.map { r -> [String: Any] in
                ["password": r.0, "salt": r.1, "iterations": r.2, "length": r.3,
                 "key": hex(Pairing.pbkdf2(password: Array(r.0.utf8), salt: Array(r.1.utf8), iterations: r.2, length: r.3))]
            },
            "codes": codes.map { c -> [String: Any] in
                guard let n = Pairing.normalize(c), let secret = PairingSecret(code: c) else {
                    return ["input": c, "valid": false]
                }
                return ["input": c, "valid": true, "normalized": n, "formatted": Pairing.formatted(n),
                        "key": hex(keyBytes(secret.key)), "fingerprint": secret.fingerprint]
            },
        ]
    }

    static func packetsFile() -> [String: Any] {
        [
            "about": "Plain packet bytes (before sealing) for fixed inputs, and bytes that must be dropped. 64-bit numbers are decimal strings. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "protocol_version": Int(WireProtocol.version),
            "max_packet_size": WireProtocol.maxPacketSize,
            "packets": packetCases.map { c -> [String: Any] in
                let bytes = Packet(session: c.session, seq: c.seq, body: c.body).encode()
                var d: [String: Any] = ["name": c.name, "session": Int(c.session), "seq": Int(c.seq),
                                        "body": describe(c.body), "bytes": hex(bytes)]
                // What the receiver gets back (names cut to their byte limit).
                if let back = try? Packet.decode(bytes) { d["decoded"] = describe(back.body) }
                return d
            },
            "bad_packets": badPackets.map { ["name": $0.name, "bytes": hex($0.bytes), "error": errorName($0.bytes)] as [String: Any] },
        ]
    }

    static func secureFile() -> [String: Any] {
        let secret = PairingSecret(code: code)!
        let k = keyBytes(secret.key)
        let a = SecureChannel(secret: secret, myNonce: nonceA)
        let b = SecureChannel(secret: secret, myNonce: nonceB)
        func dirKey(_ from: [UInt8], _ to: [UInt8]) -> [UInt8] {
            Array(HMAC<SHA256>.authenticationCode(for: Array("dir".utf8) + from + to, using: secret.key))
        }
        let sealedCases: [(name: String, sender: String, session: UInt32, seq: UInt32, body: PacketBody)] = [
            ("hello_from_a", "a", 0x0102_0304, 1, .hello(instanceID: instanceID, nonce: nonceA, name: "Stage PC")),
            ("helloAck_from_b", "b", 0x0A0B_0C0D, 1, .helloAck(instanceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, nonce: nonceB, name: "Backup Stage Mac")),
            ("noteOn_a_to_b", "a", 0x0102_0304, 2, .noteOn(channel: 0, note: 36, velocity: 127)),
            ("cueCount_a_to_b", "a", 0x0102_0304, 3, .cueCount(seq: 2, count: 1)),
            ("noteOff_a_to_b", "a", 0x0102_0304, 4, .noteOff(channel: 0, note: 36)),
            ("heartbeat_a_to_b", "a", 0x0102_0304, 5, .heartbeat(timestampNanos: 1_000_000_000)),
            ("held_a_to_b", "a", 0x0102_0304, 6, .held(channel: 0, notes: [37])),
            ("features_a_to_b", "a", 0x0102_0304, 7, .features(flags: 3, epoch: 1)),
            ("cueName_a_to_b", "a", 0x0102_0304, 8, .cueName(channel: 0, note: 37, label: "↓", memo: "次のシーン")),
            ("allNotesOff_a_to_b", "a", 0x0102_0304, 9, .allNotesOff),
            ("roleClaim_a_to_b", "a", 0x0102_0304, 10, .roleClaim(millis: 1_763_100_000_000)),
            ("bye_a_to_b", "a", 0x0102_0304, 11, .bye),
            ("noteAck_b_to_a", "b", 0x0A0B_0C0D, 2, .noteAck(seq: 2)),
            ("heartbeatAck_b_to_a", "b", 0x0A0B_0C0D, 3, .heartbeatAck(timestampNanos: 1_000_000_000)),
            ("cueResend_a_to_b_seq_max", "a", 0x0102_0304, 0xFFFF_FFFF, .cueResend(originalSeq: 2, channel: 0, note: 36, velocity: 127, released: true)),
        ]
        return [
            "about": "Signing (hello, helloAck: HMAC-SHA256 under K, first 16 bytes) and sealing (ChaCha20-Poly1305 under HMAC(K, \"dir\" + sender nonce + receiver nonce); nonce = header bytes 4..11 + 00000000; AAD = 12-byte header). Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "code": code,
            "key": hex(k),
            "fingerprint": secret.fingerprint,
            "nonce_a": hex(nonceA),
            "nonce_b": hex(nonceB),
            "direction_key_a_to_b": hex(dirKey(nonceA, nonceB)),
            "direction_key_b_to_a": hex(dirKey(nonceB, nonceA)),
            "sealed": sealedCases.map { c -> [String: Any] in
                let p = Packet(session: c.session, seq: c.seq, body: c.body)
                let (from, to) = c.sender == "a" ? (a, b) : (b, a)
                let sealed = from.seal(p, peerNonce: to.myNonce)!
                return ["name": c.name, "sender": c.sender, "session": Int(c.session), "seq": Int(c.seq),
                        "body": describe(c.body), "plain": hex(p.encode()), "sealed": hex(sealed)]
            },
        ]
    }

    static func hkdfFile() -> [String: Any] {
        let secret = PairingSecret(code: code)!
        let cases: [(name: String, ikm: [UInt8], salt: [UInt8], info: [UInt8], length: Int)] = [
            ("rfc5869_case_1", [UInt8](repeating: 0x0B, count: 22), (0...12).map { UInt8($0) }, (0xF0...0xF9).map { UInt8($0) }, 42),
            ("twinkeys_remote_shape", (0..<32).map { UInt8($0 * 3 & 0xFF) }, keyBytes(secret.key),
             Array("TwinKeys remote v1".utf8) + Array(SHA256.hash(data: Array("{}{}".utf8))), 64),
        ]
        return [
            "about": "HKDF-SHA256 (used by the iPhone link, phase 3). Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "hkdf_sha256": cases.map { c -> [String: Any] in
                let okm = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: c.ikm), salt: c.salt, info: c.info, outputByteCount: c.length)
                return ["name": c.name, "ikm": hex(c.ikm), "salt": hex(c.salt), "info": hex(c.info), "length": c.length, "okm": hex(keyBytes(okm))]
            },
        ]
    }

    static func sequenceFile() -> [String: Any] {
        [
            "about": "SequenceFilter: (session, seq, allow_late) in order and whether each is accepted. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "cases": sequenceCases.map { c -> [String: Any] in
                var f = SequenceFilter()
                return ["name": c.name, "steps": c.steps.map { s -> [String: Any] in
                    let ok = f.accept(session: s.session, seq: s.seq, allowLate: s.allowLate)
                    return ["session": Int(s.session), "seq": Int(s.seq), "allow_late": s.allowLate, "accepted": ok]
                }]
            },
        ]
    }

    static func liveCommandFile() -> [String: Any] {
        [
            "about": "LiveCommand binary form (packet 0x18) and the TwinKeysBridge JSON (phase 2). Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "commands": liveCommands.map { c -> [String: Any] in
                ["command": describe(c), "bytes": hex(c.encoded()), "valid": c.isValid, "continuous": c.isContinuous,
                 "bridge": c.bridgeJSON(id: 7)]
            },
            "bad": badLiveCommands.map { ["name": $0.name, "bytes": hex($0.bytes), "decodes": LiveCommand.decode($0.bytes) != nil] as [String: Any] },
        ]
    }

    /// Phase 2 of the Windows version: the set check (names cut to 60 UTF-8 bytes, FNV-1a hash).
    static let setCheckCases: [(name: String, tracks: [String], scenes: [String])] = [
        ("empty", [], []),
        ("simple", ["Music", "SE"], ["1 Intro", "2 Main"]),
        ("japanese", ["音楽", "効果音", "FX"], ["1 オープニング", "2 本編", "3 カーテンコール"]),
        ("empty_names", ["", ""], [""]),
        ("long_names_cut", [String(repeating: "あ", count: 40), String(repeating: "a", count: 59) + "é", String(repeating: "b", count: 60)],
         [String(repeating: "c", count: 61)]),
        ("tracks_only", ["Click", "Guide", "Band"], []),
    ]

    static func setCheckFile() -> [String: Any] {
        [
            "about": "Set check (2.1): track and scene names cut to 60 UTF-8 bytes, and the FNV-1a hash sent in setSummary. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "cases": setCheckCases.map { c -> [String: Any] in
                let s = SetSummary(tracks: c.tracks, scenes: c.scenes)
                return ["name": c.name, "tracks": c.tracks, "scenes": c.scenes,
                        "cut_tracks": s.tracks, "cut_scenes": s.scenes, "hash": Int(s.hash)]
            },
        ]
    }

    // MARK: remote.json (phase 3 of the Windows version: the iPhone link)

    static let devicePrivate: [UInt8] = (0..<32).map { UInt8(0x40 + $0) }
    static let ephemeralPrivate: [UInt8] = (0..<32).map { UInt8(0x60 + $0) }
    static let remoteNonceClient: [UInt8] = (1...16).map { UInt8($0) }
    static let remoteNonceServer: [UInt8] = (0..<16).map { UInt8(0x81 + $0) }

    static func remoteMessages() -> [(String, RemoteMessage)] {
        var song = LiveSong()
        song.tempo = 124.5; song.playing = true; song.beat = "17.3.1"; song.selectedTrack = 1; song.selectedScene = 2
        song.setName = ""; song.trackCount = 2; song.sceneCount = 3; song.structure = 42; song.bridgeVersion = 3
        let scenes = [LiveScene(index: 0, name: "1 Intro", color: "#FF3A34", triggered: false, playing: true),
                      LiveScene(index: 1, name: "2 本編", color: "#888888", triggered: true, playing: false)]
        let tracks = [LiveTrack(index: 0, name: "Music", color: "#1A2B3C", volume: 0.75, pan: 0, mute: false, solo: false,
                                playingSlot: 0, firedSlot: -1, sends: [0.5, 0.25]),
                      LiveTrack(index: 1, name: "SE", color: "#888888", volume: 0.5, pan: -0.25, mute: true, solo: false,
                                playingSlot: -1, firedSlot: -1, sends: [])]
        var master = LiveState.MasterStrip(); master.volume = 0.75; master.pan = 0
        let clips = [LiveClip(scene: 0, hasClip: true, name: "Opening", color: "#FFA500", isPlaying: true, isTriggered: false, lengthBeats: 16),
                     LiveClip(scene: 1, hasClip: false, name: "", color: "#888888", isPlaying: false, isTriggered: false, lengthBeats: 0)]
        var state = LiveState()
        state.song = song; state.scenes = scenes; state.tracks = tracks; state.master = master
        state.clips = [clips, []]; state.meters = [0: [0.5, 0.25]]; state.masterMeter = [0.75, 0.5]; state.progress = [0: [4, 16]]
        let diff = SetDiff(mainTracks: 2, backupTracks: 1, mainScenes: 3, backupScenes: 3, differences: 2,
                           rows: [.init(kind: "track", index: 1, main: "SE", backup: nil), .init(kind: "scene", index: 1, main: "2 本編", backup: "2 Main")],
                           complete: true)
        let status = RemoteStatus(mainName: "Stage PC", mainLiveConnected: true, backupName: "Backup Stage Mac", backupLinked: true,
                                  backupLiveConnected: false, latencyMs: 1.5,
                                  lastCue: .init(label: "↓", memo: "次のシーン", count: 12, delivery: "delivered"),
                                  cueKeys: [.init(keycode: 336, label: "↓", memo: "次のシーン"), .init(keycode: 328, label: "↑", memo: "")],
                                  setDiff: diff)
        let minimal = RemoteStatus(mainName: "Stage PC", mainLiveConnected: false, backupName: nil, backupLinked: false,
                                   backupLiveConnected: false, latencyMs: nil, lastCue: nil, cueKeys: [])
        return [
            ("command", .command(id: 1, .fireScene(3))),
            ("command_fireClip", .command(id: 2, .fireClip(track: 1, scene: 2))),
            ("commandAt", .commandAt(id: 3, .setVolume(track: -1, value: 0.5), structure: 42)),
            ("commandAt_no_structure", .commandAt(id: 4, .stopAll, structure: nil)),
            ("commandAt_setSend", .commandAt(id: 5, .setSend(track: 2, send: 1, value: 0.25), structure: 7)),
            ("command_setMute", .command(id: 6, .setMute(track: 0, on: true))),
            ("command_setTempo", .command(id: 7, .setTempo(128.5))),
            ("command_continuePlaying", .command(id: 8, .continuePlaying)),
            ("go", .go(id: 9, scene: 4, structure: 42)),
            ("lockScope", .lockScope(on: true, scope: 19)),
            ("becomeMain", .becomeMain(id: 10)),
            ("cue", .cue(id: 11, keycode: 336)),
            ("allNotesOff", .allNotesOff(id: 12)),
            ("ping", .ping(12.5, watch: nil)),
            ("ping_watch", .ping(13.25, watch: RemoteWatchState(paired: true, appInstalled: true, reachable: false))),
            ("lock", .lock(true)),
            ("waitingForApproval", .waitingForApproval(code: "0427")),
            ("welcome", .welcome(macName: "Stage PC", features: RemoteFeature.all)),
            ("denied", .denied),
            ("result", .result(id: 1, ok: true, error: nil, backup: "delivered")),
            ("result_error", .result(id: 2, ok: false, error: "structure_changed", backup: "notSent")),
            ("pong", .pong(12.5)),
            ("update_song", .update(.song(song))),
            ("update_scenes", .update(.scenes(scenes))),
            ("update_tracks", .update(.tracks(tracks, master))),
            ("update_clips", .update(.clips(track: 0, clips))),
            ("update_meters", .update(.meters([0: [0.5, 0.25], 3: [0.125, 0]], [0.75, 0.5]))),
            ("update_progress", .update(.progress([1: [4, 16]]))),
            ("update_full", .update(.full(state))),
            ("status", .status(status)),
            ("status_minimal", .status(minimal)),
        ]
    }

    static func remoteFile() -> [String: Any] {
        let secret = PairingSecret(code: code)!
        let k = keyBytes(secret.key)
        let dev = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: devicePrivate)
        let eph = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ephemeralPrivate)
        let shared = try! eph.sharedSecretFromKeyAgreement(with: dev.publicKey).withUnsafeBytes { Array($0) }
        let devPub = Array(dev.publicKey.rawRepresentation), ephPub = Array(eph.publicKey.rawRepresentation)
        let ch = "{\"version\":1,\"deviceID\":\"5B0E7C1A-2D4F-4E8B-9A36-7C1D2E3F4A5B\",\"deviceName\":\"Stage iPhone\",\"devicePublicKey\":\"\(Data(devPub).base64EncodedString())\",\"nonce\":\"\(Data(remoteNonceClient).base64EncodedString())\"}"
        let sh = "{\"version\":1,\"serverID\":\"8F0C2B7E-4D3A-4B8E-9C11-2A6F5E0D9B34\",\"serverName\":\"Stage PC\",\"ephemeralPublicKey\":\"\(Data(ephPub).base64EncodedString())\",\"nonce\":\"\(Data(remoteNonceServer).base64EncodedString())\"}"
        let chb = Array(ch.utf8), shb = Array(sh.utf8)
        func tag(_ d: [UInt8]) -> [UInt8] { Array(HMAC<SHA256>.authenticationCode(for: Array("remote".utf8) + d, using: secret.key)) }
        let info = Array("TwinKeys remote v1".utf8) + Array(SHA256.hash(data: chb + shb))
        let km = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: shared), salt: k, info: info, outputByteCount: 64)
        let kmb = keyBytes(km)
        let c2s = Array(kmb[0..<32]), s2c = Array(kmb[32..<64])
        func seal(_ key: [UInt8], _ counter: UInt64, _ plain: String) -> [UInt8] {
            let n = RemoteSession.nonce(counter)
            let box = try! ChaChaPoly.seal(Array(plain.utf8), using: SymmetricKey(data: key), nonce: ChaChaPoly.Nonce(data: n))
            return RemoteSession.frame(Array(n.prefix(8)) + Array(box.ciphertext) + Array(box.tag))
        }
        let sealed: [(String, String, UInt64, String)] = [
            ("ping_from_iphone", "c2s", 1, "{\"ping\":{\"_0\":12.5}}"),
            ("command_from_iphone", "c2s", 2, "{\"command\":{\"id\":1,\"_1\":{\"fireScene\":{\"_0\":3}}}}"),
            ("welcome_to_iphone", "s2c", 1, "{\"welcome\":{\"macName\":\"Stage PC\",\"features\":[\"commandAt\",\"go\",\"lockScope\",\"becomeMain\",\"skipsUnknown\"]}}"),
            ("pong_to_iphone", "s2c", 2, "{\"pong\":{\"_0\":12.5}}"),
        ]
        return [
            "about": "TwinKeys Remote (iPhone link, phase 3): X25519 with fixed keys, the hellos, tags, HKDF session keys, the 4-digit code, sealed frames, and every message as Swift's JSONEncoder writes it. Written by Tests/TwinKeysCoreTests/InteropVectorsTests.swift.",
            "pairing_code": code,
            "device_private": hex(devicePrivate), "device_public": hex(devPub),
            "ephemeral_private": hex(ephemeralPrivate), "ephemeral_public": hex(ephPub),
            "shared": hex(shared), "client_hello_json": ch, "server_hello_json": sh,
            "client_hello_frame": hex(RemoteSession.frame(chb + tag(chb))),
            "server_hello_frame": hex(RemoteSession.frame(shb + tag(chb + shb))),
            "client_tag": hex(tag(chb)), "server_tag": hex(tag(chb + shb)), "info": hex(info),
            "key_c2s": hex(c2s), "key_s2c": hex(s2c), "confirm_code": RemoteSession.confirmCode(chb),
            "sealed": sealed.map { s -> [String: Any] in
                ["name": s.0, "direction": s.1, "counter": Int(s.2), "plain": s.3, "frame": hex(seal(s.1 == "c2s" ? c2s : s2c, s.2, s.3))]
            },
            "messages": remoteMessages().map { m -> [String: Any] in
                let obj = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(m.1))
                return ["name": m.0, "message": obj]
            },
        ]
    }

    static var files: [(String, () -> [String: Any])] {
        [("pairing.json", pairingFile), ("packets.json", packetsFile), ("secure.json", secureFile),
         ("hkdf.json", hkdfFile), ("sequence.json", sequenceFile), ("livecommand.json", liveCommandFile),
         ("setcheck.json", setCheckFile), ("remote.json", remoteFile), ("qlab.json", qlabFile)]
    }

    // MARK: Compare or write

    static func canonical(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: ["v": v], options: [.sortedKeys]) else { return "<not JSON>" }
        return String(decoding: d, as: UTF8.self)
    }

    /// The first difference between the committed value and the Swift one, as "path: …".
    static func difference(_ committed: Any, _ swift: Any, _ path: String) -> String? {
        if let x = committed as? [String: Any], let y = swift as? [String: Any] {
            for k in Set(x.keys).union(y.keys).sorted() {
                guard let xv = x[k] else { return "\(path).\(k): not in the committed file" }
                guard let yv = y[k] else { return "\(path).\(k): no longer made by the Swift code" }
                if let d = difference(xv, yv, "\(path).\(k)") { return d }
            }
            return nil
        }
        if let x = committed as? [Any], let y = swift as? [Any] {
            guard x.count == y.count else { return "\(path): \(x.count) entries committed, \(y.count) made by Swift" }
            for i in x.indices {
                if let d = difference(x[i], y[i], "\(path)[\(i)]") { return d }
            }
            return nil
        }
        let a = canonical(committed), b = canonical(swift)
        return a == b ? nil : "\(path): committed \(a), Swift \(b)"
    }

    func testSharedVectorsMatchTheSwiftCode() throws {
        let write = ProcessInfo.processInfo.environment["TWINKEYS_WRITE_VECTORS"] == "1"
        if write {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        }
        for (name, make) in Self.files {
            let made = make()
            let url = Self.directory.appendingPathComponent(name)
            if write {
                var data = try JSONSerialization.data(withJSONObject: made, options: [.prettyPrinted, .sortedKeys])
                data.append(0x0A)
                try data.write(to: url)
                print("Wrote \(url.path)")
                continue
            }
            let committedData = try Data(contentsOf: url)
            let committed = try JSONSerialization.jsonObject(with: committedData)
            if let d = Self.difference(committed, made, name) {
                XCTFail("shared/test-vectors/\(d). If the wire format changed on purpose, run TWINKEYS_WRITE_VECTORS=1 swift test --filter InteropVectorsTests and update the Windows code too.")
            }
        }
    }

    /// The sealed vectors also open again with the receiver's channel (sanity check of the inputs).
    /// The committed remote hellos are accepted by the Mac's own server session, and its messages decode back.
    func testRemoteVectorsWorkWithTheMacSession() throws {
        let url = Self.directory.appendingPathComponent("remote.json")
        guard let f = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { return XCTFail("remote.json") }
        let server = RemoteSession(serverWith: PairingSecret(code: Self.code)!)
        let frame = try XCTUnwrap(f["client_hello_frame"] as? String)
        let bytes = stride(from: 0, to: frame.count, by: 2).map { i -> UInt8 in
            let a = frame.index(frame.startIndex, offsetBy: i)
            return UInt8(frame[a..<frame.index(a, offsetBy: 2)], radix: 16)!
        }
        let events = try server.receive(bytes)
        guard case let .clientHello(hello, code)? = events.first else { return XCTFail("no client hello") }
        XCTAssertEqual(code, f["confirm_code"] as? String)
        XCTAssertEqual(hello.deviceName, "Stage iPhone")
        for (name, m) in Self.remoteMessages() {
            let committed = try XCTUnwrap((f["messages"] as? [[String: Any]])?.first { $0["name"] as? String == name }?["message"], name)
            let back = try JSONDecoder().decode(RemoteMessage.self, from: JSONSerialization.data(withJSONObject: committed))
            XCTAssertEqual(back, m, name)
        }
    }

    /// The QLab packets decode back on the Mac and fit a sealed packet.
    func testQLabPacketsRoundTrip() throws {
        for c in Self.qlabPacketCases {
            let p = Packet(session: c.session, seq: c.seq, body: c.body)
            // Long texts are cut when encoded: decoding and encoding again gives the same bytes.
            XCTAssertEqual(try Packet.decode(p.encode()).encode(), p.encode(), c.name)
            XCTAssertLessThanOrEqual(p.encode().count + SecureChannel.tagSize, WireProtocol.maxPacketSize, c.name)
        }
        for c in Self.oscCases { XCTAssertEqual(OSCMessage.decode(c.1.encoded()), c.1, c.0) }
    }

    func testSealedVectorsOpen() throws {
        let secret = PairingSecret(code: Self.code)!
        let a = SecureChannel(secret: secret, myNonce: Self.nonceA)
        let b = SecureChannel(secret: secret, myNonce: Self.nonceB)
        let p = Packet(session: 9, seq: 9, body: .noteOn(channel: 0, note: 36, velocity: 127))
        let sealed = try XCTUnwrap(a.seal(p, peerNonce: Self.nonceB))
        XCTAssertEqual(try b.open(sealed, peerNonce: Self.nonceA), p)
        XCTAssertLessThanOrEqual(sealed.count, WireProtocol.maxPacketSize)
    }
}
