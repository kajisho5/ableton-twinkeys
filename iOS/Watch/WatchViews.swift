import SwiftUI

/// Three pages, swiped left and right: GO, choose the next scene, All Notes Off (docs/design/watch-dark.svg).
struct WatchRootView: View {
    @EnvironmentObject var model: WatchModel
    @State private var page: Int = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-page"), i + 1 < a.count { return ["go": 0, "scenes": 1, "panic": 2][a[i + 1]] ?? 0 }
        return 0
    }()

    var body: some View {
        TabView(selection: $page) {
            GoPage(active: page == 0).tag(0)
            ScenesPage().tag(1)
            PanicPage().tag(2)
        }
        .tabViewStyle(.page)
        .background(Color.black)
    }
}

// MARK: 1. GO

/// Playing scene and time left on top; GO plays the next scene. The Digital Crown moves "next" up and
/// down (only chooses, never plays).
struct GoPage: View {
    @EnvironmentObject var model: WatchModel
    let active: Bool
    @State private var crown = 0.0
    @FocusState private var focused: Bool

    /// `active`: this page is the one shown (it then takes the crown).
    init(active: Bool) { self.active = active }

    var body: some View {
        VStack(spacing: 6) {
            NowLine()
            goButton
            Text(model.notice ?? L.s("Digital Crown: back / next", "デジタルクラウンで前・次"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.notice == nil ? TK.dim : TK.yellow)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .focusable(true)
        .focused($focused)
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: 0, through: Double(max(model.names.count - 1, 1)), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            // Only while this page is shown (the crown scrolls the list on the next page).
            guard active else { return }
            let i = min(max(Int(value.rounded()), 0), max(model.names.count - 1, 0))
            if i != model.nextIndex { model.choose(i) }
        }
        .onChange(of: model.nextIndex) { _, i in
            if let i, Int(crown.rounded()) != i { crown = Double(i) }
        }
        .onChange(of: active) { _, on in
            if on, let i = model.nextIndex { crown = Double(i) }
            focused = on
        }
        .onAppear {
            if let i = model.nextIndex { crown = Double(i) }
            focused = active
        }
    }

    private var goButton: some View {
        let on = model.canGo
        return Button { model.go() } label: {
            // A1: a round dark-green key with a glowing green edge inside a green ring.
            ZStack {
                Circle().strokeBorder(on ? TK.accent.opacity(0.85) : TK.off, lineWidth: 5)
                    .shadow(color: on ? TK.accent.opacity(0.5) : .clear, radius: 5)
                Circle()
                    .fill(LinearGradient(colors: on ? [TK.keyTop, TK.keyBottom] : [TK.panel, TK.panel], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(on ? TK.accent : TK.stroke, lineWidth: 1.5))
                    .padding(10)
                VStack(spacing: 2) {
                    Text("GO").font(.system(size: 44, weight: .heavy, design: .monospaced)).minimumScaleFactor(0.6)
                        .foregroundStyle(on ? TK.accent : TK.dim)
                        .shadow(color: on ? TK.accent.opacity(0.5) : .clear, radius: 6)
                    Text(nextLine).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                        .foregroundStyle(on ? TK.accentSoft : TK.dim)
                }
                .padding(.horizontal, 22)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.nextIndex.map { L.s("GO: play scene \($0 + 1) \(model.sceneName($0))",
                                                     "GO：シーン \($0 + 1) \(model.sceneName($0)) を再生") } ?? "GO")
    }

    private var nextLine: String {
        guard let i = model.nextIndex else { return L.s("End of the scene list", "シーンの最後です") }
        return L.s("Next: \(i + 1) \(model.sceneName(i))", "次：\(i + 1) \(model.sceneName(i))")
    }
}

/// "3 M1 イントロ   -0:26" (green), or why the watch cannot work now.
struct NowLine: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        if let why = model.problem {
            Text(why).font(.system(size: 14, weight: .bold)).foregroundStyle(TK.yellow)
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        } else if let p = model.playingIndex {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                HStack(spacing: 6) {
                    LED(size: 5)
                    Text("\(p + 1) \(model.sceneName(p))").lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    if let left = model.leftNow(context.date) {
                        Text(WatchState.formatLeft(left)).font(.system(size: 15, weight: .bold, design: .monospaced)).monospacedDigit()
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TK.accent)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(L.s("Nothing playing", "再生中のシーンはありません")).font(.system(size: 14, weight: .bold))
                .foregroundStyle(TK.dim).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

// MARK: 2. Choose the next scene

/// Every scene; the playing one is marked green ▶, the next one blue. A tap makes it next (does not play).
struct ScenesPage: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    if let warn = model.notice ?? model.problem {
                        Text(warn)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TK.yellow)
                            .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    } else {
                        // A1 heading; VoiceOver reads the localized words.
                        Text("SCENES").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(3)
                            .foregroundStyle(TK.accent)
                            .accessibilityLabel(L.s("Choose scene", "シーンを選ぶ"))
                    }
                    ForEach(model.names.indices, id: \.self) { i in
                        row(i).id(i)
                    }
                    Text(L.s("Tap to make it Next (does not play)", "タップで「次」に選ぶ（鳴らさない）"))
                        .font(.system(size: 12)).foregroundStyle(TK.dim)
                        .multilineTextAlignment(.center).padding(.top, 2)
                }
                .padding(.horizontal, 2)
            }
            .onAppear { if let i = model.nextIndex { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    private func row(_ i: Int) -> some View {
        let playing = i == model.playingIndex
        let next = i == model.nextIndex
        return Button { model.choose(i, now: true) } label: {
            HStack(spacing: 8) {
                Text(String(format: "%02d", i + 1)).font(.system(size: 14, weight: .bold, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(TK.dim)
                Text(model.sceneName(i)).foregroundStyle(TK.read).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if playing {
                    LED(size: 6)
                } else if next {
                    Text("NEXT").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(TK.blue)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(playing ? TK.keyTop : TK.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(playing ? TK.accent : next ? TK.blue : TK.stroke, lineWidth: playing || next ? 1.5 : TK.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("Scene \(i + 1) \(model.sceneName(i))", "シーン \(i + 1) \(model.sceneName(i))")
                            + (playing ? L.s(", playing", "、再生中") : next ? L.s(", next", "、次") : ""))
    }
}

// MARK: 3. All Notes Off

/// Link status, the red All Notes Off button (both Macs) and the last cue.
struct PanicPage: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        VStack(spacing: 6) {
            linkLine
            Button { model.allNotesOff() } label: {
                VStack(spacing: 2) {
                    // A1 decoration; VoiceOver reads the localized words below.
                    VStack(spacing: 0) {
                        Text("ALL").font(.system(size: 26, weight: .heavy, design: .monospaced)).tracking(2)
                        Text("NOTES OFF").font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(1)
                    }
                    .foregroundStyle(TK.red).lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityHidden(true)
                    Text(L.s("All Notes Off", "全ノートオフ"))
                        .font(.system(size: 14, weight: .bold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .foregroundStyle(TK.redSoft)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NotesOffBackground(radius: 22, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.s("Stops every note on both Macs", "2台の Mac の音をすべて止めます"))
            Text(model.notice ?? cueLine)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(model.notice == nil ? TK.read : TK.yellow)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(L.s("Swipe left / right to switch", "左右にスワイプで切替"))
                .font(.system(size: 12)).foregroundStyle(TK.dim).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
    }

    /// "Main ✓ Backup ✓" (green when both Lives answer), with a lock when the iPhone's show lock is on.
    private var linkLine: some View {
        let st = model.state
        let main = st?.mainOK == true, backup = st?.backupOK == true
        let ok = model.problem == nil && main && backup
        let line: String = model.problem != nil ? "iPhone ✗" : "Main \(main ? "✓" : "✗")  Backup \(backup ? "✓" : "✗")"
        return HStack(spacing: 4) {
            if model.problem != nil {
                Text(line).foregroundStyle(TK.yellow)
            } else {
                // A1: the two Macs as lamps (M, B); VoiceOver reads the same line as before.
                HStack(spacing: 14) {
                    HStack(spacing: 4) { LED(color: main ? TK.accent : TK.yellow, size: 6); Text("M") }
                    HStack(spacing: 4) { LED(color: backup ? TK.accent : TK.yellow, size: 6); Text("B") }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(ok ? TK.read : TK.yellow)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line)
            }
            if st?.locked == true { Image(systemName: "lock.fill").foregroundStyle(TK.accent).accessibilityLabel(L.s("Show lock on", "本番ロック中")) }
        }
        .font(.system(size: 15, weight: .bold))
        .lineLimit(1).minimumScaleFactor(0.6)
    }

    private var cueLine: String {
        guard let c = model.state?.lastCue else { return L.s("Last cue: none yet", "直前：まだありません") }
        let mark: String
        switch model.state?.lastCueOK {
        case true?: mark = " ✓"
        case false?: mark = " ✗"
        case nil: mark = ""
        }
        return L.s("Last: \(c)\(mark)", "直前：\(c)\(mark)")
    }
}
