import SwiftUI
import TwinKeysCore

/// First screen: pairing code, Macs nearby, and the 4-digit code while the Mac asks for approval.
struct PairView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var code = ""
    @State private var invalid = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("TwinKeys Remote").font(.largeTitle.bold())
                    Text(L.s("Enter the same pairing code as TwinKeys on your Mac", "Mac の TwinKeys と同じ合言葉を入れてください"))
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                TextField("K7MQ2-WX9TP", text: $code)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCard))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(invalid ? Color.tkDanger : Color.tkAccent, lineWidth: 1.5))
                    .onSubmit(save)
                    .onAppear { code = model.pairingCode }
                    .accessibilityLabel(L.s("Pairing code", "合言葉"))
                if invalid {
                    Text(L.s("10 letters and digits (no 0, 1, I, L or O).", "10文字の英数字です（0・1・I・L・O は使いません）。"))
                        .font(.footnote).foregroundStyle(Color.tkDanger)
                }
                Button(L.s("Save", "保存"), action: save)
                    .buttonStyle(.borderedProminent).controlSize(.large)

                statusBox

                if !model.macs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.s("TwinKeys nearby", "近くの TwinKeys")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(model.macs) { mac in
                            HStack {
                                Image(systemName: "desktopcomputer").foregroundStyle(Color.tkOK)
                                Text(mac.id).font(.body.weight(.semibold))
                                Spacer()
                                Button(L.s("Connect", "接続")) { model.connect(mac) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.pairingCode.isEmpty)
                            }
                            .padding(12)
                            .frame(minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tkCard))
                        }
                    }
                }

                // Without a Mac (App Review, or a first look): fictional data, nothing is sent.
                VStack(spacing: 6) {
                    Button(L.s("Try with sample data", "サンプルで試す")) { model.startTrial() }
                        .buttonStyle(.bordered).controlSize(.large)
                    Text(L.s("Shows the screens with made-up data. Nothing is sent to a Mac.",
                             "架空のデータで画面を試せます。Mac には何も送りません。"))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 12).padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func save() {
        invalid = !model.savePairingCode(code)
        if !invalid { code = model.pairingCode }
    }

    @ViewBuilder private var statusBox: some View {
        switch model.phase {
        case let .waitingForApproval(c):
            VStack(spacing: 8) {
                Text(L.s("Allow this iPhone on the Mac", "Mac の画面で許可してください")).font(.headline)
                Text(L.s("Check that the Mac shows the same number", "Mac に出ている番号と同じか確かめてください"))
                    .font(.footnote).foregroundStyle(.secondary)
                Text(c.map { String($0) }.joined(separator: " "))
                    .font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Color.tkAccent)
                    .accessibilityLabel(L.s("Code \(c)", "番号 \(c)"))
            }
            .padding(18).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.tkCard))
        case let .connecting(name):
            Label(L.s("Connecting to \(name)…", "\(name) に接続中…"), systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.secondary)
        case .searching:
            Label(L.s("Looking for TwinKeys on this network…", "このネットワークで TwinKeys を探しています…"), systemImage: "magnifyingglass").foregroundStyle(.secondary)
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
