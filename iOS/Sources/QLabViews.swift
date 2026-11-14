import SwiftUI
import TwinKeysCore

// QLab mode on the iPhone and iPad (docs/design-qlab.md 4.2; docs/design/qlab-iphone-go.png,
// qlab-iphone-cuelist.png), in the A1 look of iOS/Shared/Theme.swift.

/// The cue number as the screens show it ("12"), or "—" for a cue without one.
private func numberText(_ n: String) -> String { n.isEmpty ? "—" : n }

/// A small type badge ("AUD", "FADE", "GRP"…), coloured like the mockups.
struct QLabTypeBadge: View {
    let type: QLabCueType
    var body: some View {
        Text(type.short)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(minWidth: 40, minHeight: 18)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1))
            .accessibilityLabel(spoken)
    }
    private var color: Color {
        switch type {
        case .audio, .video, .mic: return TK.blue
        case .fade: return Color(tkRGB: 0xB48CFF)
        case .network, .midi, .light: return TK.yellow
        case .group, .cueList: return TK.read
        default: return TK.dim
        }
    }
    private var spoken: String {
        switch type {
        case .audio: return L.s("Audio", "オーディオ")
        case .fade: return L.s("Fade", "フェード")
        case .group: return L.s("Group", "グループ")
        case .memo: return L.s("Memo", "メモ")
        case .network: return L.s("Network", "ネットワーク")
        default: return type.short
        }
    }
}

/// Time left as "-1:08" (as the GO screen for Live).
private func leftText(_ s: Double) -> String { formatTimeLeft(s) }

