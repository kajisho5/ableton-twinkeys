import SwiftUI
import TwinKeysCore

enum Pane: String, CaseIterable, Identifiable {
    case session, mixer, cues, go, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .session: return L.s("Session", "セッション")
        case .mixer: return L.s("Mixer", "ミキサー")
        case .cues: return L.s("Cues", "キュー")
        case .go: return "GO"
        case .settings: return L.s("Settings", "設定")
        }
    }
    var symbol: String {
        switch self {
        case .session: return "square.grid.3x3.fill"
        case .mixer: return "slider.vertical.3"
        case .cues: return "bolt.fill"
        case .go: return "play.circle"
        case .settings: return "gearshape"
        }
    }
}

/// Main screen. The layout follows the space available (see `LayoutClass`).
struct MainView: View {
    @EnvironmentObject var model: RemoteModel
    /// `-pane mixer` etc. picks the first pane (screenshots on CI).
    @State private var pane: Pane = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-pane"), i + 1 < a.count, let p = Pane(rawValue: a[i + 1]) { return p }
        return .session
    }()
    /// The Apple Watch mark in the top bar asks Settings to scroll to "Connection".
    @State private var showConnection = false

    var body: some View {
        GeometryReader { geo in
            let lc = LayoutClass.of(geo.size)
            VStack(spacing: 0) {
                TopBar(compact: lc == .narrowPortrait, openConnection: openConnection)
                if !model.isConnected && model.wasConnected { MainLostBanner() }
                if model.switchedToBackup && model.isConnected { SwitchedBanner() }
                if model.isConnected, let d = model.status?.setDiff { SetDiffBanner(diff: d) }
                if let r = model.lastResult { ResultBanner(error: r) }
                switch lc {
                case .narrowPortrait:
                    content(pane, lc).frame(maxWidth: .infinity, maxHeight: .infinity)
                    allTabs
                case .narrowLandscape:
                    HStack(spacing: 0) {
                        content(pane, lc).frame(maxWidth: .infinity, maxHeight: .infinity)
                        rail
                    }
                case .medium:
                    if pane == .go {
                        GoView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if pane == .session || pane == .cues {
                        HStack(alignment: .top, spacing: 12) {
                            SessionView(showSceneColumn: false).frame(maxWidth: .infinity)
                            CuesView().frame(width: min(300, geo.size.width * 0.4))
                        }
                        .padding(.horizontal, 12)
                    } else {
                        content(pane, lc).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    tabBar(panes: [.session, .mixer, .go, .settings])
                case .wide:
                    if pane == .settings {
                        SettingsPane(showConnection: $showConnection).frame(maxWidth: 640)
                    } else if pane == .go {
                        GoView().frame(maxWidth: 1000, maxHeight: .infinity)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            SessionView(showSceneColumn: true).frame(maxWidth: .infinity)
                            VStack(spacing: 12) {
                                MixerView(compact: true).frame(height: geo.size.height * 0.5)
                                CuesView(compact: true)
                            }
                            .frame(width: min(380, geo.size.width * 0.32))
                        }
                        .padding(.horizontal, 12)
                    }
                    tabBar(panes: [.session, .go, .settings])
                }
            }
        }
        .background(Color.tkBG.ignoresSafeArea())
    }

    @ViewBuilder private func content(_ p: Pane, _ lc: LayoutClass) -> some View {
        switch p {
        case .session: SessionView(showSceneColumn: lc == .narrowLandscape)
        case .mixer: MixerView(sideModes: lc == .narrowLandscape)
        case .cues: CuesView()
        case .go: GoView()
        case .settings: SettingsPane(showConnection: $showConnection)
        }
    }

    /// Settings, at "Connection".
    private func openConnection() {
        pane = .settings
        showConnection = true
    }

    private var allTabs: some View { tabBar(panes: Pane.allCases) }

    private func tabBar(panes: [Pane]) -> some View {
        HStack {
            ForEach(panes) { p in
                Button { pane = p } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.symbol).font(.system(size: 20))
                        Text(p.title).font(.caption2.weight(pane == p ? .bold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(pane == p ? Color.tkAccent : .secondary)
                }
                .accessibilityAddTraits(pane == p ? .isSelected : [])
            }
        }
        .background(Color.tkBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    /// Landscape iPhone: the pane switcher on the right edge, where the right thumb is.
    /// Five buttons share the height (a warning bar under the top bar takes some of it).
    private var rail: some View {
        VStack(spacing: 4) {
            ForEach(Pane.allCases) { p in
                Button { pane = p } label: {
                    VStack(spacing: 2) {
                        Image(systemName: p.symbol).font(.system(size: 19))
                        Text(p.title).font(.system(size: 10, weight: pane == p ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: 60).frame(minHeight: 44, maxHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 10).fill(pane == p ? Color.tkCell : .clear))
                    .foregroundStyle(pane == p ? Color.tkAccent : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 68)
        .background(Color.tkBar.ignoresSafeArea(edges: .trailing))
        .overlay(alignment: .leading) { Divider() }
    }
}

/// Always on top: link status, play / stop, tempo, position, All Notes Off and the show lock.
struct TopBar: View {
    @EnvironmentObject var model: RemoteModel
    var compact: Bool
    /// Opens Settings at "Connection" (the Apple Watch mark).
    var openConnection: () -> Void = {}
    @State private var unlockProgress = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statusText
                Spacer(minLength: 4)
                if !compact { transport }
                Spacer(minLength: 4)
                Button(action: model.allNotesOff) {
                    Text(L.s("All Notes Off", "全ノートオフ")).font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.tkDanger))
                }
                .accessibilityHint(L.s("Stops every note on both Macs", "2台の Mac の音をすべて止めます"))
                lockButton
            }
            if compact { HStack { transport; Spacer() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.tkBar.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusText: some View {
        let st = model.status
        let backupOK = st?.backupLinked ?? false
        // 2.1: the backup's own Live must answer too, or a cue reaches only one Live.
        let backupLive = backupOK && st?.backupLiveConnected == true
        let allOK = st?.mainLiveConnected == true && backupLive
        let connected = model.isConnected
        let line: String = {
            guard connected else { return L.s("Main Mac: no answer", "メイン切断中") }
            guard backupOK else { return L.s("Backup not linked", "バックアップ未接続") }
            let live = backupLive ? L.s("Live ✓", "Live ✓") : L.s("Live ✗ no answer", "Live ✗ 応答なし")
            return L.s("Backup ✓", "バックアップ ✓") + " · " + live + (backupLive ? (st?.latencyMs.map { " · \(Int($0.rounded())) ms" } ?? "") : "")
        }()
        return HStack(spacing: 8) {
            Circle().fill(!connected ? Color.tkDanger : allOK ? Color.tkOK : Color.tkWarn).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text((st?.mainName ?? "TwinKeys") + (model.trialMode ? L.s(" · Sample", " · サンプル") : "")).font(.subheadline.bold()).lineLimit(1)
                    watchMark
                }
                Text(line).font(.caption).foregroundStyle(!connected ? Color.tkDanger : backupLive ? Color.secondary : Color.tkWarn).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: L.s("Connection settings", "接続の設定")) { openConnection() }
    }

    /// Connection display: the Apple Watch next to the Mac's name (green: reachable, yellow: not
    /// reachable). Not shown without a watch with TwinKeys. Tap: Settings > Connection.
    @ViewBuilder private var watchMark: some View {
        let level = model.watch?.level ?? .absent
        if level != .absent {
            Image(systemName: "applewatch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(level == .reachable ? Color.tkOK : Color.tkWarn)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { openConnection() }
                .accessibilityLabel(level == .reachable ? L.s("Apple Watch connected", "Apple Watch つながっています")
                                                        : L.s("Apple Watch not reachable", "Apple Watch 届きません"))
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button { model.run(.play) } label: {
                Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 54, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(model.live.song.playing ? Color.tkOK : Color.secondary))
            }
            .accessibilityLabel(L.s("Play", "再生"))
            // Stop needs a long press (a touch by accident does not stop the show).
            Image(systemName: "stop.fill").font(.title3)
                .frame(width: 54, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.tkCell))
                .onLongPressGesture(minimumDuration: 0.5) { model.run(.stop) }
                .accessibilityLabel(L.s("Stop (long press)", "停止（長押し）"))
                .accessibilityAddTraits(.isButton)
                // No one-tap accessibility action: with VoiceOver, double-tap and hold (same safety as the touch).
                .accessibilityHint(L.s("Double-tap and hold to stop", "ダブルタップして長押しで停止"))
            Text(String(format: "%.2f", model.live.song.tempo)).font(.title3.bold()).monospacedDigit()
            Text("BPM").font(.caption).foregroundStyle(.secondary)
            Text(model.live.song.beat).font(.headline).monospacedDigit().padding(.leading, 4)
        }
    }

    private var lockButton: some View {
        Image(systemName: model.locked ? "lock.fill" : "lock.open")
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(model.locked ? Color.tkAccent.opacity(0.2) : Color.tkCell))
            .foregroundStyle(model.locked ? Color.tkAccent : .secondary)
            // Locking is a tap; unlocking needs a 1 s press.
            .onTapGesture { if !model.locked { model.locked = true } }
            .onLongPressGesture(minimumDuration: 1) { model.locked = false }
            .accessibilityLabel(model.locked ? L.s("Show lock on (hold to unlock)", "本番ロック中（長押しで解除）") : L.s("Show lock off", "本番ロック オフ"))
            .accessibilityAddTraits(.isButton)
            // Locking is one action; unlocking needs the 1 s hold (VoiceOver: double-tap and hold).
            .accessibilityAction { if !model.locked { model.locked = true } }
    }
}

/// Why the last command did not run (shown for 5 s under the top bar).
struct ResultBanner: View {
    let error: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 30).padding(.horizontal, 12)
            .background(Color.tkWarn)
            .accessibilityAddTraits(.updatesFrequently)
    }
    private var text: String {
        switch error {
        case "structure_changed": return L.s("Live's tracks or scenes changed, so it was not sent. Tap again.",
                                             "Live のトラックやシーンが変わったので、送りませんでした。もう一度押してください。")
        case "locked": return L.s("Show lock is on.", "本番ロック中です。")
        case "late": return L.s("Live ran it after all (late). Do not tap again.", "Live で遅れて動きました。押し直さないでください。")
        case "backup_failedLive": return L.s("Ran on the main Mac, but the backup's Live refused it.", "メインでは動きましたが、バックアップの Live では動きませんでした。")
        case "backup_noLive": return L.s("Ran on the main Mac; the backup's Live did not answer.", "メインでは動きましたが、バックアップの Live から返事がありません。")
        case "backup_missing": return L.s("Ran on the main Mac; no answer from the backup Mac.", "メインでは動きましたが、バックアップの Mac から返事がありません。")
        // Live may still have run it late: check Live's screen before tapping again (no double launch).
        case "no_answer": return L.s("No answer from Live. Check Live before tapping again.",
                                     "Live から返事がありません。Live の画面で動いたか確かめてから押し直してください。")
        default: return L.s("Live did not run it (\(error)).", "Live で実行できませんでした（\(error)）。")
        }
    }
}

