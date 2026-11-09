#if os(macOS)
import AppKit
import SwiftUI

/// Menu bar icon: a small keyboard drawn as a template image, so macOS colors it for the
/// light and dark menu bar (docs/design/menubar-icons-*.svg).
/// Connected = filled, not connected = outline, reconnecting = outline with "!".
enum MenuBarIcon {
    enum Kind { case connected, idle, reconnecting }

    private static let cache: [Kind: NSImage] = [.connected: draw(.connected), .idle: draw(.idle), .reconnecting: draw(.reconnecting)]

    static func image(_ kind: Kind) -> NSImage { cache[kind]! }

    private static func draw(_ kind: Kind) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 1.5, y: 2.5, width: kind == .reconnecting ? 13 : 17, height: 11)
            let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            outline.lineWidth = 1.6
            if kind == .connected {
                outline.fill()
                // White keys separated by "cut" lines (drawn clear), black keys as gaps.
                NSGraphicsContext.current?.compositingOperation = .clear
                let w = body.width / 4
                for i in 1..<4 {
                    let x = body.minX + w * CGFloat(i)
                    NSRect(x: x - 0.6, y: body.minY + 1.5, width: 1.2, height: 4).fill()
                }
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                outline.stroke()
                let w = body.width / (kind == .reconnecting ? 3 : 4)
                let keys = kind == .reconnecting ? 3 : 4
                for i in 1..<keys {
                    let x = body.minX + w * CGFloat(i)
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: x, y: body.minY + 0.8))
                    line.line(to: NSPoint(x: x, y: body.maxY - 0.8))
                    line.lineWidth = 1.2
                    line.stroke()
                    // Black key above each split.
                    NSRect(x: x - 1.6, y: body.midY - 0.5, width: 3.2, height: body.height / 2).fill()
                }
            }
            if kind == .reconnecting {
                // "!" to the right of the keyboard.
                NSRect(x: 16.8, y: 6.5, width: 2, height: 7).fill()
                NSRect(x: 16.8, y: 2.5, width: 2, height: 2).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The menu shown from the menu bar icon (docs/design/menubar-*.svg).
struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var t: Strings { model.state.t }

    var body: some View {
        Text(model.state.headline)
        if case .connected = model.state.link { Text(model.state.detail) }
        Divider()
        Button(t.allNotesOff) { model.actions.panic() }
            .keyboardShortcut("p", modifiers: [.command, .control])
        Button(model.state.connectMenuTitle) { model.toggleConnection() }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!model.state.canToggleConnection)
        Button(model.state.keyCapture ? t.keyCaptureMenuOff : t.keyCaptureMenuOn) {
            model.actions.setKeyCapture(!model.state.keyCapture)
        }
        .keyboardShortcut("k", modifiers: [.command, .control])
        Divider()
        Button(t.openTwinKeys) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if #available(macOS 14, *) {
            SettingsLink { Text(t.settingsMenu) }
                .keyboardShortcut(",", modifiers: .command)
        } else {
            Button(t.settingsMenu) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        Toggle(t.launchAtLogin, isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Button(t.checkForUpdates) { model.checkForUpdates() }
        Divider()
        Button(t.quitTwinKeys) { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

extension ViewState {
    var menuBarIconKind: MenuBarIcon.Kind {
        switch link {
        case .connected: return .connected
        case let .connecting(_, attempt): return attempt > 1 ? .reconnecting : .idle
        case .notConnected: return .idle
        }
    }
}
#endif
