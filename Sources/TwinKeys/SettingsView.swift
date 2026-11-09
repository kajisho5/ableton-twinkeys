#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var seconds: Double = 10

    private var t: Strings { model.state.t }

    var body: some View {
        Form {
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
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { mappingButtons }
                    VStack(alignment: .leading, spacing: 8) { mappingButtons }
                }
                Text(t.mappingHelp)
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
        .onAppear { seconds = model.settings.autoNoteOffSeconds }
    }

    @ViewBuilder private var mappingButtons: some View {
        Button(t.showMappingFile) { model.revealSettingsFolder() }.buttonStyle(TKButtonStyle())
        Button(t.reloadMapping) { model.reloadMapping() }.buttonStyle(TKButtonStyle())
        Button(t.restoreMapping) { model.resetMapping() }.buttonStyle(TKButtonStyle())
    }
}
#endif
