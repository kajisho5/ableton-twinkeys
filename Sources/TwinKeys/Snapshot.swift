#if os(macOS)
import AppKit
import SwiftUI
import TwinKeysCore

/// Renders the main window from sample data to PNG files (light and dark).
/// Used by CI to produce the screenshots in deliverables/. Sample names are fictional.
@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var connected = ViewState()
        connected.peers = [
            PeerInfo(id: "b", name: "Backup Stage Mac", sends: false, receives: true),
            PeerInfo(id: "c", name: "Spare Mac (Demo)", sends: false, receives: true),
        ]
        connected.linkedPeerID = "b"
        connected.link = .connected(name: "Backup Stage Mac", latencyMs: 2)
        connected.inputMonitoring = .granted
        connected.localNetwork = .peersVisible
        connected.heldNotes = [64, 67, 72]

        var empty = ViewState()
        empty.inputMonitoring = .denied
        empty.localNetwork = .searching

        let shots: [(String, ViewState, CGSize)] = [
            ("main", connected, CGSize(width: 560, height: 420)),
            ("min-size", empty, Theme.minWindow),
            ("min-size-connected", connected, Theme.minWindow),
        ]
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (name, state, size) in shots {
                let file = dir.appendingPathComponent("\(name)-\(appearanceName).png")
                renderWindow(state: state, size: size, appearance: appearance, to: file)
            }
        }
    }

    private static func renderWindow(state: ViewState, size: CGSize, appearance: NSAppearance.Name, to file: URL) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "TwinKeys"
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(state: state, actions: ViewActions()))
        window.setContentSize(size)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // The window's frame view includes the title bar.
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            print("snapshot: could not capture \(file.lastPathComponent)"); return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
            print("snapshot: wrote \(file.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        }
        window.close()
    }
}
#endif
