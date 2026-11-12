#if os(macOS)
import SwiftUI
import TwinKeysCore

/// Settings > Live, and Settings > iPhone and iPad (TwinKeys Remote, 2.0).
struct RemoteSettings: View {
    @ObservedObject var model: AppModel
    @State private var installError: String?
    private var t: Strings { model.state.t }

    var body: some View {
        Section(t.liveSection) {
            HStack(spacing: 8) {
                StatusDot(color: !model.state.liveConnected ? Theme.idleDot : model.state.bridgeNeedsRestart ? Theme.warning : Theme.ok)
                Text(model.state.liveConnected ? t.liveConnected : t.liveNotConnected)
            }
            if model.state.bridgeNeedsRestart {
                Text(t.bridgeNeedsRestart).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(t.liveHowTo).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(model.state.bridgeInstalled ? t.updateBridge : t.installBridge) { installError = model.installBridge() }
                    .buttonStyle(TKButtonStyle(kind: model.state.bridgeInstalled ? .normal : .primary))
                Button(t.showBridgeFolder) { model.revealBridgeFolder() }.buttonStyle(TKButtonStyle())
            }
            if let installError {
                Text(installError).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
            }
        }
        Section(t.remoteSection) {
            Toggle(isOn: Binding(get: { model.state.remoteEnabled }, set: { model.setRemoteEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.remoteEnabled)
                    Text(t.remoteHelp).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Text(t.allowedDevices).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if model.state.approvedDevices.isEmpty {
                Text(t.noAllowedDevices).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.state.approvedDevices) { d in
                HStack {
                    Text(d.name)
                    Spacer()
                    Text(d.approvedAt, style: .date).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    Button(t.removeDevice) { model.removeDevice(d.id) }.buttonStyle(TKButtonStyle())
                }
            }
            if model.state.remoteClients > 0 {
                Text(t.remoteConnected(model.state.remoteClients)).font(.system(size: Theme.caption)).foregroundStyle(Theme.ok)
            }
        }
    }
}
#endif
