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
                        Text(L.s("Scenes", "シーン")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        TextField(L.s("Jump (number or name)", "ジャンプ（番号か名前）"), text: $jump)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                            .onSubmit { if let i = jumpTarget() { withAnimation { proxy.scrollTo("scene-\(i)", anchor: .center) } } }
                        Toggle(L.s("Follow", "追従"), isOn: $model.followSelection).toggleStyle(.button).font(.footnote)
                    }
                    if !showSceneColumn {
                        ForEach(live.scenes) { sc in sceneRow(sc).id("scene-\(sc.index)") }
                        stopAllButton
                        Text(L.s("Clips", "クリップ")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
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
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: sc.color)).frame(width: 6)
                Text("\(sc.index + 1)  \(sc.name)").font(.body.weight(sc.playing ? .bold : .regular)).lineLimit(1)
                Spacer()
                if sc.playing { Text(L.s("Playing", "再生中")).font(.caption.bold()).foregroundStyle(Color.tkOK) }
                Image(systemName: "play.fill").foregroundStyle(sc.playing ? Color.tkOK : .secondary)
            }
            .padding(.trailing, 14)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tkCard))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(sc.playing || sc.index == model.live.song.selectedScene ? Color.tkAccent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("Scene \(sc.index + 1) \(sc.name)", "シーン \(sc.index + 1) \(sc.name)"))
    }

    /// Stops every clip; long press only.
    private var stopAllButton: some View {
        Label(L.s("Stop all clips (hold)", "全クリップ停止（長押し）"), systemImage: "stop.circle")
            .font(.footnote.bold())
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tkCell))
            .onLongPressGesture(minimumDuration: 0.5) { model.run(.stopAll) }
            .accessibilityAction { model.run(.stopAll) }
    }

    private func clipGrid(_ live: LiveState, cellWidth cw: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if showSceneColumn { Color.clear.frame(width: Self.rowNumberWidth, height: 1) }
                    ForEach(live.tracks) { t in
                        Text(t.name).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
                            .padding(.horizontal, 6).frame(width: cw, height: 22, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: t.color)))
                    }
                    if showSceneColumn { Text(L.s("Scene", "シーン")).font(.caption.bold()).foregroundStyle(.secondary).frame(width: Self.sceneColumnWidth) }
                }
                ForEach(live.scenes) { sc in
                    HStack(spacing: 6) {
                        if showSceneColumn {
                            Text("\(sc.index + 1)").font(.caption.bold()).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: Self.rowNumberWidth)
                        }
                        ForEach(live.tracks) { t in clipCell(live, t.index, sc.index, width: cw) }
                        if showSceneColumn {
                            Button { model.run(.fireScene(sc.index)) } label: {
                                Image(systemName: "play.fill").foregroundStyle(sc.playing ? .white : .primary)
                                    .frame(width: Self.sceneColumnWidth, height: 46)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(sc.playing ? Color.tkOK : Color.tkCard))
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
                            Image(systemName: "square.fill").font(.caption).frame(width: cw, height: 32)
                                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.4)))
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
                RoundedRectangle(cornerRadius: 8).fill(c.hasClip ? Color.tkCard : Color.tkBG)
                if c.hasClip {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.name).font(.caption.bold()).lineLimit(1)
                            Spacer(minLength: 2)
                            if c.isPlaying, let left = live.secondsLeft(track: t) {
                                Text(formatTimeLeft(left)).font(.caption2.bold()).monospacedDigit().foregroundStyle(Color.tkOK)
                            }
                        }
                        if c.isPlaying, let p = live.progress[t], p.count == 2, p[1] > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tkCell)
                                    Capsule().fill(Color.tkOK).frame(width: g.size.width * min(1, p[0] / p[1]))
                                }
                            }
                            .frame(height: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    Rectangle().fill(Color(hex: c.color)).frame(height: 4).frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.6)).frame(width: 9, height: 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: cw, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(c.isPlaying ? Color.tkOK : (c.isTriggered ? Color.tkWarn : Color.secondary.opacity(c.hasClip ? 0 : 0.3)), lineWidth: c.isPlaying || c.isTriggered ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.hasClip ? "\(c.name)\(c.isPlaying ? L.s(", playing", "、再生中") : "")" : L.s("Empty slot, stops the track", "空のスロット（トラックを停止）"))
    }
}

// MARK: - Mixer

