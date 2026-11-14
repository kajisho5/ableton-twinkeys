import SwiftUI

// QLab mode on the Apple Watch (docs/design-qlab.md 4.3, docs/design/qlab-watch.png): three pages,
// swiped left and right. M · B are the two Macs, Q both QLabs; the ring is the running cue's time left.

/// M · B · Q lamps.
struct QLabLamps: View {
    @EnvironmentObject var model: WatchModel
    var withQ = true

    var body: some View {
        let st = model.state
        let ok = model.problem == nil
        HStack(spacing: 14) {
            lamp("M", ok && st?.connected == true)
            lamp("B", ok && st?.backupOK == true || ok && st?.qlabOK == true)
            if withQ { lamp("Q", ok && st?.qlabOK == true) }
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(TK.read)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(st?.qlabOK == true && ok ? L.s("Both Macs and QLabs connected", "2台の Mac と QLab がつながっています")
                                                     : L.s("Not everything is connected", "つながっていないものがあります"))
    }

    private func lamp(_ name: String, _ on: Bool) -> some View {
        HStack(spacing: 4) { LED(color: on ? TK.accent : TK.yellow, size: 6); Text(name) }
    }
}

// MARK: 1. GO

struct QLabGoPage: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            VStack(spacing: 4) {
                QLabLamps()
                if let why = model.notice ?? model.problem {
                    Text(why).font(.system(size: 13, weight: .bold)).foregroundStyle(TK.yellow)
                        .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                } else {
                    Text(model.state?.qlabNow ?? L.s("No cue running", "動いているキューはありません"))
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(model.state?.qlabNow == nil ? TK.dim : TK.read)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                goButton(ctx.date)
                Text(model.state?.qlabNext.map { "NEXT \($0)" } ?? L.s("Nothing standing by", "待機中のキューはありません"))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(TK.read)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
        }
    }

    private func goButton(_ now: Date) -> some View {
        let on = model.canQLabGo
        let left = model.qlabLeftNow(now)
        let total = model.state?.qlabTotal ?? 0
        let fraction = left.map { total > 0 ? $0 / total : 0 } ?? 0
        return Button { model.qlabGo() } label: {
            ZStack {
                Circle().stroke(TK.off, lineWidth: 6)
                // The ring: the running cue's time left (QLab tells the length, so it is the real share).
                Circle().trim(from: 0, to: fraction)
                    .stroke(TK.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: TK.accent.opacity(0.5), radius: 4)
                Circle()
                    .fill(LinearGradient(colors: on ? [TK.keyTop, TK.keyBottom] : [TK.panel, TK.panel], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(on ? TK.accent : TK.stroke, lineWidth: 1.5))
                    .padding(12)
                VStack(spacing: 2) {
                    Text("GO").font(.system(size: 40, weight: .heavy, design: .monospaced)).minimumScaleFactor(0.6)
                        .foregroundStyle(on ? TK.accent : TK.dim)
                        .shadow(color: on ? TK.accent.opacity(0.5) : .clear, radius: 6)
                    if let left {
                        Text(WatchState.formatLeft(left)).font(.system(size: 14, weight: .bold, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(TK.accentSoft)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.state?.qlabNext.map { L.s("GO: QLab cue \($0)", "GO：QLab のキュー \($0)") } ?? "GO")
    }
}

// MARK: 2. The cue list

struct QLabCuesPage: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    if let warn = model.notice ?? model.problem {
                        Text(warn).font(.system(size: 14, weight: .bold)).foregroundStyle(TK.yellow)
                            .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    } else {
                        Text("CUES").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(TK.accent)
                            .accessibilityLabel(L.s("Cues", "キュー"))
                    }
                    ForEach(Array((model.state?.qlabCues ?? []).enumerated()), id: \.offset) { i, c in row(c).id(i) }
                    Text(L.s("Tap to move the playhead", "タップで再生位置を移す"))
                        .font(.system(size: 12)).foregroundStyle(TK.dim).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                if let i = model.state?.qlabCues.firstIndex(where: \.next) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    private func row(_ c: WatchQLabCue) -> some View {
        Button { model.qlabMove(c.number) } label: {
            HStack(spacing: 8) {
                Text(c.number.isEmpty ? "—" : c.number).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(TK.dim)
                Text(c.name).foregroundStyle(TK.read).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if c.running {
                    LED(size: 6)
                } else if c.next {
                    Text("NEXT").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(TK.blue)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.running ? TK.keyTop : TK.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.running ? TK.accent : c.next ? TK.blue : TK.stroke,
                                                                    lineWidth: c.running || c.next ? 1.5 : TK.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("Cue \(c.number) \(c.name)", "キュー \(c.number) \(c.name)")
                            + (c.running ? L.s(", running", "、動いています") : c.next ? L.s(", next", "、次") : ""))
    }
}

// MARK: 3. PANIC (both Macs)

struct QLabPanicPage: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        VStack(spacing: 8) {
            QLabLamps(withQ: false)
            Button { model.qlabPanic() } label: {
                VStack(spacing: 4) {
                    Text("PANIC").font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(TK.red)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityHidden(true)
                    Text(L.s("Stop QLab on both Macs", "QLab を2台とも止める")).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TK.redSoft).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NotesOffBackground(radius: 22, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            Text(model.notice ?? L.s("Again: stop at once", "もう一度で即停止"))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(model.notice == nil ? TK.read : TK.yellow)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
    }
}
