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
                .foregroundStyle(model.notice == nil ? Color.secondary : Color.tkWarn)
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
        Button { model.go() } label: {
            VStack(spacing: 2) {
                Text("GO").font(.system(size: 46, weight: .black)).minimumScaleFactor(0.6)
                Text(nextLine).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 6)
            .foregroundStyle(model.canGo ? Color.tkOnGreen : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(model.canGo ? Color.tkOK : Color.tkCell))
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
            Text(why).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.tkWarn)
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        } else if let p = model.playingIndex {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                HStack(spacing: 6) {
                    Text("\(p + 1) \(model.sceneName(p))").lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    if let left = model.leftNow(context.date) {
                        Text(WatchState.formatLeft(left)).monospacedDigit()
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.tkOK)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(L.s("Nothing playing", "再生中のシーンはありません")).font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
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
                    Text(model.notice ?? model.problem ?? L.s("Choose scene", "シーンを選ぶ"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.notice == nil && model.problem == nil ? Color.tkAccent : Color.tkWarn)
                        .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    ForEach(model.names.indices, id: \.self) { i in
                        row(i).id(i)
                    }
                    Text(L.s("Tap to make it Next (does not play)", "タップで「次」に選ぶ（鳴らさない）"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text("\(i + 1)").monospacedDigit().foregroundStyle(.secondary)
                Text(model.sceneName(i)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if playing {
                    Image(systemName: "play.fill").foregroundStyle(Color.tkOK)
                } else if next {
                    Text(L.s("Next", "次")).foregroundStyle(Color.tkAccent)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(playing ? Color.tkOK.opacity(0.22) : next ? Color.tkAccent.opacity(0.22) : Color.tkCell))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(playing ? Color.tkOK : next ? Color.tkAccent : Color.clear, lineWidth: 1.5))
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
                Text(L.s("All Notes Off", "全ノートオフ"))
                    .font(.system(size: 28, weight: .heavy)).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color.tkDanger))
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.s("Stops every note on both Macs", "2台の Mac の音をすべて止めます"))
            Text(model.notice ?? cueLine)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(model.notice == nil ? Color.white : Color.tkWarn)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(L.s("Swipe left / right to switch", "左右にスワイプで切替"))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
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
            Text(line)
            if st?.locked == true { Image(systemName: "lock.fill").accessibilityLabel(L.s("Show lock on", "本番ロック中")) }
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(ok ? Color.tkOK : Color.tkWarn)
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
