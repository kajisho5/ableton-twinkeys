import SwiftUI
import TwinKeysCore

/// First screen: pairing code, Macs nearby, and the 4-digit code while the Mac asks for approval.
struct PairView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var code = ""
    @State private var invalid = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        LED(size: 9)
                        Text("TwinKeys Remote").font(.system(.largeTitle, design: .monospaced, weight: .bold)).foregroundStyle(TK.read)
                            .minimumScaleFactor(0.6)
                    }
                    Text(L.s("Enter the same pairing code as TwinKeys on your Mac", "Mac の TwinKeys と同じ合言葉を入れてください"))
                        .font(.subheadline).foregroundStyle(TK.dim).multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                TextField("K7MQ2-WX9TP", text: $code)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(TK.read)
                    .padding(14)
                    .tkPanel(radius: 10, fill: TK.bg, stroke: invalid ? TK.red : TK.accent, lineWidth: 1.5)
                    .onSubmit(save)
                    .onAppear { code = model.pairingCode }
                    .accessibilityLabel(L.s("Pairing code", "合言葉"))
                if invalid {
                    Text(L.s("10 letters and digits (no 0, 1, I, L or O).", "10文字の英数字です（0・1・I・L・O は使いません）。"))
                        .font(.footnote).foregroundStyle(Color.tkDanger)
                }
                Button(action: save) { Text(L.s("Save", "保存")).font(.headline).frame(minWidth: 120) }
                    .buttonStyle(TKButtonStyle(kind: .green, radius: 10, minHeight: 50))

                statusBox

                if !model.macs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.s("TwinKeys nearby", "近くの TwinKeys")).font(TK.mono(.footnote)).tracking(1).foregroundStyle(TK.dim)
                        ForEach(model.macs) { mac in
                            HStack {
                                LED(size: 7)
                                Image(systemName: "desktopcomputer").foregroundStyle(TK.accent)
                                Text(mac.id).font(.body.weight(.semibold)).foregroundStyle(TK.read)
                                Spacer()
                                Button { model.connect(mac) } label: { Text(L.s("Connect", "接続")).font(.subheadline.bold()) }
                                    .buttonStyle(TKButtonStyle(kind: .green, radius: 8, minHeight: 40))
                                    .disabled(model.pairingCode.isEmpty)
                            }
                            .padding(12)
                            .frame(minHeight: 52)
                            .tkPanel(radius: 10)
                        }
                    }
                }

                // Without a Mac (App Review, or a first look): fictional data, nothing is sent.
                // Two samples: Live (scenes and clips) or QLab (cue list and GO). docs/design-qlab-demo.md 3.
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(TK.stroke).frame(height: TK.line).padding(.bottom, 8)
                        .accessibilityHidden(true)
                    SmallCaps(L.s("NO MAC NEEDED TO TRY", "MAC がなくても試せます"),
                              spoken: L.s("No Mac needed to try", "Mac がなくても試せます"))
                        .accessibilityAddTraits(.isHeader)
                    sampleButtons
                    Text(L.s("Shows the screens with made-up data. Nothing is sent to a Mac.",
                             "架空のデータで画面を試せます。Mac には何も送りません。"))
                        .font(.footnote).foregroundStyle(TK.dim).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.top, 12).padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    /// The two sample buttons side by side (one above the other with the largest text sizes).
    @ViewBuilder private var sampleButtons: some View {
        let live = sampleButton(target: .live, symbol: "square.grid.3x3.fill",
                                title: L.s("Live sample", "Live のサンプル"),
                                note: L.s("Scenes and clips", "シーンとクリップ"), kind: .plain)
        let qlab = sampleButton(target: .qlab, symbol: "list.bullet",
                                title: L.s("QLab sample", "QLab のサンプル"),
                                note: L.s("Cue list and GO", "キューの一覧と GO"), kind: .green)
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { live; qlab }
        } else {
            HStack(spacing: 12) { live; qlab }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sampleButton(target: QLabTarget, symbol: String, title: String, note: String, kind: TKButtonStyle.Kind) -> some View {
        Button { model.startTrial(target: target) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title).font(.headline).multilineTextAlignment(.center)
                    .foregroundStyle(TK.read)
                Text(note).font(.caption).foregroundStyle(TK.dim).multilineTextAlignment(.center)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TKButtonStyle(kind: kind, radius: 10, minHeight: 104))
        .accessibilityLabel(title)
        .accessibilityHint(L.s("Opens the app with made-up data. \(note).", "架空のデータで開きます。\(note)。"))
    }

    private func save() {
        invalid = !model.savePairingCode(code)
        if !invalid { code = model.pairingCode }
    }

    @ViewBuilder private var statusBox: some View {
        switch model.phase {
        case let .waitingForApproval(c):
            VStack(spacing: 8) {
                Text(L.s("Allow this iPhone on the Mac", "Mac の画面で許可してください")).font(.headline).foregroundStyle(TK.read)
                Text(L.s("Check that the Mac shows the same number", "Mac に出ている番号と同じか確かめてください"))
                    .font(.footnote).foregroundStyle(TK.dim)
                Text(c.map { String($0) }.joined(separator: " "))
                    .font(.system(size: 44, weight: .heavy, design: .monospaced)).foregroundStyle(TK.accent)
                    .shadow(color: TK.accent.opacity(0.4), radius: 8)
                    .accessibilityLabel(L.s("Code \(c)", "番号 \(c)"))
            }
            .padding(18).frame(maxWidth: .infinity)
            .tkPanel(radius: 12, stroke: TK.accent, lineWidth: 1.5)
        case let .connecting(name):
            Label(L.s("Connecting to \(name)…", "\(name) に接続中…"), systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(TK.dim)
        case .searching:
            Label(L.s("Looking for TwinKeys on this network…", "このネットワークで TwinKeys を探しています…"), systemImage: "magnifyingglass").foregroundStyle(TK.dim)
        case .denied:
            Label(L.s("The Mac did not allow this iPhone.", "Mac で許可されませんでした。"), systemImage: "xmark.octagon").foregroundStyle(Color.tkDanger)
        case let .failed(why):
            Label(why == "code" ? L.s("The pairing code does not match the Mac.", "合言葉が Mac と違います。")
                                : L.s("Connection lost. Retrying…", "接続が切れました。つなぎ直しています…"),
                  systemImage: "exclamationmark.triangle").foregroundStyle(Color.tkWarn)
        default:
            EmptyView()
        }
    }
}
