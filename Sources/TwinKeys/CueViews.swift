#if os(macOS)
import SwiftUI
import TwinKeysCore

/// "Last cue" panel: which cue went out (or came in), how many since connecting,
/// and whether the backup confirmed it. See docs/design/cuekeys-panel-*.svg and cue-states-*.svg.
struct CuePanel: View {
    let state: ViewState
    private var t: Strings { state.t }
    /// Backup side: this Mac only receives.
    private var isBackupView: Bool {
        if let c = state.lastCue { return c.delivery == .received }
        return !state.sendKeys && state.receiveNotes
    }

    var body: some View {
        TKGroup(border: state.lastCue?.delivery == .missing ? Theme.dangerText : Theme.separator) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    cueSide.frame(minWidth: 200, alignment: .leading)
                    Rectangle().fill(Theme.separator).frame(width: 1, height: 64)
                    statusSide.frame(width: 236, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    cueSide
                    Rectangle().fill(Theme.separator).frame(height: 1)
                    statusSide
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var cueSide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isBackupView ? t.receivedCue : t.lastCue)
                .font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if let c = state.lastCue {
                HStack(spacing: 14) {
                    Text(c.label)
                        .font(.system(size: c.label.count > 2 ? 15 : 24, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(minWidth: 64, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.windowBackground))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.buttonBorder, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.memo.isEmpty ? noteName(c.note) : c.memo)
                            .font(.system(size: Theme.value, weight: .bold)).lineLimit(1)
                        Text(t.cueCount(c.count))
                            .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    }
                }
            } else {
                Text(isBackupView ? t.noCueReceivedYet : t.noCueYet)
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var statusSide: some View {
        if let c = state.lastCue {
            let s = status(c)
            HStack(alignment: .top, spacing: 8) {
                badge(s.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(.system(size: Theme.body, weight: s.kind == .bad ? .bold : .semibold))
                        .foregroundStyle(s.kind == .bad ? Theme.dangerText : Theme.textPrimary)
                    if !s.detail.isEmpty {
                        Text(s.detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            Text(state.cueKeys.isEmpty ? t.cueKeysNone : state.cueKeys.map(\.label).joined(separator: "  "))
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum Kind { case good, bad, neutral, waiting }

    private func status(_ c: CueStatus) -> (kind: Kind, title: String, detail: String) {
        let peer = c.peerName ?? ""
        switch c.delivery {
        case let .delivered(ms):
            return (.good, t.deliveredToBackup, peer.isEmpty ? state.latencyText(ms) : "\(peer)  ·  \(state.latencyText(ms))")
        case .waiting: return (.waiting, t.waitingForBackup, peer)
        case .missing: return (.bad, t.notConfirmed, t.notConfirmedDetail)
        case .unconfirmed: return (.neutral, t.cannotConfirm, t.cannotConfirmDetail)
        case .notConnected: return (.neutral, t.cueNotConnected, t.cueNotConnectedDetail)
        case .received: return (.good, t.receivedFromMain, peer)
        }
    }

    @ViewBuilder private func badge(_ k: Kind) -> some View {
        ZStack {
            Circle().fill(k == .good ? Theme.ok : k == .bad ? Theme.dangerFill : Theme.idleDot).frame(width: 18, height: 18)
            switch k {
            case .good: Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            case .bad: Text("!").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            case .neutral: Text("–").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            case .waiting: ProgressView().controlSize(.mini)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Banner shown when an update has been downloaded, or one must be fetched by hand.
struct UpdateBanner: View {
    let state: ViewState
    let actions: ViewActions
    private var t: Strings { state.t }

    var body: some View {
        switch state.update {
        case let .ready(v):
            banner(title: t.updateReady(v), detail: t.updateReadyDetail) {
                if state.canRestartForUpdate {
                    Button(t.restartNow, action: actions.restartForUpdate).buttonStyle(TKButtonStyle())
                }
            }
        case let .manual(v, reason):
            banner(title: t.updateManual(v), detail: t.updateManualDetail(reason)) {
                Button(t.openReleasePage, action: actions.openReleasePage).buttonStyle(TKButtonStyle())
            }
        default:
            EmptyView()
        }
    }

    private func banner<B: View>(title: String, detail: String, @ViewBuilder button: () -> B) -> some View {
        let b = button()
        return TKGroup {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { texts(title, detail); Spacer(minLength: 8); b }
                VStack(alignment: .leading, spacing: 8) { texts(title, detail); b }
            }
            .padding(12)
        }
    }

    private func texts(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