/// 2.1: the backup's Live set differs from the main's. Stays under the top bar; tap for the rows.
struct SetDiffBanner: View {
    let diff: SetDiff
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack {
                Label(L.s("Backup's set differs: tracks \(diff.mainTracks) / \(diff.backupTracks) · scenes \(diff.mainScenes) / \(diff.backupScenes) · \(diff.differences) name(s)",
                          "バックアップのセットが違います：トラック \(diff.mainTracks) / \(diff.backupTracks) ・ シーン \(diff.mainScenes) / \(diff.backupScenes) ・ 名前の違い \(diff.differences) か所"),
                      systemImage: "exclamationmark.triangle.fill")
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(L.s("Details ›", "詳しく ›"))
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color(red: 1, green: 0.89, blue: 0.65))
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 34)
            .background(Color(red: 0.35, green: 0.24, blue: 0.04))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { SetDiffSheet(diff: diff) }
    }
}

struct SetDiffSheet: View {
    let diff: SetDiff
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(L.s("Tracks", "トラックの数"), "\(diff.mainTracks)", "\(diff.backupTracks)")
                    row(L.s("Scenes", "シーンの数"), "\(diff.mainScenes)", "\(diff.backupScenes)")
                } header: { header }
                Section {
                    ForEach(Array(diff.rows.enumerated()), id: \.offset) { _, r in
                        row(r.kind == "track" ? L.s("Track \(r.index + 1)", "トラック \(r.index + 1) の名前") : L.s("Scene \(r.index + 1)", "シーン \(r.index + 1) の名前"),
                            r.main ?? L.s("(none)", "（なし）"), r.backup ?? L.s("(none)", "（なし）"))
                    }
                } footer: {
                    Text((diff.complete ? "" : L.s("Still receiving the backup's names. ", "バックアップの名前を受け取り中です。"))
                         + L.s("Open the same set file on both Macs to clear this. Nothing is changed automatically during a show.",
                               "セットのファイルを2台で同じにすると消えます。本番中は確かめるだけで、自動で直すことはしません。"))
                }
            }
            .navigationTitle(L.s("Main and backup sets", "メインとバックアップの Live のセット"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.s("Done", "閉じる")) { dismiss() } } }
        }
    }
    private var header: some View {
        HStack {
            Text(L.s("Item", "項目")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.s("Main", "メイン")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.s("Backup", "バックアップ")).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func row(_ item: String, _ main: String, _ backup: String) -> some View {
        HStack {
            Text(item).frame(maxWidth: .infinity, alignment: .leading)
            Text(main).bold().frame(maxWidth: .infinity, alignment: .leading)
            Text(backup).bold().foregroundStyle(main == backup ? Color.primary : Color.tkWarn).frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(2).font(.subheadline)
    }
}

/// 2.3: the main Mac stopped answering. After 3 s, offer switching to the backup Mac.
struct MainLostBanner: View {
    @EnvironmentObject var model: RemoteModel
    @State private var confirming = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let secs = model.lostAt.map { Int(ctx.date.timeIntervalSince($0)) } ?? 0
            if secs >= 3 {
                HStack(spacing: 10) {
                    Label(L.s("The main Mac is not answering (\(secs) s)", "メインの Mac が応答しません（\(secs) 秒）"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if model.backupMac != nil {
                        Button { confirming = true } label: {
                            Text(L.s("Switch to the backup", "バックアップに切り替える")).font(.subheadline.bold())
                                .foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.tkDanger))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(L.s("Backup Mac not found", "バックアップの Mac が見つかりません")).font(.caption.bold())
                    }
                }
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.8))
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(red: 0.29, green: 0.08, blue: 0.06))
            }
        }
        .sheet(isPresented: $confirming) { SwitchConfirmSheet().presentationDetents([.medium]) }
    }
}

