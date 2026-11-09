#if os(macOS)
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel { MainActor.assumeIsolated { AppModel.shared } }

    /// The Dock icon setting applies before any window shows (no flash of the Dock icon).
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.applyMenuBarOnly() }
    }

    /// Start everything at launch, whether or not the main window appears
    /// (opened at login, menu-bar-only, window closed last time).
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    /// Closing the window keeps TwinKeys running (it stays in the menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

struct TwinKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        Window("TwinKeys", id: "main") {
            ContentView(state: model.state, actions: model.actions)
                .onAppear { model.start() }     // already started at launch; harmless
        }
        .defaultSize(width: 560, height: 420)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(model.state.t.aboutMenu) { model.showAbout() }
                Button(model.state.t.checkForUpdates) { model.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(model.state.t.connectionMenu) {
                Button(model.state.connectMenuTitle) { model.toggleConnection() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(!model.state.canToggleConnection)
                Button(model.state.t.connectByIP) { model.showSheet(.connectByIP) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button(model.state.t.setUpPairing) { model.showSheet(.pairing) }
                Divider()
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

        // Always in the menu bar: TwinKeys keeps running when the window is closed.
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(model.state.menuBarIconKind))
                .accessibilityLabel("TwinKeys: \(model.state.headline)")
        }
        .menuBarExtraStyle(.menu)
    }
}
#endif
