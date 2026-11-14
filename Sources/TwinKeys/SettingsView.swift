#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var seconds: Double = 10

    private var t: Strings { model.state.t }

    var body: some View {
        Form {
            QLabSettingsSection(state: model.state, actions: model.qlabActions)
            CueKeySettings(model: model)
            RemoteSettings(model: model)
            DeskSettingsSection(state: model.state, actions: model.deskActions)
            Section(t.pairingTitle) {
                PairingPanel(state: model.state, actions: model.actions)
                    .padding(.vertical, 4)
            }
            Section(t.updatesSection) {
                Toggle(isOn: Binding(get: { model.state.autoUpdate }, set: { model.setAutoUpdate($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.autoUpdate)
                        Text(t.autoUpdateHelp).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                HStack {
                    Text(updateLine).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(t.checkNow) { model.checkForUpdates() }
                        .buttonStyle(TKButtonStyle())
                        .disabled(model.state.update == .checking)
                }
            }
            Section(t.menuBarSection) {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.launchAtLogin)
                        Text(t.launchAtLoginHelp).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.checkbox)
                Toggle(t.menuBarOnly, isOn: Binding(get: { model.settings.menuBarOnly }, set: { model.setMenuBarOnly($0) }))
                    .toggleStyle(.checkbox)
            }
            Section {
                Picker(t.language, selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { l in Text(t.languageName(l)).tag(l) }
                }
                Text(t.languageNote)
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Stepper(value: $seconds, in: 0...120, step: 1) {
                    Text(seconds == 0 ? t.autoNoteOffDisabled : t.autoNoteOff(Int(seconds)))
                }
                .onChange(of: seconds) { if $0 != model.settings.autoNoteOffSeconds { model.setAutoNoteOff($0) } }
                .accessibilityHint(t.autoNoteOffHint)
                Text(t.autoNoteOffHelp)
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 640)
        .padding(.vertical, 8)
        .onAppear { seconds = model.settings.autoNoteOffSeconds }
    }

    private var updateLine: String {
        let s = model.state
        var line = t.currentVersion(s.appVersion)
        switch s.update {
        case .checking: line += "  ·  " + t.updateChecking
        case .upToDate: line += "  ·  " + t.updateUpToDate
        case .failed: line += "  ·  " + t.updateFailed
        case let .downloading(v): line += "  ·  " + t.updateDownloading(v)
        case let .ready(v): line += "  ·  " + t.updateReady(v)
        case let .manual(v, _): line += "  ·  " + t.updateManual(v)
        case .idle: break
        }
        return line
    }

}
#endif