/// Confirm with a 1 s hold (a stray tap must not move the show to the other Mac).
struct SwitchConfirmSheet: View {
    @EnvironmentObject var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let name = model.backupMacName ?? L.s("the backup Mac", "バックアップの Mac")
        VStack(spacing: 14) {
            Text(L.s("Switch to the backup?", "バックアップに切り替えますか？")).font(.title3.bold())
            Text(L.s("\(name) becomes the main.", "\(name) がメインになります。")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.s("· The iPhone connects to \(name)", "・iPhone は \(name) につなぎ直します"))
                Text(L.s("· \(name)'s keyboard fires the cues", "・\(name) のキーボードでキューを出せるようになります"))
            }
            .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text(L.s("Cancel", "やめる")).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCell))
                }
                .buttonStyle(.plain)
                VStack(spacing: 2) {
                    Text(L.s("Hold to switch", "長押しで切り替え")).font(.headline)
                    Text(L.s("1 s", "1 秒")).font(.caption.bold())
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkDanger))
                .onLongPressGesture(minimumDuration: 1) { model.switchToBackup(); dismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(L.s("Double-tap and hold to switch", "ダブルタップして長押しで切り替え"))
            }
        }
        .padding(20)
    }
}

/// 2.3: running on the backup Mac after switching.
struct SwitchedBanner: View {
    @EnvironmentObject var model: RemoteModel
    var body: some View {
        Text(L.s("Switched to the backup: \(model.status?.mainName ?? "this Mac") is the main. To go back, use Return to Main on the Mac.",
                 "バックアップに切り替え中：\(model.status?.mainName ?? "この Mac") がメインです。元に戻すときは Mac の画面で「メインに戻す」"))
            .font(.footnote.weight(.bold)).foregroundStyle(Color(red: 0.75, green: 0.87, blue: 1))
            .lineLimit(2).minimumScaleFactor(0.8)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
    }
}
