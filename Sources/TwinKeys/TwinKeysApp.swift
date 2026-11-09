#if os(macOS)
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
}

struct TwinKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("TwinKeys", id: "main") {
            ContentView(state: model.state, actions: model.actions)
                .onAppear {
                    delegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 560, height: 420)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Connection") {
                Button(model.state.connectMenuTitle) { model.toggleConnection() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(!model.state.canToggleConnection)
                Button(model.state.keyCapture ? "Turn Key Capture Off" : "Turn Key Capture On") {
                    model.actions.setKeyCapture(!model.state.keyCapture)
                }
                .keyboardShortcut("k", modifiers: [.command, .control])
                Divider()
                Button("All Notes Off") { model.actions.panic() }
                    .keyboardShortcut("p", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .help) {
                Button("TwinKeys Help") { model.openHelp() }
                Button("Show Log Folder in Finder") { model.revealLogs() }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
#endif
