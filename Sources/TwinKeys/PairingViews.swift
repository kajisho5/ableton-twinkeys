#if os(macOS)
import AppKit
import Network
import SwiftUI
import TwinKeysCore

/// The pairing code, with actions. Used in the sheet from the main window and in Settings.
struct PairingPanel: View {
    let state: ViewState
    let actions: ViewActions
    @State private var entering = false
    @State private var typed = ""
    @State private var invalid = false
    @State private var confirmNew = false
    private var t: Strings { state.t }

    var body: some View {
        if entering { entryForm } else { overview }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.pairingExplain)
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(t.thisMacCode).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(t.thisMacAddress(addressText))
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
            Text(state.pairingCode ?? t.noCodeYet)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(state.pairingCode == nil ? Theme.textSecondary : Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.groupBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.buttonBorder, lineWidth: 1))
                .accessibilityLabel("\\(t.thisMacCode): \\(spelled(state.pairingCode) ?? t.noCodeYet)")
            HStack(spacing: 8) {
                Button(t.makeNewCode) {
                    if state.pairingCode == nil { actions.makeNewPairingCode() } else { confirmNew = true }
                }
                .buttonStyle(TKButtonStyle(kind: state.pairingCode == nil ? .primary : .normal))
                Button(t.copy, action: actions.copyPairingCode)
                    .buttonStyle(TKButtonStyle())
                    .disabled(state.pairingCode == nil)
            }
            Text(t.haveOtherCode).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            Button(t.enterCode) { typed = ""; invalid = false; entering = true }
                .buttonStyle(TKButtonStyle())
        }
        .confirmationDialog(t.replaceCodeTitle, isPresented: $confirmNew) {
            Button(t.makeNew, role: .destructive, action: actions.makeNewPairingCode)
            Button(t.cancel, role: .cancel) {}
        } message: { Text(t.replaceCodeMessage) }
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.enterCodeTitle).font(.system(size: 15, weight: .semibold))
            Text(t.enterCodeExplain)
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("XXXXX-XXXXX", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .onSubmit(save)
                .accessibilityLabel(t.enterCodeTitle)
            Text(invalid ? t.invalidCode : t.enterCodeRule)
                .font(.system(size: Theme.caption))
                .foregroundStyle(invalid ? Theme.warning : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(t.cancel) { entering = false }.buttonStyle(TKButtonStyle()).keyboardShortcut(.cancelAction)
                Button(t.save, action: save).buttonStyle(TKButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        if actions.savePairingCode(typed) { entering = false } else { invalid = true }
    }

    private var addressText: String {
        guard !state.localAddresses.isEmpty else { return t.noAddress }
        return state.localAddresses.joined(separator: ", ")
    }

    /// VoiceOver reads the code character by character.
    private func spelled(_ code: String?) -> String? {
        code.map { $0.filter { $0 != "-" }.map(String.init).joined(separator: " ") }
    }
}

/// Sheet with the pairing panel (from the main window).
struct PairingSheet: View {
    let state: ViewState
    let actions: ViewActions
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.t.pairingTitle).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            PairingPanel(state: state, actions: actions)
            HStack {
                Spacer()
                Button(state.t.done) { actions.setSheet(nil) }
                    .buttonStyle(TKButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
        .onExitCommand { actions.setSheet(nil) }
    }
}

/// "Connect by IP Address" sheet.
struct ConnectByIPSheet: View {
    let state: ViewState
    let actions: ViewActions
    @State private var address = ""
    @State private var invalid = false
    private var t: Strings { state.t }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.connectByIPTitle).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(t.connectByIPExplain)
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("192.168.1.20", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(width: 260)
                    .onSubmit(connect)
                    .accessibilityLabel(t.connectByIPTitle)
                Text(t.portLabel(NetworkService.fixedPort)).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            }
            if invalid {
                Text(t.invalidAddress).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
            }
            if !state.isPaired {
                Text(t.pairingNeeded).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
            }
            Text(t.thisMacAddress(state.localAddresses.isEmpty ? t.noAddress : state.localAddresses.joined(separator: ", ")))
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button(t.cancel) { actions.setSheet(nil) }.buttonStyle(TKButtonStyle()).keyboardShortcut(.cancelAction)
                Button(t.connect, action: connect)
                    .buttonStyle(TKButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.isPaired)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
        .onAppear { address = state.lastManualAddress }
        .onExitCommand { actions.setSheet(nil) }
    }

    private func connect() {
        if actions.connectByAddress(address) { actions.setSheet(nil) } else { invalid = true }
    }
}

enum AddressCheck {
    /// IPv4 or IPv6 literal, optionally with a port ("192.168.1.20:47802", "[fe80::1%en0]:47802").
    /// No host names: those need Bonjour or DNS. A link-local IPv6 address needs its interface
    /// ("%en0"), otherwise macOS cannot tell where to send it.
    static func isValid(_ s: String) -> Bool {
        guard let (host, _) = ManualAddress.parse(s) else { return false }
        if IPv4Address(host) != nil { return true }
        guard IPv6Address(host) != nil else { return false }
        return !host.lowercased().hasPrefix("fe80") || host.contains("%")
    }
}
#endif
