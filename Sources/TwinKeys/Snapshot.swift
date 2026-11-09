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
        connected.isPaired = true
        connected.pairingCode = "K7MQ2-WX9TP"

        // Pairing set, one visible Mac uses another code.
        var mismatch = connected
        mismatch.linkedPeerID = nil
        mismatch.link = .notConnected
        mismatch.heldNotes = []
        mismatch.mismatchedPeers = ["b"]

        // No pairing code yet.
        var unpaired = mismatch
        unpaired.isPaired = false
        unpaired.pairingCode = nil
        unpaired.mismatchedPeers = []

        var empty = ViewState()
        empty.inputMonitoring = .denied
        empty.localNetwork = .searching

        let shots: [(String, ViewState, CGSize)] = [
            ("main", connected, CGSize(width: 560, height: 420)),
            ("min-size", empty, Theme.minWindow),
            ("min-size-connected", connected, Theme.minWindow),
            ("pairing-needed", unpaired, CGSize(width: 560, height: 420)),
            ("pairing-mismatch", mismatch, CGSize(width: 560, height: 420)),
        ]
        for (suffix, language) in [("", AppLanguage.en), ("-ja", .ja)] {
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for (name, base, size) in shots {
                    var state = base
                    state.language = language
                    let file = dir.appendingPathComponent("\(name)-\(appearanceName)\(suffix).png")
                    renderWindow(state: state, size: size, appearance: appearance, to: file)
                }
            }
        }
        renderHelp(to: dir)
        for (suffix, language) in [("", AppLanguage.en), ("-ja", .ja)] {
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                var s = connected
                s.language = language
                s.localAddresses = ["192.168.1.10"]
                s.lastManualAddress = "192.168.1.20"
                renderWindow(view: PairingSheet(state: s, actions: ViewActions()), size: CGSize(width: 440, height: 330),
                             appearance: appearance, title: "TwinKeys",
                             to: dir.appendingPathComponent("sheet-pairing-\(appearanceName)\(suffix).png"))
                renderWindow(view: ConnectByIPSheet(state: s, actions: ViewActions()), size: CGSize(width: 440, height: 270),
                             appearance: appearance, title: "TwinKeys",
                             to: dir.appendingPathComponent("sheet-ip-\(appearanceName)\(suffix).png"))
            }
        }
    }

    static func renderHelp(to dir: URL) {
        for (suffix, language) in [("", AppLanguage.en), ("-ja", .ja)] {
            renderWindow(view: HelpWindowView(language: language), size: CGSize(width: 600, height: 680),
                         appearance: .aqua, title: Strings(language).help,
                         to: dir.appendingPathComponent("help-light\(suffix).png"))
        }
    }

    private static func renderWindow(state: ViewState, size: CGSize, appearance: NSAppearance.Name, to file: URL) {
        renderWindow(view: ContentView(state: state, actions: ViewActions()), size: size,
                     appearance: appearance, title: "TwinKeys", to: file)
    }

    private static func renderWindow<V: View>(view: V, size: CGSize, appearance: NSAppearance.Name, title: String, to file: URL) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // The window's frame view includes the title bar. Render at 2x for sharp images.
        guard let frameView = window.contentView?.superview else {
            print("snapshot: could not capture \(file.lastPathComponent)"); return
        }
        let bounds = frameView.bounds
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
            print("snapshot: wrote \(file.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        }
        window.close()
    }
}
#endif
