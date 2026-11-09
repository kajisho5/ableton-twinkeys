#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var seconds: Double = 10

    var body: some View {
        Form {
            Section {
                HStack {
                    Stepper(value: $seconds, in: 0...120, step: 1) {
                        Text("Automatic note-off after \(Int(seconds)) s")
                    }
                    .onChange(of: seconds) { model.setAutoNoteOff($0) }
                    .accessibilityHint("A note that never receives its note-off is stopped after this time. 0 turns it off.")
                }
                Text("Protects against stuck notes if a note-off is lost. 0 turns it off.")
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            }
            Section {
                HStack(spacing: 8) {
                    Button("Show Mapping File in Finder") { model.revealSettingsFolder() }
                        .buttonStyle(TKButtonStyle())
                    Button("Reload Mapping") { model.reloadMapping() }
                        .buttonStyle(TKButtonStyle())
                    Button("Restore Default Mapping") { model.resetMapping() }
                        .buttonStyle(TKButtonStyle())
                }
                Text("Edit mapping.json to change which physical keys play which notes.")
                    .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
        .onAppear { seconds = model.settings.autoNoteOffSeconds }
    }
}
#endif
