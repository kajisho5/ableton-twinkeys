import SwiftUI
import TwinKeysCore

/// 2.1 GO screen: Live's scene list is the script. GO launches the scene selected in Live (on both
/// Macs) and moves the selection to the next one. Back / Next only choose; they never play.
/// Works while the show lock is on (scene launch and selection are allowed then).
struct GoView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var lastGo = Date.distantPast
    /// Landscape iPhone: little height, so smaller cards.
    @State private var tight = false
    /// A second GO within this time is ignored (a double tap must not skip a cue).
    static let goGuard: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: tight ? 8 : 12) { nowCard; nextCard; Spacer(minLength: 0); chooseRow }
                        goButton.frame(width: min(300, geo.size.width * 0.36))
                    }
                } else {
                    VStack(spacing: 12) { nowCard; nextCard; goButton.frame(maxHeight: 260); chooseRow }
                }
            }
            .padding(tight ? 8 : 12)
            .onAppear { tight = geo.size.height < 340 }
            .onChange(of: geo.size) { sz in tight = sz.height < 340 }
        }
    }

    // MARK: Pieces

    private var live: LiveState { model.live }
    private var playing: LiveScene? { live.scenes.first { $0.playing } }
    private var nextIndex: Int { live.song.selectedScene }
    private var next: LiveScene? { nextIndex >= 0 && nextIndex < live.scenes.count ? live.scenes[nextIndex] : nil }

    /// Tracks playing a clip of the playing scene, longest time left first.
    private var playingTracks: [Int] {
        guard let sc = playing?.index else { return [] }
        return live.tracks.filter { $0.playingSlot == sc }.map(\.index)
            .sorted { (live.secondsLeft(track: $0) ?? 0) > (live.secondsLeft(track: $1) ?? 0) }
    }

    /// "03": two digits on the cards and GO (A1); VoiceOver reads the plain number.
    private func number(_ i: Int, size: CGFloat) -> some View {
        Text(String(format: "%02d", i + 1)).font(.system(size: size, weight: .bold, design: .monospaced)).monospacedDigit()
            .foregroundStyle(TK.dim)
            .accessibilityLabel("\(i + 1)")
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCaps("NOW PLAYING", color: TK.accent, spoken: L.s("Now playing", "いま再生中"))
            if let sc = playing {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    number(sc.index, size: tight ? 24 : 30)
                    Text(sc.name.isEmpty ? L.s("Scene \(sc.index + 1)", "シーン \(sc.index + 1)") : sc.name)
                        .font(.system(size: tight ? 21 : 26, weight: .heavy)).foregroundStyle(TK.read)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if let t = playingTracks.first, let left = live.secondsLeft(track: t) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            SmallCaps("REMAIN", spoken: L.s("Left", "残り"))
                            Text(formatTimeLeft(left)).font(TK.mono(tight ? .headline : .title3)).monospacedDigit().foregroundStyle(TK.accent)
                        }
                        if let p = live.progress[t], p.count == 2, p[1] > 0 {
                            SegmentMeter(value: p[0] / p[1], segments: 40)
                                .frame(height: tight ? 10 : 14)
                                .padding(.bottom, 4)
                        }
                    }
                }
                let names = playingTracks.prefix(3).compactMap { t -> String? in
                    guard t < live.clips.count, sc.index < live.clips[t].count else { return nil }
                    let n = live.clips[t][sc.index].name
                    return n.isEmpty ? nil : n
                }
                if !names.isEmpty, !tight { Text(names.joined(separator: " ・ ")).font(.caption).foregroundStyle(TK.dim).lineLimit(1) }
            } else {
                Text(L.s("Nothing playing", "再生中のシーンはありません")).font(.title3.bold()).foregroundStyle(TK.dim)
            }
        }
        .padding(tight ? 10 : 16)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tkPanel(radius: 10)
        // A green bar at the left edge while a scene plays.
        .overlay(alignment: .leading) {
            if playing != nil { TK.accent.frame(width: 3).shadow(color: TK.accent.opacity(0.6), radius: 4) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCaps("NEXT", color: TK.accentSoft, spoken: L.s("Next", "次"))
            if let sc = next {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    number(sc.index, size: tight ? 20 : 26)
                    Text(sc.name.isEmpty ? L.s("Scene \(sc.index + 1)", "シーン \(sc.index + 1)") : sc.name)
                        .font(.system(size: tight ? 18 : 22, weight: .heavy)).foregroundStyle(TK.read)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if !tight { Text(L.s("The scene selected in Live", "Live で選んでいるシーン")).font(.caption).foregroundStyle(TK.dim) }
            } else {
                Text(L.s("End of the scene list", "シーンの最後です")).font(.title3.bold()).foregroundStyle(TK.dim)
            }
        }
        .padding(tight ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tkPanel(radius: 10)
        .accessibilityElement(children: .combine)
    }

    private var chooseRow: some View {
        HStack(spacing: 8) {
            chooseButton(L.s("◀ Back", "◀ 前へ"), to: nextIndex - 1)
            chooseButton(L.s("Next ▶", "次へ ▶"), to: nextIndex + 1)
            Text(L.s("Only chooses (does not play)", "選ぶだけ（鳴らさない）")).font(.caption).foregroundStyle(TK.dim)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseButton(_ title: String, to i: Int) -> some View {
        Button { model.run(.selectScene(i)) } label: {
            Text(title).font(.headline).frame(maxWidth: 160, minHeight: tight ? 44 : 56)
        }
        .buttonStyle(TKButtonStyle(radius: 10, minHeight: tight ? 44 : 56))
        .disabled(i < 0 || i >= live.scenes.count)
    }

    private var goButton: some View {
        let on = next != nil
        return Button(action: go) {
            VStack(spacing: 10) {
                Text("GO").font(.system(size: 88, weight: .heavy, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(on ? TK.accent : TK.dim)
                    .shadow(color: on ? TK.accent.opacity(0.5) : .clear, radius: 12)
                Text(L.s("Play the next scene", "次のシーンを再生")).font(.subheadline.bold()).foregroundStyle(TK.accentSoft)
                if let sc = next {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("NEXT ▸").font(TK.mono(.caption)).accessibilityHidden(true)
                        Text("\(String(format: "%02d", sc.index + 1))  \(sc.name)").font(.headline)
                    }
                    .foregroundStyle(TK.accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                Text(L.s("Works with the show lock on", "本番ロック中も使えます")).font(TK.mono(.caption2)).tracking(1)
                    .foregroundStyle(TK.dim).multilineTextAlignment(.center)
            }
            .padding(.top, 40).padding(.bottom, 16).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoKeyBackground(enabled: on, radius: 18))
        }
        .buttonStyle(.plain)
        .disabled(next == nil)
        .accessibilityLabel(next.map { L.s("GO: play scene \($0.index + 1) \($0.name)", "GO：シーン \($0.index + 1) \($0.name) を再生") } ?? "GO")
    }

    private func go() {
        guard Date().timeIntervalSince(lastGo) >= Self.goGuard, let sc = next else { return }
        lastGo = Date()
        model.go(scene: sc.index)
    }
}