/// The whole column is the fader: drag anywhere in it. The dashed line is 0 dB.
struct MixerView: View {
    @EnvironmentObject var model: RemoteModel
    var compact = false
    /// Landscape iPhone: the Volume / Pan buttons stand at the right of the faders.
    var sideModes = false
    enum Mode: String, CaseIterable { case volume, pan }
    @State private var mode: Mode = .volume

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !sideModes {
                HStack {
                    Text(L.s("Mixer", "ミキサー")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $mode) {
                        Text(L.s("Volume", "音量")).tag(Mode.volume)
                        Text(L.s("Pan", "パン")).tag(Mode.pan)
                    }
                    .pickerStyle(.segmented).frame(width: 180)
                }
            }
            if model.locked {
                Label(L.s("Show lock: the mixer cannot be changed", "本番ロック中はミキサーを変えられません"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                GeometryReader { g in
                    let n = model.live.tracks.count + 1
                    let w = min(110, max(compact ? 58 : 66, (g.size.width - CGFloat(n - 1) * 6) / CGFloat(max(1, n))))
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(model.live.tracks) { t in strip(t.index, t.name, t.color, t.volume, t.pan, t.mute, t.solo, model.live.meters[t.index], width: w) }
                            strip(-1, "Master", "#8E8E93", model.live.master.volume, model.live.master.pan, false, false, model.live.masterMeter, width: w)
                        }
                        .padding(.bottom, 4)
                        .frame(minHeight: g.size.height, alignment: .top)
                    }
                }
                if sideModes {
                    VStack(spacing: 8) {
                        modeButton(.volume, L.s("Volume", "音量"))
                        modeButton(.pan, L.s("Pan", "パン"))
                        Spacer()
                    }
                    .frame(width: 84)
                }
            }
        }
        .padding(compact ? 0 : 12)
    }

    private func modeButton(_ m: Mode, _ title: String) -> some View {
        Button { mode = m } label: {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(mode == m ? .white : .primary)
                .background(RoundedRectangle(cornerRadius: 10).fill(mode == m ? Color.tkAccent : Color.tkCell))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    /// Live's volume knob position (0.85 is 0 dB). Shown as "0 dB" there, otherwise as a percentage
    /// of the knob (the exact dB curve stays in Live).
    private func dB(_ v: Double) -> String {
        guard v > 0.001 else { return "-∞" }
        if abs(v - RemoteModel.zeroDB) < 0.005 { return "0 dB" }
        return "\(Int((v * 100).rounded()))%"
    }

    private func strip(_ i: Int, _ name: String, _ color: String, _ vol: Double, _ pan: Double, _ mute: Bool, _ solo: Bool, _ meter: [Double]?, width: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(mode == .volume ? dB(vol) : String(format: "%+.0f", pan * 50)).font(.caption.bold()).monospacedDigit()
            GeometryReader { g in
                let h = g.size.height
                let value = mode == .volume ? vol : (pan + 1) / 2
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.tkCard)
                    RoundedRectangle(cornerRadius: 8).fill(i == -1 ? Color.secondary : Color.tkAccent)
                        .frame(height: h * value).padding(.trailing, 8)
                    // meter
                    HStack { Spacer(); Capsule().fill(Color.tkOK).frame(width: 4, height: h * (meter?.max() ?? 0)) }
                    if mode == .volume {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary)
                            .frame(height: 1).offset(y: -h * RemoteModel.zeroDB)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                    let v = min(1, max(0, 1 - d.location.y / h))
                    if mode == .volume { model.run(.setVolume(track: i, value: v)) } else { model.run(.setPan(track: i, value: v * 2 - 1)) }
                })
                .opacity(model.locked ? 0.5 : 1)
            }
            .frame(minHeight: 120)
            if i >= 0 {
                HStack(spacing: 4) {
                    toggle("M", mute, Color.tkWarn) { model.run(.setMute(track: i, on: !mute)) }
                    toggle("S", solo, Color.tkAccent) { model.run(.setSolo(track: i, on: !solo)) }
                }
            }
            Text(name).font(.caption2.bold()).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 20).background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: color)))
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(dB(vol))")
        .accessibilityAdjustableAction { dir in
            let step = dir == .increment ? 0.02 : -0.02
            model.run(.setVolume(track: i, value: min(1, max(0, vol + step))))
        }
    }

    private func toggle(_ label: String, _ on: Bool, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? .white : .primary)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? color : Color.tkCell))
        }
        .buttonStyle(.plain)
        .disabled(model.locked)
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
                Text(L.s("Cue keys", "キューのキー")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                let keys = model.status?.cueKeys ?? []
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(keys) { k in
                        Button { model.cue(k.keycode) } label: {
                            VStack(spacing: 3) {
                                Text(k.label).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
                                if !compact { Text(k.memo.isEmpty ? "—" : k.memo).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .frame(maxWidth: .infinity, minHeight: compact ? 50 : 64)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCard))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(k.memo.isEmpty ? k.label : "\(k.label) \(k.memo)")
                    }
                }
                if !compact {
                    Button(action: model.allNotesOff) {
                        Text(L.s("All Notes Off (both Macs)", "オールノートオフ（2台とも）")).font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52).background(RoundedRectangle(cornerRadius: 12).fill(Color.tkDanger))
                    }
                    macs
                }
            }
            .padding(compact ? 0 : 12)
        }
        }
    }

    private var lastCue: some View {
        let c = model.status?.lastCue
        return HStack(spacing: 12) {
            Text(c?.label ?? "–").font(.title.bold()).frame(width: 60, height: 50)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.tkCell))
            VStack(alignment: .leading, spacing: 2) {
                Text(L.s("Last cue", "直前のキュー")).font(.caption.bold()).foregroundStyle(.secondary)
                Text(c.map { $0.memo.isEmpty ? $0.label : $0.memo } ?? L.s("No cue yet", "まだありません")).font(.headline).lineLimit(1)
                if let c { Text(L.s("Cue \(c.count) since connecting", "接続してから \(c.count) 回目")).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let d = c?.delivery {
                Image(systemName: d == "delivered" ? "checkmark.circle.fill" : d == "missing" ? "exclamationmark.circle.fill" : "circle.dotted")
                    .font(.title2).foregroundStyle(d == "delivered" ? Color.tkOK : d == "missing" ? Color.tkDanger : .secondary)
                    .accessibilityLabel(d == "delivered" ? L.s("Reached the backup", "バックアップに届きました")
                                        : d == "missing" ? L.s("No confirmation", "届いた確認がありません") : d)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c?.delivery == "missing" ? Color.tkDanger : .clear, lineWidth: 1.5))
    }

    private var macs: some View {
        let st = model.status
        return VStack(alignment: .leading, spacing: 10) {
            row(L.s("Main Mac", "メインの Mac"), st?.mainName ?? "—", st?.mainLiveConnected == true ? L.s("Live connected", "Live 接続済み") : L.s("Live not connected", "Live 未接続"), st?.mainLiveConnected == true)
            row(L.s("Backup Mac", "バックアップの Mac"), st?.backupName ?? "—", st?.backupLinked == true ? L.s("Linked", "接続済み") : L.s("Not linked", "未接続"), st?.backupLinked == true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCard))
    }

    private func row(_ title: String, _ name: String, _ detail: String, _ ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(ok ? Color.tkOK : Color.tkWarn).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold())
                Text("\(name) · \(detail)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

struct SettingsPane: View {
    @EnvironmentObject var model: RemoteModel

    var body: some View {
        Form {
            Section(L.s("Show safety", "本番の安全")) {
                Toggle(L.s("Show lock", "本番ロック"), isOn: $model.locked)
                Toggle(L.s("Faders stop at 0 dB", "フェーダーの上限を 0dB にする"), isOn: $model.capAtZeroDB)
                Toggle(L.s("Follow the selection in Live", "Live の選択に追従"), isOn: $model.followSelection)
            }
            Section(L.s("Connection", "接続")) {
                LabeledContent(L.s("Mac", "Mac"), value: model.status?.mainName ?? "—")
                LabeledContent(L.s("Pairing code", "合言葉"), value: model.pairingCode)
                Button(L.s("Connect to another Mac (for example the backup)", "別の Mac につなぐ（バックアップなど）")) { model.chooseAnotherMac() }
            }
            Section {
                Text(L.s("TwinKeys Remote by Shogo Kajiyama / SEVENTHWELL. Unofficial tool, not affiliated with Ableton.",
                         "TwinKeys Remote（制作 Shogo Kajiyama / SEVENTHWELL）。非公式のツールで、Ableton 社とは関係ありません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
