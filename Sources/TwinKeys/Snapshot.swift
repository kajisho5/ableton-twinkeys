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
        // Connection row: one iPhone with its Apple Watch.
        connected.remoteClients = 1
        connected.remoteWatch = .reachable

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
        unpaired.remoteClients = 0           // no iPhone can connect without a pairing code
        unpaired.remoteWatch = .absent

        var empty = ViewState()
        empty.inputMonitoring = .denied
        empty.localNetwork = .searching

        // Cue use (1.0.0): last cue delivered, missing, and the backup side.
        var cue = connected
        cue.heldNotes = []
        cue.receiveNotes = false
        cue.accessibility = .granted
        cue.cueKeysBlocked = true
        cue.cueKeys[1].memo = "Next scene"
        cue.lastCue = CueStatus(label: "↓", memo: "Next scene", note: 37, count: 12, delivery: .delivered(ms: 2), peerName: "Backup Stage Mac")
        var cueMissing = cue
        cueMissing.lastCue?.delivery = .missing
        var cueBackup = cue
        cueBackup.sendKeys = false; cueBackup.receiveNotes = true
        cueBackup.link = .connected(name: "Main Stage Mac", latencyMs: 2)
        cueBackup.peers = [PeerInfo(id: "m", name: "Main Stage Mac", sends: true, receives: false)]
        cueBackup.linkedPeerID = "m"
        cueBackup.lastCue = CueStatus(label: "↓", memo: "Next scene", note: 37, count: 12, delivery: .received, peerName: "Main Stage Mac")
        // The backup shows the main Mac's iPhone (it told it with the heartbeat).
        cueBackup.remoteClients = 0
        cueBackup.remoteWatch = .absent
        cueBackup.peerRemote = RemoteSummary(phones: 1, watch: .reachable)
        var updateReady = cue
        updateReady.link = .notConnected; updateReady.linkedPeerID = nil; updateReady.lastCue = nil
        updateReady.update = .ready(version: "1.0.1")
        var many = cue
        many.cueKeys = CueKey.adding(CueKey.alphanumericKeyCodes, to: CueKey.defaults)
        var leaking = cue
        leaking.accessibility = .denied; leaking.cueKeysBlocked = false; leaking.lastCue = nil

        let shots: [(String, ViewState, CGSize)] = [
            ("main", connected, CGSize(width: 560, height: 420)),
            ("min-size", empty, Theme.minWindow),
            ("min-size-connected", connected, Theme.minWindow),
            ("pairing-needed", unpaired, CGSize(width: 560, height: 420)),
            ("pairing-mismatch", mismatch, CGSize(width: 560, height: 420)),
            ("cue-main", cue, CGSize(width: 560, height: 520)),
            ("cue-missing", cueMissing, CGSize(width: 560, height: 520)),
            ("cue-backup", cueBackup, CGSize(width: 560, height: 520)),
            ("cue-min-size", cue, Theme.minWindow),
            ("update-ready", updateReady, CGSize(width: 560, height: 520)),
            ("accessibility-needed", leaking, CGSize(width: 560, height: 520)),
            ("cue-many-keys", many, Theme.minWindow),
        ]
        for (suffix, language) in [("", AppLanguage.en), ("-ja", .ja)] {
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for (name, base, size) in shots {
                    var state = base
                    state.language = language
                    if language == .ja, state.lastCue != nil { state.lastCue?.memo = "次のシーン" }
                    if language == .ja, state.cueKeys.count > 1, !state.cueKeys[1].memo.isEmpty { state.cueKeys[1].memo = "次のシーン" }
                    let file = dir.appendingPathComponent("\(name)-\(appearanceName)\(suffix).png")
                    renderWindow(state: state, size: size, appearance: appearance, to: file)
                }
            }
        }
        renderHelp(to: dir)
        renderMenuBarIcons(to: dir)
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

    /// The three menu bar icon states, at 4x on a light and a dark bar.
    static func renderMenuBarIcons(to dir: URL) {
        for (name, bg, fg) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black), ("dark", NSColor(white: 0.17, alpha: 1), NSColor.white)] {
            let scale: CGFloat = 4, w: CGFloat = 3 * 28 + 8, h: CGFloat = 24
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bg.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
            for (i, kind) in [MenuBarIcon.Kind.connected, .idle, .reconnecting].enumerated() {
                // Tint the template image the way the menu bar does.
                let icon = MenuBarIcon.image(kind)
                let tinted = NSImage(size: icon.size, flipped: false) { r in
                    icon.draw(in: r); fg.set(); r.fill(using: .sourceAtop); return true
                }
                tinted.draw(in: NSRect(x: 8 + CGFloat(i) * 28, y: 4, width: 20, height: 16))
            }
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("menubar-icons-\(name).png"))
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
