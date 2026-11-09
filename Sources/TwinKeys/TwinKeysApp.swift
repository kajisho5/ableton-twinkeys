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
            CommandGroup(replacing: .appInfo) {
                Button(model.state.t.aboutMenu) { model.showAbout() }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(model.state.t.connectionMenu) {
                Button(model.state.connectMenuTitle) { model.toggleConnection() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(!model.state.canToggleConnection)
                Button(model.state.keyCapture ? model.state.t.keyCaptureMenuOff : model.state.t.keyCaptureMenuOn) {
                    model.actions.setKeyCapture(!model.state.keyCapture)
                }
                .keyboardShortcut("k", modifiers: [.command, .control])
                Divider()
                Button(model.state.t.allNotesOff) { model.actions.panic() }
                    .keyboardShortcut("p", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .help) {
                HelpMenuItem(title: model.state.t.help)
                Button(model.state.t.showLogs) { model.revealLogs() }
            }
        }

        Window(model.state.t.help, id: "help") {
            HelpWindowView(language: model.state.language)
        }
        .defaultSize(width: 600, height: 680)

        Settings {
            SettingsView(model: model)
        }
    }
}
#endif
