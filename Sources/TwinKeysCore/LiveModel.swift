import Foundation

// MARK: - Commands

/// Something the iPhone asks Live to do. Sent to the main Mac, which runs it on its own Live
/// and forwards it to the backup Mac, so both Lives do the same thing.
/// Indices are 0-based. `track == -1` is the master track (volume and pan only).
/// `send` is 0 (Send A) or 1 (Send B): the track's first two sends, i.e. the first two return tracks.
public enum LiveCommand: Equatable, Sendable, Codable {
    case fireScene(Int)
    case fireClip(track: Int, scene: Int)
    case stopTrack(Int)
    case stopAll
    case play
    case stop
    case continuePlaying
    case setTempo(Double)
    case setVolume(track: Int, value: Double)
    case setPan(track: Int, value: Double)
    case setSend(track: Int, send: Int, value: Double)
    case setMute(track: Int, on: Bool)
    case setSolo(track: Int, on: Bool)
    case selectScene(Int)

    /// Continuous controls: only the latest value matters (no resend of old values).
    public var isContinuous: Bool {
        switch self {
        case .setVolume, .setPan, .setSend, .setTempo: return true
        default: return false
        }
    }

    /// Allowed while the iPhone's show lock is on (playback, scenes, clips, stops).
    public var allowedWhileLocked: Bool {
        switch self {
        case .fireScene, .fireClip, .stopTrack, .stopAll, .play, .stop, .continuePlaying, .selectScene: return true
        case .setTempo, .setVolume, .setPan, .setSend, .setMute, .setSolo: return false
        }
    }

    /// The JSON command for the Live Bridge script (see LiveBridge/README.md).
    /// `structure`: Live's track/scene layout this command was aimed at; TwinKeysBridge refuses the
    /// command ("structure_changed") when the layout has changed since, so it never hits the wrong clip.
    public func bridgeJSON(id: Int, structure: Int? = nil) -> [String: Any] {
        var d: [String: Any] = ["id": id]
        if let structure { d["structure"] = structure }
        switch self {
        case let .fireScene(s): d["cmd"] = "fire_scene"; d["scene"] = s
        case let .fireClip(t, s): d["cmd"] = "fire_clip"; d["track"] = t; d["scene"] = s
        case let .stopTrack(t): d["cmd"] = "stop_track"; d["track"] = t
        case .stopAll: d["cmd"] = "stop_all"
        case .play: d["cmd"] = "play"
        case .stop: d["cmd"] = "stop"
        case .continuePlaying: d["cmd"] = "continue"
        case let .setTempo(b): d["cmd"] = "set_tempo"; d["bpm"] = b
        case let .setVolume(t, v): d["cmd"] = "set_volume"; d["track"] = t; d["value"] = v
        case let .setPan(t, v): d["cmd"] = "set_pan"; d["track"] = t; d["value"] = v
        case let .setSend(t, k, v): d["cmd"] = "set_send"; d["track"] = t; d["send"] = k; d["value"] = v
        case let .setMute(t, on): d["cmd"] = "set_mute"; d["track"] = t; d["on"] = on
        case let .setSolo(t, on): d["cmd"] = "set_solo"; d["track"] = t; d["on"] = on
        case let .selectScene(s): d["cmd"] = "select_scene"; d["scene"] = s
        }
        return d
    }

    /// Range checks before anything is sent (values from the network are not trusted).
    public var isValid: Bool {
        func idx(_ i: Int) -> Bool { (0...9999).contains(i) }
        func unit(_ v: Double) -> Bool { v.isFinite && (0...1).contains(v) }
        switch self {
        case let .fireScene(s), let .selectScene(s): return idx(s)
        case let .fireClip(t, s): return idx(t) && idx(s)
        case let .stopTrack(t): return idx(t)
        case .stopAll, .play, .stop, .continuePlaying: return true
        case let .setTempo(b): return b.isFinite && (20...999).contains(b)
        case let .setVolume(t, v): return (t == -1 || idx(t)) && unit(v)
        case let .setPan(t, v): return (t == -1 || idx(t)) && v.isFinite && (-1...1).contains(v)
        case let .setSend(t, k, v): return idx(t) && (0...1).contains(k) && unit(v)   // the master has no sends
        case let .setMute(t, _), let .setSolo(t, _): return idx(t)
        }
    }