/// The QLab GO screen: what runs (time left), what stands by, the playhead buttons, Stop and GO.
/// GO and the playhead buttons work under the show lock; Stop is long-press.
struct QLabGoView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var tight = false
    @State private var lastGo = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: tight ? 8 : 12) { nowCard; nextCard; Spacer(minLength: 0); buttonsRow }
                        goButton.frame(width: min(320, geo.size.width * 0.38))
                    }
                } else {
                    VStack(spacing: 12) { nowCard; nextCard; goButton.frame(maxHeight: 280); buttonsRow }
                }
            }
            .padding(tight ? 8 : 12)
            .onAppear { tight = geo.size.height < 340 }
            .onChange(of: geo.size) { _, sz in tight = sz.height < 340 }
        }
    }

    private var st: QLabStatus? { model.qlabStatus }
    private var next: QLabCue? { model.qlabNext }

    private var nowCard: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SmallCaps("NOW PLAYING", color: TK.accent, spoken: L.s("Now playing", "いま動いているキュー"))
                    Spacer()
                    if let r = st?.running.first {
                        QLabTypeBadge(type: r.type)
                        if let d = r.duration, d > 0 { durationBox(d) }
                    }
                }
                if let r = st?.running.first {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(numberText(r.number)).font(.system(size: tight ? 24 : 34, weight: .bold, design: .monospaced)).foregroundStyle(TK.dim)
                        Text(r.name.isEmpty ? L.s("(no name)", "（名前なし）") : r.name)
                            .font(.system(size: tight ? 21 : 28, weight: .heavy)).foregroundStyle(TK.read)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if let left = model.qlabLeft(r, now: ctx.date), let d = r.duration, d > 0 {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                SmallCaps("REMAIN", spoken: L.s("Left", "残り"))
                                Text(leftText(left)).font(TK.mono(tight ? .headline : .title2)).monospacedDigit().foregroundStyle(TK.accent)
                            }
                            SegmentMeter(value: 1 - left / d, segments: 40).frame(height: tight ? 10 : 16).padding(.bottom, 4)
                        }
                    }
                    if !tight {
                        ForEach(st?.running.dropFirst().prefix(2) ?? [], id: \.uniqueID) { o in
                            Divider().overlay(TK.stroke)
                            HStack(spacing: 8) {
                                LED(size: 5)
                                Text(numberText(o.number)).font(TK.mono(.subheadline)).foregroundStyle(TK.dim)
                                Text(o.name).font(.subheadline.bold()).foregroundStyle(TK.read).lineLimit(1)
                                Spacer()
                                if let l = model.qlabLeft(o, now: ctx.date) {
                                    Text(leftText(l)).font(TK.mono(.subheadline)).monospacedDigit().foregroundStyle(TK.accent)
                                }
                            }
                        }
                    }
                } else {
                    Text(L.s("No cue running", "動いているキューはありません")).font(.title3.bold()).foregroundStyle(TK.dim)
                }
            }
        }
        .padding(tight ? 10 : 16)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tkPanel(radius: 10)
        .overlay(alignment: .leading) {
            if st?.running.isEmpty == false { TK.accent.frame(width: 3).shadow(color: TK.accent.opacity(0.6), radius: 4) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func durationBox(_ d: Double) -> some View {
        Text(formatQLabDuration(d)).font(TK.mono(.caption2)).foregroundStyle(TK.read)
            .padding(.horizontal, 8).frame(minHeight: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(TK.stroke, lineWidth: 1))
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SmallCaps("NEXT · STANDING BY", color: TK.blue, spoken: L.s("Next, standing by", "次・待機中"))
                Spacer()
                if let n = next {
                    QLabTypeBadge(type: n.type)
                    if let d = n.duration, d > 0 { durationBox(d) }
                }
            }
            if let n = next {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(numberText(n.number)).font(.system(size: tight ? 22 : 30, weight: .bold, design: .monospaced)).foregroundStyle(TK.dim)
                    Text(n.name).font(.system(size: tight ? 19 : 26, weight: .heavy)).foregroundStyle(TK.read)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                backupLine
            } else {
                Text(L.s("Nothing standing by", "待機中のキューはありません")).font(.title3.bold()).foregroundStyle(TK.dim)
            }
        }
        .padding(tight ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tkPanel(radius: 10, stroke: next == nil ? TK.stroke : TK.blue, lineWidth: next == nil ? TK.line : 1.5)
        .accessibilityElement(children: .combine)
    }

    /// "BACKUP も 13 で待機中" (green), or the difference (yellow).
    @ViewBuilder private var backupLine: some View {
        if let b = st?.backup {
            let same = b.samePlayhead == true
            let text: String = {
                guard b.supported else { return L.s("The backup's TwinKeys cannot drive QLab", "バックアップの TwinKeys は QLab を動かせません") }
                guard b.state.canView else { return L.s("The backup's QLab is not connected", "バックアップの QLab につながっていません") }
                if same, let n = b.playheadNumber { return L.s("BACKUP standing by on \(n) too", "BACKUP も \(n) で待機中") }
                return L.s("BACKUP standing by on \(b.playheadNumber ?? "—")", "BACKUP は \(b.playheadNumber ?? "—") で待機中")
            }()
            HStack(spacing: 6) {
                LED(color: same && b.supported ? TK.accent : TK.yellow, size: 6)
                Text(text).font(.subheadline.bold()).foregroundStyle(same && b.supported ? TK.accent : TK.yellow).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            Text(L.s("No backup linked", "バックアップ未接続")).font(.caption).foregroundStyle(TK.yellow)
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            Button { model.qlab(QLabCommand(action: .playheadPrevious)) } label: {
                VStack(spacing: 2) {
                    Text(L.s("▲ Back", "▲ 前へ")).font(.headline)
                    Text(L.s("Playhead (both)", "再生位置（2台）")).font(.caption2).foregroundStyle(TK.dim)
                }.frame(maxWidth: .infinity, minHeight: tight ? 44 : 60)
            }
            .buttonStyle(TKButtonStyle(radius: 10, minHeight: tight ? 44 : 60))
            Button { model.qlab(QLabCommand(action: .playheadNext)) } label: {
                VStack(spacing: 2) {
                    Text(L.s("Next ▼", "次へ ▼")).font(.headline)
                    Text(L.s("Playhead (both)", "再生位置（2台）")).font(.caption2).foregroundStyle(TK.dim)
                }.frame(maxWidth: .infinity, minHeight: tight ? 44 : 60)
            }
            .buttonStyle(TKButtonStyle(radius: 10, minHeight: tight ? 44 : 60))
            // Stop (hardStop on both) needs a long press.
            VStack(spacing: 2) {
                Text("STOP").font(TK.mono(.headline)).tracking(2).foregroundStyle(TK.read)
                Text(L.s("Hold · both", "長押し・2台")).font(.caption2).foregroundStyle(TK.dim)
            }
            .frame(maxWidth: .infinity, minHeight: tight ? 44 : 60)
            .tkPanel(radius: 10)
            .onLongPressGesture(minimumDuration: 0.5) { model.qlab(QLabCommand(action: .hardStop)) }
            .accessibilityLabel(L.s("Stop on both Macs (long press)", "2台とも停止（長押し）"))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L.s("Double-tap and hold to stop", "ダブルタップして長押しで停止"))
        }
    }

    private var goButton: some View {
        let on = next != nil && model.qlabStatus?.state.canControl == true
        return Button(action: go) {
            VStack(spacing: 10) {
                SmallCaps("QLAB", color: TK.accentSoft, style: .subheadline)
                Text("GO").font(.system(size: 96, weight: .heavy, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(on ? TK.accent : TK.dim)
                    .shadow(color: on ? TK.accent.opacity(0.5) : .clear, radius: 12)
                if let n = next {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("NEXT ▸").font(TK.mono(.caption)).accessibilityHidden(true)
                        Text(n.title).font(.headline)
                    }
                    .foregroundStyle(TK.accent).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                if let l = st?.last {
                    Text(lastLine(l)).font(TK.mono(.caption2)).tracking(1)
                        .foregroundStyle(["missing", "noSuchCue", "notConnected", "noAnswer"].contains(l.backup) ? TK.red : TK.accent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Text("SHOW LOCK OK").font(TK.mono(.caption2)).tracking(2).foregroundStyle(TK.dim)
                    .accessibilityLabel(L.s("Works with the show lock on", "本番ロック中も使えます"))
            }
            .padding(.top, 28).padding(.bottom, 16).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoKeyBackground(enabled: on, radius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel(next.map { L.s("GO: QLab cue \($0.title)", "GO：QLab のキュー \($0.title)") } ?? "GO")
    }

    private func lastLine(_ l: QLabLastCommand) -> String {
        let main = l.main == "delivered" ? "MAIN ✓" : "MAIN ✗"
        let backup: String
        switch l.backup {
        case "delivered", "corrected": backup = "BACKUP ✓"
        case "waiting": backup = "BACKUP …"
        case "notLinked", "unsupported", "notSent": backup = "BACKUP –"
        default: backup = "BACKUP ✗"
        }
        return "LAST \(l.action == .go || l.action == .goCue ? "GO" : l.action.name.uppercased()) \(l.number ?? "") \(main) \(backup)"
    }

    private func go() {
        // A second GO within 0.5 s is ignored here too (the Mac merges any within 0.3 s).
        guard Date().timeIntervalSince(lastGo) >= GoView.goGuard else { return }
        lastGo = Date()
        model.qlabGo()
    }
}

/// The cue list (in place of Session and Mixer in QLab mode). A tap moves the playhead there on both
/// Macs (never GO); under the show lock it takes a 0.5 s press.
struct QLabCueListView: View {
    @EnvironmentObject var model: RemoteModel
    /// iPad and wide windows: the hint and the backup comparison on the right.
    var showSide = true
    @State private var search = ""
    @State private var follow = true
    /// Little width (an iPhone): no meters in the rows, so the names keep their room.
    @State private var narrow = false

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 12) {
                list
                if showSide && geo.size.width > 900 {
                    VStack(spacing: 12) { hint; backupBox; Spacer(minLength: 0) }.frame(width: min(250, geo.size.width * 0.26))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .onAppear { narrow = geo.size.width < 760 }
            .onChange(of: geo.size) { _, sz in narrow = sz.width < 760 }
        }
    }

    private var cues: [QLabCue] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.qlabCues }
        return model.qlabCues.filter { $0.number.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SmallCaps(narrow ? "\(model.qlabCues.count) CUES" : "CUE LIST · \((model.qlabStatus?.listName ?? "").uppercased()) · \(model.qlabCues.count) CUES",
                          spoken: L.s("Cue list, \(model.qlabCues.count) cues", "キューの一覧、\(model.qlabCues.count) 個"))
                    .layoutPriority(1)
                Spacer(minLength: 4)
                TextField(L.s("Find a number or name", "番号か名前で探す"), text: $search)
                    .textFieldStyle(.plain).font(.subheadline).padding(.horizontal, 10).frame(maxWidth: narrow ? 170 : 260, minHeight: 34)
                    .tkPanel(radius: 6)
                Toggle(isOn: $follow) { Text("FOLLOW").font(TK.mono(.caption)).tracking(1.5) }
                    .toggleStyle(TKToggleKeyStyle())
                    .accessibilityLabel(L.s("Follow the playhead", "再生位置に付いていく"))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        LazyVStack(spacing: 4) {
                            ForEach(cues) { c in row(c, now: ctx.date).id(c.uniqueID) }
                        }
                    }
                }
                .onAppear { scroll(proxy) }
                .onChange(of: model.qlabStatus?.playheadID) { _, _ in scroll(proxy) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard follow, search.isEmpty, let id = model.qlabStatus?.playheadID else { return }
        withAnimation { proxy.scrollTo(id, anchor: .center) }
    }

    private func row(_ c: QLabCue, now: Date) -> some View {
        let running = model.qlabStatus?.running.first { $0.uniqueID == c.uniqueID }
        let isNext = model.qlabStatus?.playheadID == c.uniqueID
        let index = model.qlabCues.firstIndex { $0.uniqueID == c.uniqueID } ?? 0
        let nextIndex = model.qlabCues.firstIndex { $0.uniqueID == model.qlabStatus?.playheadID } ?? Int.max
        let done = running == nil && !isNext && index < nextIndex
        return HStack(spacing: 10) {
            ZStack {
                if running != nil { LED(size: 6) } else if isNext { Image(systemName: "play.fill").font(.caption).foregroundStyle(TK.blue) }
            }
            .frame(width: 14)
            Text(numberText(c.number)).font(TK.mono(.subheadline)).monospacedDigit().foregroundStyle(TK.read).frame(width: 46, alignment: .leading)
            QLabTypeBadge(type: c.type).padding(.leading, CGFloat(min(c.depth, 4)) * 18)
            Text(c.name).font(.subheadline.weight(.bold)).foregroundStyle(done ? TK.dim : TK.read).lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if let r = running {
                if !narrow, let d = r.duration, d > 0, let l = model.qlabLeft(r, now: now) {
                    SegmentMeter(value: 1 - l / d, segments: 16).frame(width: 120, height: 10)
                }
                if let l = model.qlabLeft(r, now: now) {
                    Text(leftText(l)).font(TK.mono(.subheadline)).monospacedDigit().foregroundStyle(TK.accent).frame(width: 64, alignment: .trailing)
                }
            } else if isNext {
                Text("NEXT").font(TK.mono(.caption)).tracking(2).foregroundStyle(TK.blue)
            }
            Text(c.duration.map { $0 > 0 ? formatQLabDuration($0) : "∞" } ?? "")
                .font(TK.mono(.subheadline)).monospacedDigit().foregroundStyle(TK.dim).frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 10).frame(minHeight: 42)
        .tkPanel(radius: 6, fill: running != nil ? TK.keyTop : isNext ? TK.blueGround : TK.panel,
                 stroke: running != nil ? TK.accent : isNext ? TK.blue : TK.stroke,
                 lineWidth: running != nil || isNext ? 1.5 : TK.line)
        .contentShape(Rectangle())
        // A tap moves the playhead (both Macs); under the show lock a 0.5 s press (no slip of the finger).
        .onTapGesture { if !model.locked { move(c) } }
        .onLongPressGesture(minimumDuration: 0.5) { if model.locked { move(c) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L.s("Moves the playhead here on both Macs (does not GO)", "2台とも再生位置をここへ移します（GO はしません）"))
    }

    private func move(_ c: QLabCue) {
        guard !c.number.isEmpty else { model.lastResult = "qlab_no_number"; return }
        model.qlab(QLabCommand(action: .setPlayhead, cueNumber: c.number))
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCaps("TAP A CUE", spoken: L.s("Tap a cue", "キューをタップ"))
            Text(L.s("Tap: move the playhead there (both Macs)", "タップ：そこに再生位置を移す（2台とも）")).font(.headline).foregroundStyle(TK.read)
            Text(L.s("It does not GO. With the show lock on, hold 0.5 s.", "GO はしません。本番ロック中は長押し 0.5 秒"))
                .font(.subheadline).foregroundStyle(TK.dim)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tkPanel(radius: 10)
    }

    private var backupBox: some View {
        let b = model.qlabStatus?.backup
        return VStack(alignment: .leading, spacing: 8) {
            SmallCaps("BACKUP", spoken: L.s("Backup", "バックアップ"))
            if let b, b.supported {
                compare(b.sameCues != false, L.s("\(b.cueCount) cues · \(b.sameCues == true ? "same" : "differ")",
                                                 "\(b.cueCount) キュー・\(b.sameCues == true ? "同じ" : "違います")"))
                compare(b.samePlayhead != false, L.s("Playhead \(b.playheadNumber ?? "—") · \(b.samePlayhead == true ? "same" : "differs")",
                                                     "位置 \(b.playheadNumber ?? "—")・\(b.samePlayhead == true ? "同じ" : "違います")"))
                if !b.showMode {
                    compare(false, L.s("Not in Show Mode", "本番モードではありません"))
                }
            } else {
                Text(b == nil ? L.s("No backup linked", "バックアップ未接続") : L.s("The backup's TwinKeys cannot drive QLab", "バックアップの TwinKeys は QLab を動かせません"))
                    .font(.subheadline.bold()).foregroundStyle(TK.yellow)
            }
            Text(L.s("Yellow when they differ: \"The backup's cues differ\"", "違うときは黄色で「バックアップのキューが違います」"))
                .font(.caption).foregroundStyle(TK.dim)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tkPanel(radius: 10)
        .accessibilityElement(children: .combine)
    }

    private func compare(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            LED(color: ok ? TK.accent : TK.yellow, size: 6)
            Text(text).font(.subheadline.bold()).foregroundStyle(ok ? TK.accent : TK.yellow).lineLimit(2)
        }
    }
}

/// The top bar's QLab part: MAIN · BACKUP · QLAB lamps, WORKSPACE, RUNNING, LIST and PANIC (both Macs).
struct QLabTopBarItems: View {
    @EnvironmentObject var model: RemoteModel
    var compact: Bool

    var body: some View {
        let st = model.qlabStatus
        HStack(spacing: 8) {
            if !compact {
                DisplayWindow(title: "WORKSPACE") {
                    Text(st?.workspaceName ?? "—").font(TK.mono(.headline)).foregroundStyle(TK.read).lineLimit(1)
                }
                DisplayWindow(title: "RUNNING") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(st?.running.count ?? 0)").font(TK.mono(.headline)).foregroundStyle(TK.accent)
                        Text("cues").font(.caption2).foregroundStyle(TK.dim)
                    }
                }
                DisplayWindow(title: "LIST") {
                    Text(st?.listName ?? "—").font(TK.mono(.headline)).foregroundStyle(TK.read).lineLimit(1)
                }
            }
        }
    }
}

/// PANIC (both Macs): QLab's panic; pressed again during the fade, QLab stops at once.
struct QLabPanicButton: View {
    @EnvironmentObject var model: RemoteModel
    var body: some View {
        Button { model.qlab(QLabCommand(action: .panic)); if model.target == .both { model.allNotesOff() } } label: {
            Text(model.target == .both ? L.s("All Notes Off + PANIC", "全ノートオフ＋PANIC") : L.s("PANIC (both)", "PANIC（2台）"))
                .font(.subheadline.bold()).foregroundStyle(TK.red)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(NotesOffBackground(radius: 8))
        }
        .accessibilityHint(L.s("Panic on both Macs' QLab. Press again to stop at once.", "2台の QLab を Panic。もう一度押すとすぐ止まります"))
    }
}
