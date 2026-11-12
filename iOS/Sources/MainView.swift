import SwiftUI
import TwinKeysCore

enum Pane: String, CaseIterable, Identifiable {
    case session, mixer, cues, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .session: return L.s("Session", "セッション")
        case .mixer: return L.s("Mixer", "ミキサー")
        case .cues: return L.s("Cues", "キュー")
        case .settings: return L.s("Settings", "設定")
        }
    }
    var symbol: String {
        switch self {
        case .session: return "square.grid.3x3.fill"
        case .mixer: return "slider.vertical.3"
        case .cues: return "bolt.fill"
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

    var body: some View {
        GeometryReader { geo in
            let lc = LayoutClass.of(geo.size)
            VStack(spacing: 0) {
                TopBar(compact: lc == .narrowPortrait)
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
                    if pane == .session || pane == .cues {
                        HStack(alignment: .top, spacing: 12) {
                            SessionView(showSceneColumn: false).frame(maxWidth: .infinity)
                            CuesView().frame(width: min(300, geo.size.width * 0.4))
                        }
                        .padding(.horizontal, 12)
                    } else {
                        content(pane, lc).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    tabBar(panes: [.session, .mixer, .settings])
                case .wide:
                    if pane == .settings {
                        SettingsPane().frame(maxWidth: 640)
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
                    tabBar(panes: [.session, .settings])
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
        case .settings: SettingsPane()
        }
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
    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(Pane.allCases) { p in
                Button { pane = p } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.symbol).font(.system(size: 20))
                        Text(p.title).font(.system(size: 10, weight: pane == p ? .bold : .regular))
                    }
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: 10).fill(pane == p ? Color.tkCell : .clear))
                    .foregroundStyle(pane == p ? Color.tkAccent : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 68)
        .background(Color.tkBar.ignoresSafeArea(edges: .trailing))
        .overlay(alignment: .leading) { Divider() }
    }
}

/// Always on top: link status, play / stop, tempo, position, All Notes Off and the show lock.
struct TopBar: View {
    @EnvironmentObject var model: RemoteModel
    var compact: Bool
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
        return HStack(spacing: 8) {
            Circle().fill(st?.mainLiveConnected == true ? Color.tkOK : Color.tkWarn).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(st?.mainName ?? "TwinKeys").font(.subheadline.bold()).lineLimit(1)
                Text(backupOK ? L.s("Backup ✓", "バックアップ ✓") + (st?.latencyMs.map { " · \(Int($0.rounded())) ms" } ?? "")
                              : L.s("Backup not linked", "バックアップ未接続"))
                    .font(.caption).foregroundStyle(backupOK ? Color.secondary : Color.tkWarn).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
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
        default: return L.s("Live did not run it (\(error)).", "Live で実行できませんでした（\(error)）。")
        }
    }
}