    // Compact binary form for the UDP link between the two Macs (packets are at most 128 bytes).
    public func encoded() -> [UInt8] {
        func i16(_ v: Int) -> [UInt8] { let u = UInt16(truncatingIfNeeded: v); return [UInt8(u >> 8), UInt8(u & 0xFF)] }
        func f64(_ v: Double) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.bigEndian) { Array($0) } }
        switch self {
        case let .fireScene(s): return [1] + i16(s)
        case let .fireClip(t, s): return [2] + i16(t) + i16(s)
        case let .stopTrack(t): return [3] + i16(t)
        case .stopAll: return [4]
        case .play: return [5]
        case .stop: return [6]
        case .continuePlaying: return [7]
        case let .setTempo(b): return [8] + f64(b)
        case let .setVolume(t, v): return [9] + i16(t) + f64(v)
        case let .setPan(t, v): return [10] + i16(t) + f64(v)
        case let .setMute(t, on): return [11] + i16(t) + [on ? 1 : 0]
        case let .setSolo(t, on): return [12] + i16(t) + [on ? 1 : 0]
        case let .selectScene(s): return [13] + i16(s)
        case let .setSend(t, k, v): return [14] + i16(t) + [UInt8(truncatingIfNeeded: k)] + f64(v)
        }
    }

    public static func decode(_ b: [UInt8]) -> LiveCommand? {
        func i16(_ i: Int) -> Int? { guard b.count >= i + 2 else { return nil }; return Int(Int16(bitPattern: UInt16(b[i]) << 8 | UInt16(b[i + 1]))) }
        func f64(_ i: Int) -> Double? {
            guard b.count >= i + 8 else { return nil }
            let u = b[i..<(i + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return Double(bitPattern: u)
        }
        guard let op = b.first else { return nil }
        let c: LiveCommand?
        switch op {
        case 1: c = i16(1).map { .fireScene($0) }
        case 2: c = i16(1).flatMap { t in i16(3).map { .fireClip(track: t, scene: $0) } }
        case 3: c = i16(1).map { .stopTrack($0) }
        case 4: c = .stopAll
        case 5: c = .play
        case 6: c = .stop
        case 7: c = .continuePlaying
        case 8: c = f64(1).map { .setTempo($0) }
        case 9: c = i16(1).flatMap { t in f64(3).map { .setVolume(track: t, value: $0) } }
        case 10: c = i16(1).flatMap { t in f64(3).map { .setPan(track: t, value: $0) } }
        case 11: c = i16(1).flatMap { t in b.count > 3 ? .setMute(track: t, on: b[3] != 0) : nil }
        case 12: c = i16(1).flatMap { t in b.count > 3 ? .setSolo(track: t, on: b[3] != 0) : nil }
        case 13: c = i16(1).map { .selectScene($0) }
        case 14: c = i16(1).flatMap { t in f64(4).map { .setSend(track: t, send: Int(b[3]), value: $0) } }
        default: c = nil
        }
        guard let c, c.isValid else { return nil }
        return c
    }
}

// MARK: - State shown on the iPhone (from the main Mac's Live)

public struct LiveSong: Codable, Equatable, Sendable {
    public var tempo: Double = 120
    public var playing = false
    public var beat = "1.1.1"
    public var selectedTrack = 0
    public var selectedScene = 0
    public var setName = ""
    /// Number of tracks and scenes in Live (the iPhone drops rows and strips that no longer exist).
    public var trackCount: Int?
    public var sceneCount: Int?
    /// Rises whenever Live's track or scene list changes (from TwinKeysBridge; nil from older scripts).
    public var structure: Int?
    public init() {}
}

public struct LiveScene: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var name: String
    public var color: String
    public var triggered: Bool
    public var playing: Bool
    public var id: Int { index }
    public init(index: Int, name: String, color: String = "#888888", triggered: Bool = false, playing: Bool = false) {
        self.index = index; self.name = name; self.color = color; self.triggered = triggered; self.playing = playing
    }
}

public struct LiveTrack: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var name: String
    public var color: String
    public var volume: Double
    public var pan: Double
    public var mute: Bool
    public var solo: Bool
    public var playingSlot: Int
    public var firedSlot: Int
    /// Send A and Send B, 0...1 (Live's first two sends). Shorter, or empty, when the set has fewer
    /// return tracks (and from older Macs and scripts).
    public var sends: [Double]
    public var id: Int { index }
    public init(index: Int, name: String, color: String = "#888888", volume: Double = 0.85, pan: Double = 0,
                mute: Bool = false, solo: Bool = false, playingSlot: Int = -1, firedSlot: Int = -1, sends: [Double] = []) {
        self.index = index; self.name = name; self.color = color; self.volume = volume; self.pan = pan
        self.mute = mute; self.solo = solo; self.playingSlot = playingSlot; self.firedSlot = firedSlot; self.sends = sends
    }

    /// As synthesized, except that `sends` may be missing (a Mac from before sends): then it is empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
        volume = try c.decode(Double.self, forKey: .volume)
        pan = try c.decode(Double.self, forKey: .pan)
        mute = try c.decode(Bool.self, forKey: .mute)
        solo = try c.decode(Bool.self, forKey: .solo)
        playingSlot = try c.decode(Int.self, forKey: .playingSlot)
        firedSlot = try c.decode(Int.self, forKey: .firedSlot)
        sends = (try? c.decodeIfPresent([Double].self, forKey: .sends)) ?? []
    }
}

