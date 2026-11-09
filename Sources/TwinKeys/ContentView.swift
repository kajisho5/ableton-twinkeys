#if os(macOS)
import SwiftUI
import TwinKeysCore

struct ContentView: View {
    let state: ViewState
    let actions: ViewActions
    @State private var showingHelp = false

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
        .sheet(isPresented: $showingHelp) { HelpView(onClose: { showingHelp = false }, actions: actions) }
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
            .accessibilityLabel("Connection status: \(state.headline). \(state.detail)")
            Spacer(minLength: 8)
            Button("All Notes Off", action: actions.panic)
                .buttonStyle(TKButtonStyle(kind: .destructive))
                .help("Stop every sounding note on this Mac and the connected Mac (⌃⌘P)")
                .accessibilityHint("Sends All Notes Off to this Mac and to the connected Mac")
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
                    Text("Key capture needs Input Monitoring permission.")
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open System Settings…", action: actions.openInputMonitoringSettings)
                            .buttonStyle(TKButtonStyle(kind: .primary))
                            .accessibilityHint("Opens Privacy & Security, Input Monitoring")
                        Button("Check Again", action: actions.recheckPermissions)
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
                    Text("The TwinKeys MIDI port could not be created. Notes cannot reach your music software.")
                        .font(.system(size: 12, weight: .semibold))
                }
                ForEach(state.problems, id: \.self) { p in
                    Text(p).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
    }

    // MARK: Peers

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Nearby TwinKeys")
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
            Text("No TwinKeys found on this network").font(.system(size: Theme.body, weight: .semibold))
            Text(state.localNetwork == .denied
                 ? "macOS is blocking local network access for TwinKeys. Allow it in System Settings > Privacy & Security > Local Network."
                 : "Make sure both Macs are on the same Wi-Fi or wired network, and that TwinKeys is allowed in System Settings > Privacy & Security > Local Network.")
                .font(.system(size: Theme.caption))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("How to Fix…") { showingHelp = true }
                .buttonStyle(TKButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func peerRow(_ peer: PeerInfo) -> some View {
        let isLinked = state.linkedPeerID == peer.id
        var detail = peer.modeText
        var dot = Theme.idleDot
        if isLinked {
            switch state.link {
            case let .connected(_, ms): detail += "  ·  " + ViewState.latencyText(ms); dot = Theme.ok
            case .connecting: detail += "  ·  connecting…"; dot = Theme.warning
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
                Button("Disconnect", action: actions.disconnect)
                    .buttonStyle(TKButtonStyle())
                    .accessibilityLabel("Disconnect from \(peer.name)")
                    .help("Disconnect (⌘K)")
            } else {
                Button("Connect") { actions.connect(peer.id) }
                    .buttonStyle(TKButtonStyle())
                    .accessibilityLabel("Connect to \(peer.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isLinked ? Theme.selectedRow : Color.clear)
    }

    // MARK: Mode and keyboard

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Mode and Keyboard")
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
                    Text("Turn off the computer MIDI keyboard in your music software to avoid double notes.")
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
        Toggle("Send my keys", isOn: Binding(get: { state.sendKeys }, set: actions.setSendKeys))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityHint("Keys you press play notes here and on the connected Mac")
        Toggle("Receive notes", isOn: Binding(get: { state.receiveNotes }, set: actions.setReceiveNotes))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityHint("Notes from the connected Mac play on this Mac")
    }

    private var keyCaptureToggle: some View {
        Toggle(isOn: Binding(get: { state.keyCapture }, set: actions.setKeyCapture)) {
            Text(keyCaptureText)
                .font(.system(size: Theme.caption, weight: .semibold))
                .foregroundStyle(state.keyCaptureActive ? Theme.ok : Theme.textSecondary)
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("Turn key capture on or off (⌃⌘K)")
        .accessibilityLabel("Key capture")
        .accessibilityValue(keyCaptureText)
    }

    private var keyCaptureText: String {
        if !state.keyCapture { return "Key capture: Off" }
        if !state.sendKeys { return "Key capture: Not sending" }
        if state.inputMonitoring != .granted { return "Key capture: Needs permission" }
        return "Key capture: On"
    }

    @ViewBuilder private var valueBlocks: some View {
        valueBlock(title: "Octave", value: "C\(state.octave)", keys: "Z / X")
        valueBlock(title: "Velocity", value: "\(state.velocity)", keys: "C / V")
        VStack(alignment: .leading, spacing: 2) {
            Text("Held notes").font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            Text(state.heldNotes.isEmpty ? "—" : state.heldNotes.map(noteName).joined(separator: "  "))
                .font(.system(size: Theme.body, weight: .medium, design: .monospaced))
                .frame(minHeight: 22, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private func valueBlock(title: String, value: String, keys: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value).font(.system(size: Theme.value, weight: .semibold)).monospacedDigit()
                Text(keys).font(.system(size: Theme.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value). Change with \(keys.replacingOccurrences(of: " / ", with: " and "))")
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
            case .granted: return (Theme.ok, "Input Monitoring: Allowed")
            case .denied: return (Theme.warning, "Input Monitoring: Not allowed")
            case .unknown: return (Theme.idleDot, "Input Monitoring: Checking…")
            }
        }()
        let ln: (Color, String) = {
            switch state.localNetwork {
            case .peersVisible: return (Theme.ok, "Local Network: Peers visible")
            case .searching: return (Theme.idleDot, "Local Network: Searching")
            case .denied: return (Theme.warning, "Local Network: Not allowed")
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
