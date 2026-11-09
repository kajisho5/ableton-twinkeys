#if os(macOS)
import SwiftUI
import TwinKeysCore

struct ContentView: View {
    let state: ViewState
    let actions: ViewActions
    @State private var showingHelp = false
    private var t: Strings { state.t }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.groupSpacing) {
                    if state.inputMonitoring != .granted && state.sendKeys { permissionBanner }
                    if !state.midiPortReady || !state.problems.isEmpty { problemBanner }
                    peersSection
                    modeSection
                    permissionRow
                }
                .padding(Theme.outerPadding)
            }
        }
        .frame(minWidth: Theme.minWindow.width, minHeight: Theme.minWindow.height)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
        .font(.system(size: Theme.body))
        .sheet(isPresented: $showingHelp) { HelpView(t: t, onClose: { showingHelp = false }, actions: actions) }
    }

    // MARK: Header (always visible: status + panic)

    private var statusColor: Color {
        switch state.link {
        case .connected: return Theme.ok
        case .connecting: return Theme.warning
        case .notConnected: return state.peers.isEmpty ? Theme.warning : Theme.idleDot
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusDot(color: statusColor, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.headline).font(.system(size: Theme.body, weight: .semibold)).lineLimit(1)
                Text(state.detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(t.statusLabel(state.headline, state.detail))
            Spacer(minLength: 8)
            Button(t.allNotesOff, action: actions.panic)
                .buttonStyle(TKButtonStyle(kind: .destructive))
                .help(t.allNotesOffHelp)
                .accessibilityHint(t.allNotesOffHint)
        }
        .padding(.horizontal, Theme.outerPadding)
        .padding(.vertical, 12)
    }

    // MARK: Banners

    private var permissionBanner: some View {
        TKGroup(border: Theme.warning) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warning)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.needsInputMonitoring)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(t.openSystemSettings, action: actions.openInputMonitoringSettings)
                            .buttonStyle(TKButtonStyle(kind: .primary))
                            .accessibilityHint(t.openSystemSettingsHint)
                        Button(t.checkAgain, action: actions.recheckPermissions)
                            .buttonStyle(TKButtonStyle())
                    }
                }
            }
            .padding(12)
        }
    }

    private var problemBanner: some View {
        TKGroup(border: Theme.warning) {
            VStack(alignment: .leading, spacing: 4) {
                if !state.midiPortReady {
                    Text(t.midiPortFailed)
                        .font(.system(size: 12, weight: .semibold))
                }
                ForEach(state.problems.filter { $0 != .midiPort }, id: \.self) { p in
                    Text(t.problem(p)).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
    }

    // MARK: Peers

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(t.nearbyTwinKeys)
            TKGroup {
                if state.peers.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(state.peers.enumerated()), id: \.element.id) { index, peer in
                            if index > 0 { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 30) }
                            peerRow(peer)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(t.noPeersTitle).font(.system(size: Theme.body, weight: .semibold))
            Text(state.localNetwork == .denied ? t.noPeersDenied : t.noPeersBody)
                .font(.system(size: Theme.caption))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(t.howToFix) { showingHelp = true }
                .buttonStyle(TKButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func peerRow(_ peer: PeerInfo) -> some View {
        let isLinked = state.linkedPeerID == peer.id
        var detail = peer.isCompatible ? t.modes(peer) : t.incompatible
        var dot = Theme.idleDot
        if isLinked {
            switch state.link {
            case let .connected(_, ms): detail += "  ·  " + state.latencyText(ms); dot = Theme.ok
            case .connecting: detail += "  ·  " + t.connectingShort; dot = Theme.warning
            case .notConnected: break
            }
        }
        return HStack(spacing: 10) {
            StatusDot(color: dot)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name).font(.system(size: Theme.body, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if isLinked {
                Button(t.disconnect, action: actions.disconnect)
                    .buttonStyle(TKButtonStyle())
                    .accessibilityLabel(t.disconnectFrom(peer.name))
                    .help(t.disconnectHelp)
            } else {
                Button(t.connect) { actions.connect(peer.id) }
                    .buttonStyle(TKButtonStyle())
                    .disabled(!peer.isCompatible)
                    .accessibilityLabel(t.connectTo(peer.name))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isLinked ? Theme.selectedRow : Color.clear)
    }

    // MARK: Mode and keyboard

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(t.modeAndKeyboard)
            TKGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) {
                            modeToggles
                            Spacer(minLength: 8)
                            keyCaptureToggle
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 20) { modeToggles }
                            keyCaptureToggle
                        }
                    }
                    .frame(minHeight: Theme.controlHeight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 14)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) { valueBlocks }
                        VStack(alignment: .leading, spacing: 8) { valueBlocks }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    Text(t.doubleNotesHint)
                        .font(.system(size: Theme.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder private var modeToggles: some View {
        Toggle(t.sendMyKeys, isOn: Binding(get: { state.sendKeys }, set: actions.setSendKeys))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityHint(t.sendMyKeysHint)
        Toggle(t.receiveNotes, isOn: Binding(get: { state.receiveNotes }, set: actions.setReceiveNotes))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityHint(t.receiveNotesHint)
    }

    private var keyCaptureToggle: some View {
        Toggle(isOn: Binding(get: { state.keyCapture }, set: actions.setKeyCapture)) {
            Text(keyCaptureText)
                .font(.system(size: Theme.caption, weight: .semibold))
                .foregroundStyle(state.keyCaptureActive && !state.secureInput ? Theme.ok : Theme.textSecondary)
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help(t.keyCaptureHelp)
        .accessibilityLabel(t.keyCapture)
        .accessibilityValue(keyCaptureValue)
    }

    /// Short value for VoiceOver (the label already says "Key capture").
    private var keyCaptureValue: String {
        if !state.keyCapture { return t.valueOff }
        if state.secureInput && state.keyCaptureActive { return t.valuePaused }
        if !state.sendKeys { return t.valueNotSending }
        if state.inputMonitoring != .granted { return t.valueNeedsPermission }
        return t.valueOn
    }

    private var keyCaptureText: String {
        if !state.keyCapture { return t.keyCaptureOff }
        if state.secureInput && state.keyCaptureActive { return t.keyCapturePaused }
        if !state.sendKeys { return t.keyCaptureNotSending }
        if state.inputMonitoring != .granted { return t.keyCaptureNeedsPermission }
        return t.keyCaptureOn
    }

    @ViewBuilder private var valueBlocks: some View {
        valueBlock(title: t.octave, value: "C\(state.octave)", keys: ("Z", "X"))
        valueBlock(title: t.velocity, value: "\(state.velocity)", keys: ("C", "V"))
        VStack(alignment: .leading, spacing: 2) {
            Text(t.heldNotes).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            Text(state.heldNotes.isEmpty ? "—" : state.heldNotes.map(noteName).joined(separator: "  "))
                .font(.system(size: Theme.body, weight: .medium, design: .monospaced))
                .frame(minHeight: 22, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private func valueBlock(title: String, value: String, keys: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value).font(.system(size: Theme.value, weight: .semibold)).monospacedDigit()
                Text("\(keys.0) / \(keys.1)").font(.system(size: Theme.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t.changeWith(title, value, keys.0, keys.1))
    }

    // MARK: Permissions row

    private var permissionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { permissionItems }
            VStack(alignment: .leading, spacing: 6) { permissionItems }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder private var permissionItems: some View {
        let im: (Color, String) = {
            switch state.inputMonitoring {
            case .granted: return (Theme.ok, t.inputMonitoringAllowed)
            case .denied: return (Theme.warning, t.inputMonitoringNotAllowed)
            case .unknown: return (Theme.idleDot, t.inputMonitoringChecking)
            }
        }()
        let ln: (Color, String) = {
            switch state.localNetwork {
            case .peersVisible: return (Theme.ok, t.localNetworkVisible)
            case .searching: return (Theme.idleDot, t.localNetworkSearching)
            case .denied: return (Theme.warning, t.localNetworkNotAllowed)
            }
        }()
        HStack(spacing: 6) { StatusDot(color: im.0); Text(im.1) }
            .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
        HStack(spacing: 6) { StatusDot(color: ln.0); Text(ln.1) }
            .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
    }
}
#endif