public struct LiveClip: Codable, Equatable, Sendable {
    public var scene: Int
    public var hasClip: Bool
    public var name: String
    public var color: String
    public var isPlaying: Bool
    public var isTriggered: Bool
    public var lengthBeats: Double
    public init(scene: Int, hasClip: Bool, name: String = "", color: String = "#888888",
                isPlaying: Bool = false, isTriggered: Bool = false, lengthBeats: Double = 0) {
        self.scene = scene; self.hasClip = hasClip; self.name = name; self.color = color
        self.isPlaying = isPlaying; self.isTriggered = isTriggered; self.lengthBeats = lengthBeats
    }
}

/// Everything the iPhone shows about Live. Kept by the main Mac from Bridge messages and sent to
/// the iPhone as updates (`LiveUpdate`).
public struct LiveState: Codable, Equatable, Sendable {
    public var song = LiveSong()
    public var scenes: [LiveScene] = []
    public var tracks: [LiveTrack] = []
    public var master = MasterStrip()
    /// clips[track][scene]
    public var clips: [[LiveClip]] = []
    /// track -> (left, right) 0...1
    public var meters: [Int: [Double]] = [:]
    public var masterMeter: [Double] = [0, 0]
    /// track -> (position, length) in beats, for playing clips
    public var progress: [Int: [Double]] = [:]
    public init() {}

    public struct MasterStrip: Codable, Equatable, Sendable {
        public var volume: Double = 0.85
        public var pan: Double = 0
        public init() {}
    }

    /// Applies one message from the Live Bridge script (JSON object). Returns the update to send
    /// to the iPhone, or nil when the message is not understood.
    @discardableResult
    public mutating func apply(bridge m: [String: Any]) -> LiveUpdate? {
        func d(_ k: String, _ o: [String: Any]) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        func i(_ k: String, _ o: [String: Any]) -> Int? { (o[k] as? NSNumber)?.intValue }
        func b(_ k: String, _ o: [String: Any]) -> Bool { (o[k] as? NSNumber)?.boolValue ?? false }
        func s(_ k: String, _ o: [String: Any]) -> String { String((o[k] as? String ?? "").prefix(200)) }
        switch m["type"] as? String {
        case "song":
            var x = song
            x.tempo = d("tempo", m) ?? x.tempo
            x.playing = b("playing", m)
            x.beat = s("beat", m)
            x.selectedTrack = i("selected_track", m) ?? x.selectedTrack
            x.selectedScene = i("selected_scene", m) ?? x.selectedScene
            x.setName = s("set_name", m)
            if let n = i("tracks", m), n >= 0, n <= 4096 { x.trackCount = n }
            if let n = i("scenes", m), n >= 0, n <= 4096 { x.sceneCount = n }
            if let st = i("structure", m) { x.structure = st }
            song = x
            trim()
            return .song(x)
        case "scenes":
            guard let items = m["items"] as? [[String: Any]] else { return nil }
            var list: [LiveScene] = []
            for o in items {
                guard let idx = i("index", o), (0...4095).contains(idx) else { continue }
                let sc = LiveScene(index: idx, name: s("name", o), color: s("color", o), triggered: b("triggered", o), playing: b("playing", o))
                while scenes.count <= idx { scenes.append(LiveScene(index: scenes.count, name: "")) }
                scenes[idx] = sc; list.append(sc)
            }
            return .scenes(list)
        case "tracks":
            guard let items = m["items"] as? [[String: Any]] else { return nil }
            if let mo = m["master"] as? [String: Any] {
                master.volume = d("volume", mo) ?? master.volume
                master.pan = d("pan", mo) ?? master.pan
            }
            /// Send A and Send B (0...1); stops at the first entry that is not a number, so B never moves into A.
            func sends(_ o: [String: Any]) -> [Double] {
                var out: [Double] = []
                for x in (o["sends"] as? [Any] ?? []).prefix(2) {
                    guard let v = (x as? NSNumber)?.doubleValue, v.isFinite else { break }
                    out.append(min(1, max(0, v)))
                }
                return out
            }
            var list: [LiveTrack] = []
            for o in items {
                guard let idx = i("index", o), (0...4095).contains(idx) else { continue }
                let t = LiveTrack(index: idx, name: s("name", o), color: s("color", o), volume: d("volume", o) ?? 0,
                                  pan: d("pan", o) ?? 0, mute: b("mute", o), solo: b("solo", o),
                                  playingSlot: i("playing_slot", o) ?? -1, firedSlot: i("fired_slot", o) ?? -1, sends: sends(o))
                while tracks.count <= idx { tracks.append(LiveTrack(index: tracks.count, name: "")) }
                tracks[idx] = t; list.append(t)
            }
            return .tracks(list, master)
        case "clips":
            guard let t = i("track", m), (0...4095).contains(t), let items = m["items"] as? [[String: Any]] else { return nil }
            while clips.count <= t { clips.append([]) }
            var list: [LiveClip] = []
            for o in items {
                guard let sc = i("scene", o), (0...4095).contains(sc) else { continue }
                let c = LiveClip(scene: sc, hasClip: b("has_clip", o), name: s("name", o), color: s("color", o),
                                 isPlaying: b("is_playing", o), isTriggered: b("is_triggered", o), lengthBeats: d("length_beats", o) ?? 0)
                while clips[t].count <= sc { clips[t].append(LiveClip(scene: clips[t].count, hasClip: false)) }
                clips[t][sc] = c; list.append(c)
            }
            return .clips(track: t, list)
        case "meters":
            guard let items = m["items"] as? [[Any]] else { return nil }
            for row in items where row.count >= 3 {
                if let t = (row[0] as? NSNumber)?.intValue, let l = (row[1] as? NSNumber)?.doubleValue, let r = (row[2] as? NSNumber)?.doubleValue {
                    meters[t] = [l, r]
                }
            }
            if let mm = m["master"] as? [NSNumber], mm.count >= 2 { masterMeter = [mm[0].doubleValue, mm[1].doubleValue] }
            return .meters(meters, masterMeter)
        case "progress":
            guard let items = m["items"] as? [[Any]] else { return nil }
            var p: [Int: [Double]] = [:]
            for row in items where row.count >= 3 {
                if let t = (row[0] as? NSNumber)?.intValue, let pos = (row[1] as? NSNumber)?.doubleValue, let len = (row[2] as? NSNumber)?.doubleValue {
                    p[t] = [pos, len]
                }
            }
            progress = p
            return .progress(p)
        default:
            return nil
        }
    }

