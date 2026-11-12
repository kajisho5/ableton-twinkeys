import SwiftUI
import TwinKeysCore

/// 2.1 GO screen: Live's scene list is the script. GO launches the scene selected in Live (on both
/// Macs) and moves the selection to the next one. Back / Next only choose; they never play.
/// Works while the show lock is on (scene launch and selection are allowed then).
struct GoView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var lastGo = Date.distantPast
    /// A second GO within this time is ignored (a double tap must not skip a cue).
    static let goGuard: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 12) { nowCard; nextCard; chooseRow }
                        goButton.frame(width: min(300, geo.size.width * 0.36))
                    }
                } else {
                    VStack(spacing: 12) { nowCard; nextCard; goButton.frame(maxHeight: 260); chooseRow }
                }
            }
            .padding(12)
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

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.s("Now playing", "いま再生中")).font(.caption.bold()).foregroundStyle(Color.tkOK)
            if let sc = playing {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(sc.index + 1)").font(.system(size: 30, weight: .heavy)).foregroundStyle(.secondary)
                    Text(sc.name.isEmpty ? L.s("Scene \(sc.index + 1)", "シーン \(sc.index + 1)") : sc.name)
                        .font(.system(size: 26, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                }
                if let t = playingTracks.first, let left = live.secondsLeft(track: t) {
                    HStack(spacing: 10) {
                        Text(L.s("Left", "残り")).font(.caption).foregroundStyle(.secondary)
                        Text(formatTimeLeft(left)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Color.tkOK)
                        if let p = live.progress[t], p.count == 2, p[1] > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tkCell)
                                    Capsule().fill(Color.tkOK).frame(width: g.size.width * min(1, p[0] / p[1]))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                let names = playingTracks.prefix(3).compactMap { t -> String? in
                    guard t < live.clips.count, sc.index < live.clips[t].count else { return nil }
                    let n = live.clips[t][sc.index].name
                    return n.isEmpty ? nil : n
                }
                if !names.isEmpty { Text(names.joined(separator: " ・ ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                Text(L.s("Nothing playing", "再生中のシーンはありません")).font(.title3.bold()).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.tkCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(playing == nil ? Color.clear : Color.tkOK, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.s("Next", "次")).font(.caption.bold()).foregroundStyle(Color.tkAccent)
            if let sc = next {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(sc.index + 1)").font(.system(size: 26, weight: .heavy)).foregroundStyle(.secondary)
                    Text(sc.name.isEmpty ? L.s("Scene \(sc.index + 1)", "シーン \(sc.index + 1)") : sc.name)
                        .font(.system(size: 22, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(L.s("The scene selected in Live", "Live で選んでいるシーン")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L.s("End of the scene list", "シーンの最後です")).font(.title3.bold()).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.tkCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }

    private var chooseRow: some View {
        HStack(spacing: 8) {
            chooseButton(L.s("◀ Back", "◀ 前へ"), to: nextIndex - 1)
            chooseButton(L.s("Next ▶", "次へ ▶"), to: nextIndex + 1)
            Text(L.s("Only chooses (does not play)", "選ぶだけ（鳴らさない）")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseButton(_ title: String, to i: Int) -> some View {
        Button { model.run(.selectScene(i)) } label: {
            Text(title).font(.headline).frame(maxWidth: 160, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCell))
        }
        .buttonStyle(.plain)
        .disabled(i < 0 || i >= live.scenes.count)
    }

    private var goButton: some View {
        Button(action: go) {
            VStack(spacing: 10) {
                Text("GO").font(.system(size: 64, weight: .black))
                Text(L.s("Play the next scene", "次のシーンを再生")).font(.subheadline.bold())
                if let sc = next { Text("\(sc.index + 1)  \(sc.name)").font(.headline).lineLimit(1).minimumScaleFactor(0.6) }
                Spacer(minLength: 0)
                Text(L.s("Works with the show lock on", "本番ロック中も使えます")).font(.caption.bold())
            }
            .padding(.top, 40).padding(.bottom, 16).padding(.horizontal, 12)
            .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.06))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(next == nil ? Color.secondary : Color.tkOK))
        }
        .buttonStyle(.plain)
        .disabled(next == nil)
        .accessibilityLabel(next.map { L.s("GO: play scene \($0.index + 1) \($0.name)", "GO：シーン \($0.index + 1) \($0.name) を再生") } ?? "GO")
    }

    private func go() {
        guard Date().timeIntervalSince(lastGo) >= Self.goGuard, let sc = next else { return }
        lastGo = Date()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        model.run(.fireScene(sc.index))
        if sc.index + 1 < live.scenes.count { model.run(.selectScene(sc.index + 1)) }
    }
}
