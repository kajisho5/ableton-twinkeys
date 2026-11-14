import SwiftUI
import TwinKeysCore

// MARK: - Session

/// Scenes and the clip grid. Playing clips show the time left (for the next cue).
struct SessionView: View {
    @EnvironmentObject var model: RemoteModel
    /// Landscape / wide: scenes as a column at the right edge of the grid.
    var showSceneColumn: Bool
    @State private var jump = ""

    var body: some View {
        let live = model.live
        GeometryReader { geo in
        ScrollViewReader { proxy in
            ScrollView([.vertical]) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SmallCaps("SCENES", spoken: L.s("Scenes", "シーン"))
                        Spacer()
                        TextField(L.s("Jump (number or name)", "ジャンプ（番号か名前）"), text: $jump)
                            .textFieldStyle(.plain).foregroundStyle(TK.read)
                            .padding(.horizontal, 10).frame(minHeight: 34)
                            .tkPanel(radius: 6, fill: TK.bg)
                            .frame(maxWidth: 200)
                            .onSubmit { if let i = jumpTarget() { withAnimation { proxy.scrollTo("scene-\(i)", anchor: .center) } } }
                        Toggle(isOn: $model.followSelection) {
                            Text(L.s("Follow", "追従")).font(TK.mono(.footnote)).tracking(1)
                        }
                        .toggleStyle(TKToggleKeyStyle())
                    }
                    if !showSceneColumn {
                        ForEach(live.scenes) { sc in sceneRow(sc).id("scene-\(sc.index)") }
                        stopAllButton
                        SmallCaps("CLIPS", spoken: L.s("Clips", "クリップ")).padding(.top, 6)
                    }
                    clipGrid(live, cellWidth: cellWidth(geo.size.width, tracks: live.tracks.count))
                    if showSceneColumn { stopAllButton }
                }
                .padding(12)
            }
            .onChange(of: live.song.selectedScene) { s in
                if model.followSelection { withAnimation { proxy.scrollTo("scene-\(s)", anchor: .center) } }
            }
        }
        }
    }

    /// Cells share the width (landscape fills the screen); narrow screens scroll sideways.
    private func cellWidth(_ width: CGFloat, tracks: Int) -> CGFloat {
        guard tracks > 0 else { return 96 }
        let side: CGFloat = showSceneColumn ? (Self.rowNumberWidth + Self.sceneColumnWidth + 12) : 0
        let w = (width - 24 - side - CGFloat(tracks - 1) * 6) / CGFloat(tracks)
        return min(150, max(88, w.rounded(.down)))
    }
    static let rowNumberWidth: CGFloat = 22
    static let sceneColumnWidth: CGFloat = 58

    private func jumpTarget() -> Int? {
        let q = jump.trimmingCharacters(in: .whitespaces)
        if let n = Int(q), n >= 1, n <= model.live.scenes.count { return n - 1 }
        return model.live.scenes.first { $0.name.localizedCaseInsensitiveContains(q) }?.index
    }

    private func sceneRow(_ sc: LiveScene) -> some View {
        Button { model.run(.fireScene(sc.index)) } label: {
            HStack(spacing: 12) {
                Rectangle().fill(Color(hex: sc.color)).frame(width: 4)
                Text("\(sc.index + 1)").font(TK.mono(.body)).monospacedDigit().foregroundStyle(TK.dim)
                Text(sc.name).font(.body.weight(sc.playing ? .bold : .regular)).foregroundStyle(TK.read).lineLimit(1)
                Spacer()
                if sc.playing { Text(L.s("Playing", "再生中")).font(.caption.bold()).foregroundStyle(TK.accent) }
                if sc.playing { LED(size: 6) }
                Image(systemName: "play.fill").foregroundStyle(sc.playing ? TK.accent : TK.read)
            }
            .padding(.trailing, 14)
            .frame(minHeight: 48)
            .background(sc.playing ? TK.keyTop : TK.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(sc.playing ? TK.accent : sc.index == model.live.song.selectedScene ? TK.blue : TK.stroke,
                                                                     lineWidth: sc.playing || sc.index == model.live.song.selectedScene ? 1.5 : TK.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("Scene \(sc.index + 1) \(sc.name)", "シーン \(sc.index + 1) \(sc.name)"))
    }

    /// Stops every clip; long press only.
    private var stopAllButton: some View {
        Label(L.s("Stop all clips (hold)", "全クリップ停止（長押し）"), systemImage: "stop.circle")
            .font(.footnote.bold()).foregroundStyle(TK.read)
            .frame(maxWidth: .infinity, minHeight: 44)
            .tkPanel(radius: 8)
            .onLongPressGesture(minimumDuration: 0.5) { model.run(.stopAll) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L.s("Double-tap and hold to stop every clip", "ダブルタップして長押しで全クリップを停止"))
    }

    private func clipGrid(_ live: LiveState, cellWidth cw: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if showSceneColumn { Color.clear.frame(width: Self.rowNumberWidth, height: 1) }
                    ForEach(live.tracks) { t in
                        // A1: the track's colour as a thin frame and a bar at the left, name in spaced capitals.
                        Text(t.name.uppercased()).font(TK.mono(.caption)).tracking(1).foregroundStyle(TK.read).lineLimit(1)
                            .padding(.leading, 9).padding(.trailing, 4).frame(width: cw, alignment: .leading).frame(minHeight: 22)
                            .tkPanel(radius: 4, fill: Color(tkRGB: 0x0A0A0A), stroke: Color(hex: t.color))
                            .overlay(alignment: .leading) { Color(hex: t.color).frame(width: 3) }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel(t.name)
                    }
                    if showSceneColumn {
                        Text(L.s("Scene", "シーン")).font(TK.mono(.caption2)).tracking(1).foregroundStyle(TK.dim)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(width: Self.sceneColumnWidth)
                    }
                }
                ForEach(live.scenes) { sc in
                    HStack(spacing: 6) {
                        if showSceneColumn {
                            Text(String(format: "%02d", sc.index + 1)).font(TK.mono(.caption)).monospacedDigit().foregroundStyle(TK.dim)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: Self.rowNumberWidth)
                                .accessibilityLabel("\(sc.index + 1)")
                        }
                        ForEach(live.tracks) { t in clipCell(live, t.index, sc.index, width: cw) }
                        if showSceneColumn {
                            Button { model.run(.fireScene(sc.index)) } label: {
                                Image(systemName: "play.fill").foregroundStyle(sc.playing ? TK.accent : TK.read)
                                    .frame(width: Self.sceneColumnWidth, height: 46)
                                    .tkPanel(radius: 8, fill: sc.playing ? TK.keyTop : TK.panel, stroke: sc.playing ? TK.accent : TK.stroke,
                                             lineWidth: sc.playing ? 1.5 : TK.line)
                                    .overlay(alignment: .topTrailing) { if sc.playing { LED(size: 4).padding(5) } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L.s("Scene \(sc.index + 1)", "シーン \(sc.index + 1)"))
                        }
                    }
                    .id(showSceneColumn ? "scene-\(sc.index)" : "row-\(sc.index)")
                }
                HStack(spacing: 6) {
                    if showSceneColumn { Color.clear.frame(width: Self.rowNumberWidth, height: 1) }
                    ForEach(live.tracks) { t in
                        Button { model.run(.stopTrack(t.index)) } label: {
                            Image(systemName: "square.fill").font(.caption).foregroundStyle(TK.dim).frame(width: cw, height: 32)
                                .tkPanel(radius: 6, fill: TK.bg)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.s("Stop \(t.name)", "\(t.name) を停止"))
                    }
                }
            }
        }
    }

    private func clipCell(_ live: LiveState, _ t: Int, _ s: Int, width cw: CGFloat) -> some View {
        let c = (t < live.clips.count && s < live.clips[t].count) ? live.clips[t][s] : LiveClip(scene: s, hasClip: false)
        return Button {
            model.run(c.hasClip ? .fireClip(track: t, scene: s) : .stopTrack(t))
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(c.hasClip ? TK.panel : TK.bg)
                if c.hasClip {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.name).font(.caption.bold()).foregroundStyle(TK.read).lineLimit(1)
                            Spacer(minLength: 2)
                            if c.isPlaying, let left = live.secondsLeft(track: t) {
                                Text(formatTimeLeft(left)).font(TK.mono(.caption2)).monospacedDigit().foregroundStyle(TK.accent)
                            }
                        }
                        if c.isPlaying, let p = live.progress[t], p.count == 2, p[1] > 0 {
                            SegmentMeter(value: p[0] / p[1], segments: 10).frame(height: 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    Rectangle().fill(Color(hex: c.color)).frame(height: 4).frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(TK.stroke).frame(width: 9, height: 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: cw, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(c.isPlaying ? TK.accent : (c.isTriggered ? TK.yellow : (c.hasClip ? TK.stroke : Color(tkRGB: 0x1C1C1C))),
                                                                     lineWidth: c.isPlaying || c.isTriggered ? 2 : TK.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.hasClip ? "\(c.name)\(c.isPlaying ? L.s(", playing", "、再生中") : "")" : L.s("Empty slot, stops the track", "空のスロット（トラックを停止）"))
    }
}

// MARK: - Mixer

/// The whole column is the fader: drag anywhere in it. The dashed line is 0 dB.
/// Volume, Pan, Send A and Send B are shown on the same faders (one at a time).
struct MixerView: View {
    @EnvironmentObject var model: RemoteModel
    var compact = false
    /// Landscape iPhone: the Volume / Pan / Send A / Send B buttons stand at the right of the faders.
    var sideModes = false
    enum Mode: String, CaseIterable {
        case volume, pan, sendA, sendB
        var title: String {
            switch self {
            case .volume: return L.s("Volume", "音量")
            case .pan: return L.s("Pan", "パン")
            case .sendA: return L.s("Send A", "センド A")
            case .sendB: return L.s("Send B", "センド B")
            }
        }
        /// Index in `LiveTrack.sends` (Live's first two sends), nil for volume and pan.
        var send: Int? {
            switch self {
            case .sendA: return 0
            case .sendB: return 1
            case .volume, .pan: return nil
            }
        }
    }
    @State private var mode: Mode = .volume
    /// Fader position when the current drag started (per track), and the mode it started in.
    @State private var dragStart: [Int: (mode: Mode, value: Double)] = [:]

    /// Volume and Pan always; a send only when some track has it (the set has that many return tracks).
    private var modes: [Mode] {
        Mode.allCases.filter { m in
            guard let k = m.send else { return true }
            return model.live.tracks.contains { $0.sends.count > k }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !sideModes {
                // On one line when there is room; otherwise the modes go under the title.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        mixerTitle
                        Spacer()
                        modePicker.frame(width: CGFloat(modes.count) * 90)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        mixerTitle
                        modePicker
                    }
                }
            }
            if model.mixerLocked {
                Label(L.s("Show lock: the mixer cannot be changed", "本番ロック中はミキサーを変えられません"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(TK.dim)
            }
            HStack(alignment: .top, spacing: 10) {
                GeometryReader { g in
                    let n = model.live.tracks.count + 1
                    let w = min(110, max(compact ? 58 : 66, (g.size.width - CGFloat(n - 1) * 6) / CGFloat(max(1, n))))
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(model.live.tracks) { t in strip(t.index, t.name, t.color, t.volume, t.pan, t.sends, t.mute, t.solo, model.live.meters[t.index], width: w) }
                            strip(-1, "Master", "#8E8E93", model.live.master.volume, model.live.master.pan, [], false, false, model.live.masterMeter, width: w)
                        }
                        .padding(.bottom, 4)
                        .frame(minHeight: g.size.height, alignment: .top)
                    }
                }
                if sideModes {
                    VStack(spacing: 8) {
                        ForEach(modes, id: \.self) { modeButton($0) }
                        Spacer()
                    }
                    .frame(width: 84)
                }
            }
        }
        .padding(compact ? 0 : 12)
        // The send went away (its return track was deleted in Live): show the volume again.
        .onChange(of: modes) { _, now in if !now.contains(mode) { mode = .volume } }
    }

    private var mixerTitle: some View {
        SmallCaps("MIXER", spoken: L.s("Mixer", "ミキサー"))
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(modes, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func modeButton(_ m: Mode) -> some View {
        Button { mode = m } label: {
            Text(m.title).font(TK.mono(.subheadline)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
        }
        .buttonStyle(TKButtonStyle(kind: mode == m ? .green : .plain, radius: 8, minHeight: 48))
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    /// Live's volume knob position (0.85 is 0 dB). Shown as "0 dB" there, otherwise as a percentage
    /// of the knob (the exact dB curve stays in Live).
    private func dB(_ v: Double) -> String {
        guard v > 0.001 else { return "-∞" }
        if abs(v - RemoteModel.zeroDB) < 0.005 { return "0 dB" }
        return "\(Int((v * 100).rounded()))%"
    }

    /// Where the fader stands (0...1) in the current mode, or nil when the strip has no such send
    /// (the master, or a track without it).
    private func position(_ vol: Double, _ pan: Double, _ sends: [Double]) -> Double? {
        switch mode {
        case .volume: return vol
        case .pan: return (pan + 1) / 2
        case .sendA, .sendB:
            guard let k = mode.send, k < sends.count else { return nil }
            return sends[k]
        }
    }

    /// The number above a fader. A send is shown as a percentage of its knob, like the volume.
    private func valueText(_ vol: Double, _ pan: Double, _ sends: [Double]) -> String {
        switch mode {
        case .volume: return dB(vol)
        case .pan: return String(format: "%+.0f", pan * 50)
        case .sendA, .sendB:
            guard let v = position(vol, pan, sends) else { return "–" }
            return v > 0.001 ? "\(Int((v * 100).rounded()))%" : "-∞"
        }
    }

    /// Sets the control the faders show now; `v` is the fader position 0...1.
    private func setFader(_ i: Int, _ v: Double, sends: [Double]) {
        switch mode {
        case .volume: model.run(.setVolume(track: i, value: v))
        case .pan: model.run(.setPan(track: i, value: v * 2 - 1))
        case .sendA, .sendB:
            guard let k = mode.send, i >= 0, k < sends.count else { return }
            model.run(.setSend(track: i, send: k, value: v))
        }
    }

    private func strip(_ i: Int, _ name: String, _ color: String, _ vol: Double, _ pan: Double, _ sends: [Double], _ mute: Bool, _ solo: Bool, _ meter: [Double]?, width: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(valueText(vol, pan, sends)).font(TK.mono(.caption)).monospacedDigit().foregroundStyle(TK.read)
                .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { g in
                let h = g.size.height
                let value = position(vol, pan, sends)
                // A1: a console fader (track, scale, cap) and a green-yellow-red LED meter at the right.
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ZStack(alignment: .bottom) {
                            faderScale.frame(width: 30)
                            Capsule().fill(Color(tkRGB: 0x141414)).frame(width: 6)
                            faderCap.frame(width: 30, height: Self.capHeight)
                                .offset(y: -(h - Self.capHeight) * min(1, max(0, value ?? 0)))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        SegmentMeter(value: meter?.max() ?? 0, segments: 24, vertical: true, vu: true, spacing: 2)
                            .frame(width: 9)
                    }
                    if mode == .volume {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(TK.dim)
                            .frame(height: 1).offset(y: -((h - Self.capHeight) * RemoteModel.zeroDB + Self.capHeight / 2))
                    }
                }
                .contentShape(Rectangle())
                // Moves from where the fader is (never jumps to the finger), and only for an upward or
                // downward drag, so a sideways swipe to scroll the mixer does not touch any fader.
                .gesture(DragGesture(minimumDistance: 6).onChanged { d in
                    if dragStart[i] == nil {
                        guard let value, abs(d.translation.height) > abs(d.translation.width) else { return }
                        dragStart[i] = (mode: mode, value: value)
                    }
                    // A drag that began in another mode does nothing more (it must not jump this control).
                    guard let start = dragStart[i], start.mode == mode else { return }
                    setFader(i, min(1, max(0, start.value - d.translation.height / h)), sends: sends)
                }.onEnded { _ in dragStart[i] = nil })
                .opacity(model.mixerLocked || value == nil ? 0.5 : 1)
            }
            .frame(minHeight: 120)
            if i >= 0 {
                HStack(spacing: 4) {
                    toggle("M", mute, TK.yellow) { model.run(.setMute(track: i, on: !mute)) }
                    toggle("S", solo, TK.blue) { model.run(.setSolo(track: i, on: !solo)) }
                }
            }
            // The track's colour as the frame of the name plate.
            Text(name.uppercased()).font(TK.mono(.caption2)).tracking(1).foregroundStyle(TK.read).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 20)
                .tkPanel(radius: 4, fill: TK.bg, stroke: Color(hex: color), lineWidth: 1.5)
        }
        .padding(5)
        .frame(width: width)
        .tkPanel(radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(mode.title) \(valueText(vol, pan, sends))")
        .accessibilityAdjustableAction { dir in
            let step = dir == .increment ? 0.02 : -0.02
            switch mode {
            case .pan:
                model.run(.setPan(track: i, value: min(1, max(-1, pan + step * 2))))
            case .volume:
                // Above the 0 dB cap already (set on the Mac): "up" must not pull the fader down to the cap.
                if step > 0, model.capAtZeroDB, vol >= RemoteModel.zeroDB { return }
                model.run(.setVolume(track: i, value: min(1, max(0, vol + step))))
            case .sendA, .sendB:
                guard let v = position(vol, pan, sends) else { return }
                setFader(i, min(1, max(0, v + step)), sends: sends)
            }
        }
    }

    private static let capHeight: CGFloat = 20

    /// Scale marks beside the fader track (decoration).
    private var faderScale: some View {
        VStack(spacing: 0) {
            ForEach(0..<11, id: \.self) { k in
                if k > 0 { Spacer(minLength: 0) }
                HStack(spacing: 0) {
                    Rectangle().frame(width: 6, height: 1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, Self.capHeight / 2)
        .foregroundStyle(Color(tkRGB: 0x333333))
        .accessibilityHidden(true)
    }

    /// The fader cap: dark key with a white line.
    private var faderCap: some View {
        RoundedRectangle(cornerRadius: 4).fill(TK.cap)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(TK.capLine, lineWidth: TK.line))
            .overlay(Rectangle().fill(TK.read).frame(height: 2).padding(.horizontal, 4))
            .accessibilityHidden(true)
    }

    private func toggle(_ label: String, _ on: Bool, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(TK.mono(.subheadline)).frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? color : TK.read)
                .tkPanel(radius: 6, fill: on ? color.opacity(0.18) : TK.panel, stroke: on ? color : TK.stroke, lineWidth: on ? 1.5 : TK.line)
        }
        .buttonStyle(.plain)
        .disabled(model.mixerLocked)
    }
}

// MARK: - Cues and status

struct CuesView: View {
    @EnvironmentObject var model: RemoteModel
    var compact = false

    var body: some View {
        GeometryReader { geo in
        let cols = compact ? 4 : (geo.size.width > 640 ? 4 : 3)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                lastCue
                SmallCaps("CUE KEYS", spoken: L.s("Cue keys", "キューのキー"))
                let keys = model.status?.cueKeys ?? []
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(keys) { k in
                        Button { model.cue(k.keycode) } label: { cueButton(k) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(k.memo.isEmpty ? k.label : "\(k.memo), \(k.label)")
                    }
                }
                if keys.contains(where: { $0.memo.isEmpty }) || !compact {
                    VStack(alignment: .leading, spacing: 4) {
                        if keys.contains(where: { $0.memo.isEmpty }) {
                            Label(L.s("Keys without a memo: write one in the Mac's Settings > Cue Keys and it shows here.",
                                      "メモのないキーは、Mac の「設定」>「キューのキー」でメモを書くと、何をするかがここに出ます。"),
                                  systemImage: "info.circle")
                        }
                        if !compact {
                            Text(L.s("A button does what that key does on the Mac. What moves in Live depends on your MIDI Map.",
                                     "押すと、Mac でそのキーを押したのと同じ。何が動くかは Live の MIDI マップで決まります。"))
                        }
                    }
                    .font(.caption).foregroundStyle(TK.dim)
                }
                if !compact {
                    Button(action: model.allNotesOff) {
                        VStack(spacing: 4) {
                            Text("ALL NOTES OFF").font(.system(.title2, design: .monospaced, weight: .heavy)).tracking(3)
                                .foregroundStyle(TK.red).lineLimit(1).minimumScaleFactor(0.5)
                                .accessibilityHidden(true)
                            Text(L.s("All Notes Off (both Macs)", "オールノートオフ（2台とも）")).font(.headline).foregroundStyle(TK.redSoft)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(NotesOffBackground(radius: 12, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    SmallCaps("MACS")
                    macs
                }
            }
            .padding(compact ? 0 : 12)
        }
        }
    }

    /// What the key does (its memo) first; the key itself small. Keys without a memo show the key large.
    @ViewBuilder private func cueButton(_ k: RemoteStatus.CueKeySummary) -> some View {
        VStack(alignment: k.memo.isEmpty ? .center : .leading, spacing: 5) {
            if k.memo.isEmpty {
                Text(k.label).font(TK.mono(.title2)).foregroundStyle(TK.read).lineLimit(1).minimumScaleFactor(0.6)
                if !compact { Text(L.s("No memo", "メモなし")).font(.caption2).foregroundStyle(TK.dim) }
            } else {
                Text(k.memo).font(compact ? .subheadline.bold() : .headline).foregroundStyle(TK.read).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(k.label).font(TK.mono(.caption)).foregroundStyle(TK.dim).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .tkPanel(radius: 4, fill: TK.bg)
                    if !compact { Text(L.s("key", "キー")).font(.caption2).foregroundStyle(TK.dim) }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 52 : 68, alignment: k.memo.isEmpty ? .center : .leading)
        .tkPanel(radius: 8)
    }

    private var lastCue: some View {
        let c = model.status?.lastCue
        return HStack(spacing: 12) {
            Text(c?.label ?? "–").font(TK.mono(.title)).foregroundStyle(TK.read).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 60, height: 50)
                .tkPanel(radius: 8, fill: TK.bg)
            VStack(alignment: .leading, spacing: 2) {
                SmallCaps("LAST CUE", spoken: L.s("Last cue", "直前のキュー"))
                Text(c.map { $0.memo.isEmpty ? $0.label : $0.memo } ?? L.s("No cue yet", "まだありません")).font(.headline).foregroundStyle(TK.read).lineLimit(1)
                if let c { Text(L.s("\(c.label) key · cue \(c.count) since connecting", "\(c.label) キー ・ 接続してから \(c.count) 回目")).font(.caption).foregroundStyle(TK.dim) }
            }
            Spacer()
            if let d = c?.delivery {
                Image(systemName: d == "delivered" ? "checkmark.circle.fill" : d == "missing" ? "exclamationmark.circle.fill" : "circle.dotted")
                    .font(.title2).foregroundStyle(d == "delivered" ? TK.accent : d == "missing" ? TK.red : TK.dim)
                    .shadow(color: d == "delivered" ? TK.accent.opacity(0.5) : .clear, radius: 4)
                    .accessibilityLabel(d == "delivered" ? L.s("Reached the backup", "バックアップに届きました")
                                        : d == "missing" ? L.s("No confirmation", "届いた確認がありません") : d)
            }
        }
        .padding(12)
        .tkPanel(radius: 10, stroke: c?.delivery == "missing" ? TK.red : TK.stroke, lineWidth: c?.delivery == "missing" ? 1.5 : TK.line)
    }

    private var macs: some View {
        let st = model.status
        return VStack(alignment: .leading, spacing: 10) {
            row(L.s("Main Mac", "メインの Mac"), st?.mainName ?? "—", st?.mainLiveConnected == true ? L.s("Live connected", "Live 接続済み") : L.s("Live not connected", "Live 未接続"), st?.mainLiveConnected == true)
            row(L.s("Backup Mac", "バックアップの Mac"), st?.backupName ?? "—",
                st?.backupLinked != true ? L.s("Not linked", "未接続")
                    : st?.backupLiveConnected == true ? L.s("Linked · Live ✓", "接続済み・Live ✓") : L.s("Linked · Live ✗ no answer", "接続済み・Live ✗ 応答なし"),
                st?.backupLinked == true && st?.backupLiveConnected == true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tkPanel(radius: 10)
    }

    private func row(_ title: String, _ name: String, _ detail: String, _ ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LED(color: ok ? TK.accent : TK.yellow, size: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TK.mono(.subheadline)).foregroundStyle(TK.read)
                Text("\(name) · \(detail)").font(.caption).foregroundStyle(TK.dim)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

struct SettingsPane: View {
    @EnvironmentObject var model: RemoteModel
    /// Set by the Apple Watch mark in the top bar: scroll to "Connection" (once).
    var showConnection: Binding<Bool> = .constant(false)

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { scrollToConnection(proxy) }
                .onChange(of: showConnection.wrappedValue) { _, _ in scrollToConnection(proxy) }
        }
    }

    private func scrollToConnection(_ proxy: ScrollViewProxy) {
        guard showConnection.wrappedValue else { return }
        showConnection.wrappedValue = false
        // On the next turn: the form has its rows by then.
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(Self.connectionID, anchor: .top) } }
    }

    private static let connectionID = "connection"

    private var form: some View {
        Form {
            if model.trialMode {
                Section {
                    Button(L.s("End the sample and connect to a Mac", "サンプルを終わって Mac につなぐ")) { model.endTrial() }
                } footer: {
                    Text(L.s("You are looking at made-up data. Nothing is sent to a Mac.", "架空のデータを表示しています。Mac には何も送っていません。"))
                }
                .listRowBackground(TK.panel)
            }
            Section(L.s("Show safety", "本番の安全")) {
                // Turning the lock off only with the 1 s hold on the lock button.
                Toggle(L.s("Show lock", "本番ロック"), isOn: $model.locked).disabled(model.locked)
                Toggle(L.s("Faders stop at 0 dB", "フェーダーの上限を 0dB にする"), isOn: $model.capAtZeroDB)
                Toggle(L.s("Follow the selection in Live", "Live の選択に追従"), isOn: $model.followSelection)
            }
            .listRowBackground(TK.panel)
            Section {
                lockToggle(.tempo, L.s("Tempo", "テンポ"))
                lockToggle(.mixer, L.s("Mixer (volume, pan, sends, M/S)", "ミキサー（音量・パン・センド・M/S）"))
                lockToggle(.launches, L.s("Clip and scene launches", "クリップ・シーンの再生"),
                           note: L.s("When on, only GO and the cues are left", "オンにすると GO とキューだけになります"))
                lockToggle(.stops, L.s("Stop and Stop all clips", "停止・全クリップ停止"))
                lockToggle(.cues, L.s("Cue buttons", "キューのボタン"))
            } header: {
                Text(L.s("What the show lock stops", "本番ロックで止めるもの"))
            } footer: {
                Text(L.s("All Notes Off and unlocking (1 s hold) are never stopped. Change these while the lock is off.",
                         "全ノートオフと「ロックの解除（1 秒長押し）」は止めません。ロック中は変えられません。"))
            }
            .listRowBackground(TK.panel)
            connectionSection
            Section(L.s("About", "このアプリについて")) {
                Link(L.s("Privacy policy", "プライバシーポリシー"), destination: Self.site(L.ja ? "ja/privacy/" : "privacy/"))
                Link(L.s("Help and support", "使い方・サポート"), destination: Self.site(L.ja ? "ja/support/" : "support/"))
                Text(L.s("TwinKeys Remote by Shogo Kajiyama / SEVENTHWELL. Unofficial tool, not affiliated with Ableton.",
                         "TwinKeys Remote（制作 Shogo Kajiyama / SEVENTHWELL）。非公式のツールで、Ableton 社とは関係ありません。"))
                    .font(.footnote).foregroundStyle(TK.dim)
            }
            .listRowBackground(TK.panel)
        }
        // A1: black behind the rows, near-black rows (as the other panes).
        .scrollContentBackground(.hidden)
        .background(TK.bg)
    }

    // MARK: Connection (docs/design-links.md)

    private var connectionSection: some View {
        Section(L.s("Connection", "接続")) {
            linkRow("desktopcomputer", L.s("Mac (main)", "Mac（メイン）"), model.status?.mainName ?? "—", mainState)
                .id(Self.connectionID)
            linkRow("desktopcomputer", L.s("Backup", "バックアップ"), model.status?.backupName ?? model.backupMacName ?? "—", backupState)
            if model.qlabOn, let q = model.qlabStatus {
                linkRow("list.bullet.rectangle", "QLab", "\(q.workspaceName ?? "—")（\(model.status?.mainName ?? "Mac")）",
                        q.state.canControl ? (text: connectedText, color: Color.tkOK) : (text: L.s("Not connected", "つながっていません"), color: Color.tkWarn))
            }
            linkRow("applewatch", "Apple Watch", L.s("TwinKeys (Watch)", "TwinKeys（Watch）"), watchState)
            linkRow("iphone", L.s("Pairing code", "合言葉"), model.pairingCode, nil)
            Button(L.s("Connect to another Mac (for example the backup)", "別の Mac につなぐ（バックアップなど）")) { model.chooseAnotherMac() }
                .disabled(model.locked)
        }
        .listRowBackground(TK.panel)
    }

    private typealias LinkState = (text: String, color: Color)

    private var connectedText: String { "✓ " + L.s("Connected", "つながっています") }

    private var mainState: LinkState {
        if model.isConnected { return (text: connectedText, color: Color.tkOK) }
        return (text: L.s("Not connected", "つながっていません"), color: Color.tkDanger)
    }

    /// As the top bar: the backup's link and its own Live.
    private var backupState: LinkState? {
        guard model.isConnected, let st = model.status else { return nil }
        guard st.backupLinked else { return (text: L.s("Backup not linked", "バックアップ未接続"), color: Color.tkWarn) }
        guard st.backupLiveConnected else { return (text: L.s("Live ✗ no answer", "Live ✗ 応答なし"), color: Color.tkWarn) }
        let ms = st.latencyMs.map { " · \(Int($0.rounded())) ms" } ?? ""
        return (text: "✓ Live ✓" + ms, color: Color.tkOK)
    }

    private var watchState: LinkState {
        guard let w = model.watch, w.paired else { return (text: L.s("Not paired", "ペアリングされていません"), color: TK.dim) }
        guard w.appInstalled else {
            return (text: L.s("Not installed (install it from the Watch app)", "入っていません（Watch の App で入れられます）"), color: TK.dim)
        }
        guard w.reachable else {
            return (text: L.s("Not reachable (open TwinKeys on the watch)", "届きません（Watch で TwinKeys を開いてください）"), color: Color.tkWarn)
        }
        return (text: connectedText, color: Color.tkOK)
    }

    private func linkRow(_ symbol: String, _ title: String, _ detail: String, _ state: LinkState?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(TK.dim)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(TK.read)
                Text(detail).font(.caption).foregroundStyle(TK.dim).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let state {
                Text(state.text)
                    .font(.subheadline.bold())
                    .foregroundStyle(state.color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func site(_ path: String) -> URL {
        URL(string: "https://kajisho5.github.io/ableton-twinkeys/" + path)!
    }

    private func lockToggle(_ part: LockScope, _ title: String, note: String? = nil) -> some View {
        Toggle(isOn: Binding(get: { model.lockScope.contains(part) },
                             set: { on in if on { model.lockScope.insert(part) } else { model.lockScope.remove(part) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(TK.dim) }
            }
        }
        .disabled(model.locked)
    }
}