    /// Applies an update received from the Mac (iPhone side).
    public mutating func apply(_ u: LiveUpdate) {
        switch u {
        case let .full(s): self = s
        case let .song(x): song = x; trim()
        case let .scenes(list):
            for sc in list where sc.index >= 0 && sc.index < 4096 {
                while scenes.count <= sc.index { scenes.append(LiveScene(index: scenes.count, name: "")) }
                scenes[sc.index] = sc
            }
        case let .tracks(list, m):
            master = m
            for t in list where t.index >= 0 && t.index < 4096 {
                while tracks.count <= t.index { tracks.append(LiveTrack(index: tracks.count, name: "")) }
                tracks[t.index] = t
            }
        case let .clips(t, list):
            guard t >= 0 && t < 4096 else { return }
            while clips.count <= t { clips.append([]) }
            for c in list where c.scene >= 0 && c.scene < 4096 {
                while clips[t].count <= c.scene { clips[t].append(LiveClip(scene: clips[t].count, hasClip: false)) }
                clips[t][c.scene] = c
            }
        case let .meters(m, mm): meters = m; masterMeter = mm
        case let .progress(p): progress = p
        }
    }

    /// The whole state for an iPhone that just connected, as several updates: everything but the
    /// clips first, then one clip column per update (applying them in order rebuilds this state).
    public func initialUpdates() -> [LiveUpdate] {
        var head = self
        head.clips = []
        return [.full(head)] + clips.enumerated().map { .clips(track: $0.offset, $0.element) }
    }

    /// Drops tracks, scenes, clips, meters and progress beyond Live's current counts.
    mutating func trim() {
        if let n = song.trackCount {
            if tracks.count > n { tracks.removeLast(tracks.count - n) }
            if clips.count > n { clips.removeLast(clips.count - n) }
            meters = meters.filter { $0.key < n }
            progress = progress.filter { $0.key < n }
        }
        if let n = song.sceneCount {
            if scenes.count > n { scenes.removeLast(scenes.count - n) }
            for t in clips.indices where clips[t].count > n { clips[t].removeLast(clips[t].count - n) }
        }
    }

    /// Seconds left of the clip playing on a track (for the cue operator), or nil.
    public func secondsLeft(track: Int) -> Double? {
        guard let p = progress[track], p.count == 2, p[1] > 0, song.tempo > 0 else { return nil }
        return max(0, p[1] - p[0]) * 60 / song.tempo
    }
}

/// A change of the Live state, sent from the main Mac to the iPhone.
public enum LiveUpdate: Codable, Equatable, Sendable {
    case full(LiveState)
    case song(LiveSong)
    case scenes([LiveScene])
    case tracks([LiveTrack], LiveState.MasterStrip)
    case clips(track: Int, [LiveClip])
    case meters([Int: [Double]], [Double])
    case progress([Int: [Double]])
}

/// "-0:42" style.
public func formatTimeLeft(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.up))
    return String(format: "-%d:%02d", s / 60, s % 60)
}
