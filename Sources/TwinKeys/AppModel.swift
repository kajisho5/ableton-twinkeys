#if os(macOS)
import AppKit
import Combine
import SwiftUI
import TwinKeysCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = ViewState()

    private let store = ConfigStore()
    private(set) var settings: AppSettings
    private let log: FileLog
    private let midi: VirtualMIDIPort?
    private let network: NetworkService
    private let conductor: Conductor
    private let keyMonitor = KeyMonitor()
    private var peers: [PeerInfo] = []
    private var localNetwork: LocalNetworkState = .searching
    private var problems: [AppProblem] = []
    private var tickTimer: DispatchSourceTimer?
    private var uiTimer: Timer?
    private var started = false
    /// Input Monitoring state, refreshed once per second (not on every UI tick).
    private var hasInputMonitoring = KeyMonitor.hasPermission
    private var lastPermissionCheck = 0.0
    private var lastTapAttempt = 0.0

    init() {
        let store = ConfigStore()
        let loaded = store.loadSettingsReportingProblem()
        var settings = loaded.0
        let settingsProblem = loaded.1
        var problems: [AppProblem] = []
        if let settingsProblem { problems.append(.settingsUnreadable(backup: settingsProblem)) }
        let log = FileLog(dir: store.paths.logsDir)
        let (mapping, mappingProblem) = store.loadMapping()
        if mappingProblem != nil { problems.append(.mappingUnreadable) }

        var port: VirtualMIDIPort?
        do {
            port = try VirtualMIDIPort(name: "TwinKeys", uniqueID: settings.midiUniqueID)
        } catch {
            problems.append(.midiPort)
            log.write("MIDI port error: \(error)")
        }
        if let port, settings.midiUniqueID != port.uniqueID {
            settings.midiUniqueID = port.uniqueID
            try? store.save(settings)
        }

        let name = Host.current().localizedName ?? "Mac"
        let network = NetworkService(ownID: settings.instanceID.uuidString, serviceName: name)
        let conductor = Conductor(instanceID: settings.instanceID, displayName: name, mapping: mapping,
                                  settings: settings, midi: port, net: network,
                                  clock: { ProcessInfo.processInfo.systemUptime },
                                  nanos: { DispatchTime.now().uptimeNanoseconds })
        conductor.log = { log.write($0) }
        log.write("TwinKeys started (\(name))")

        self.settings = settings
        self.log = log
        self.midi = port
        self.network = network
        self.conductor = conductor
        self.problems = problems
        var initial = ViewState()
        initial.midiPortReady = port != nil
        initial.problems = problems
        initial.sendKeys = settings.sendKeys
        initial.receiveNotes = settings.receiveNotes
        initial.keyCapture = settings.keyCapture
        initial.language = AppLanguage(rawValue: settings.language) ?? .system
        self.state = initial
    }

    var actions: ViewActions {
        ViewActions(
            connect: { [weak self] id in self?.connect(id) },
            disconnect: { [weak self] in self?.conductor.disconnect(); self?.refresh() },
            panic: { [weak self] in self?.conductor.panic(); self?.refresh() },
            setSendKeys: { [weak self] on in self?.setSendKeys(on) },
            setReceiveNotes: { [weak self] on in self?.setReceiveNotes(on) },
            setKeyCapture: { [weak self] on in self?.setKeyCapture(on) },
            openInputMonitoringSettings: { [weak self] in self?.openInputMonitoringSettings() },
            openLocalNetworkSettings: { Self.openSettingsPane("Privacy_LocalNetwork") },
            recheckPermissions: { [weak self] in self?.checkPermissions() }
        )
    }

    func start() {
        guard !started else { return }
        started = true
        let conductor = self.conductor
        network.onDatagram = { bytes, known in conductor.receive(bytes, knownPeer: known) }
        network.onPeersChanged = { [weak self] list in
            guard let self else { return }
            self.peers = list
            for p in list { conductor.setPeerName(p.name, for: p.id) }
            self.refresh()
        }
        network.onLocalNetworkState = { [weak self] s in self?.localNetwork = s; self?.refresh() }
        network.onProblem = { [weak self] msg in
            guard let self else { return }
            if !self.problems.contains(.listenFailed) { self.problems.append(.listenFailed) }
            self.log.write(msg); self.refresh()
        }
        network.start(sends: settings.sendKeys, receives: settings.receiveNotes)

        keyMonitor.onKey = { input in conductor.handleKey(input) }
        checkPermissions()

        // Link timing (heartbeats, timeouts, auto note-off) runs off the main thread.
        let t = DispatchSource.makeTimerSource(queue: network.queue)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
        t.setEventHandler { conductor.tick() }
        t.resume()
        tickTimer = t

        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func shutdown() {
        log.write("TwinKeys quitting: All Notes Off")
        conductor.prepareForQuit()
        network.flush(timeout: 0.15)
        keyMonitor.stop()
        network.stop()
        try? store.save(settings)
    }

    // MARK: Actions

    func connect(_ id: String) {
        conductor.connect(to: id)
        settings.lastPeerID = id
        try? store.save(settings)
        refresh()
    }

    func toggleConnection() {
        if state.linkedPeerID != nil { conductor.disconnect() }
        else if peers.count == 1 { connect(peers[0].id) }
        refresh()
    }

    private func setSendKeys(_ on: Bool) {
        conductor.setSendKeys(on)
        settings.sendKeys = on
        persistModes()
    }

    private func setReceiveNotes(_ on: Bool) {
        conductor.setReceiveNotes(on)
        settings.receiveNotes = on
        persistModes()
    }

    private func setKeyCapture(_ on: Bool) {
        conductor.setKeyCapture(on)
        settings.keyCapture = on
        try? store.save(settings)
        log.write("Key capture \(on ? "on" : "off")")
        refresh()
    }

    private func persistModes() {
        network.updateModes(sends: settings.sendKeys, receives: settings.receiveNotes)
        try? store.save(settings)
        refresh()
    }

    var language: AppLanguage { AppLanguage(rawValue: settings.language) ?? .system }

    func setLanguage(_ l: AppLanguage) {
        settings.language = l.rawValue
        try? store.save(settings)
        refresh()
    }

    func showAbout() {
        let t = state.t
        let credits = NSAttributedString(string: t.aboutCredits, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAutoNoteOff(_ seconds: Double) {
        settings.autoNoteOffSeconds = seconds
        conductor.setAutoNoteOff(seconds: seconds)
        try? store.save(settings)
    }

    func reloadMapping() {
        let (m, problem) = store.loadMapping()
        conductor.setMapping(m)
        problems.removeAll { $0 == .mappingUnreadable }
        if problem != nil { problems.append(.mappingUnreadable) }
        refresh()
    }

    func resetMapping() {
        try? store.writeDefaultMapping()
        reloadMapping()
    }

    func checkPermissions() {
        hasInputMonitoring = KeyMonitor.hasPermission
        lastPermissionCheck = ProcessInfo.processInfo.systemUptime
        if hasInputMonitoring {
            lastTapAttempt = lastPermissionCheck
            if !keyMonitor.isRunning, !keyMonitor.start() {
                if !problems.contains(.keyCaptureFailed) { problems.append(.keyCaptureFailed) }
            }
        }
        if keyMonitor.isRunning { problems.removeAll { $0 == .keyCaptureFailed } }
        refresh()
    }

    /// Light-weight permission upkeep for the 100 ms UI tick.
    private func maintainKeyMonitor() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPermissionCheck >= 1 {
            lastPermissionCheck = now
            hasInputMonitoring = KeyMonitor.hasPermission
        }
        // Start the tap once permission appears; retry at most every 2 s.
        if hasInputMonitoring, !keyMonitor.isRunning, now - lastTapAttempt >= 2 {
            lastTapAttempt = now
            _ = keyMonitor.start()
        }
        if keyMonitor.isRunning, problems.contains(.keyCaptureFailed) {
            problems.removeAll { $0 == .keyCaptureFailed }
        }
    }

    private func openInputMonitoringSettings() {
        // The first request shows the system dialog and adds TwinKeys to the list.
        KeyMonitor.requestPermission()
        Self.openSettingsPane("Privacy_ListenEvent")
    }

    static func openSettingsPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealLogs() {
        try? FileManager.default.createDirectory(at: store.paths.logsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.paths.logsDir])
    }

    func revealSettingsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.paths.mappingFile])
    }

    // MARK: State

    private func refresh() {
        maintainKeyMonitor()
        let snap = conductor.snapshot()
        var s = ViewState()
        let nameFor: (String) -> String = { id in
            snap.peerNames[id] ?? self.peers.first { $0.id == id }?.name ?? Strings(self.language).anotherMac
        }
        switch snap.link {
        case .idle: s.link = .notConnected
        case let .connecting(p, attempt, _): s.link = .connecting(name: nameFor(p), attempt: attempt); s.linkedPeerID = p
        case let .connected(p): s.link = .connected(name: nameFor(p), latencyMs: snap.latencyMs); s.linkedPeerID = p
        }
        s.peers = peers
        // A peer that connected to us but is not (yet) in the Bonjour list still gets a row.
        if let id = s.linkedPeerID, !peers.contains(where: { $0.id == id }) {
            s.peers.append(PeerInfo(id: id, name: nameFor(id), sends: true, receives: false))
        }
        s.sendKeys = snap.sendKeys
        s.receiveNotes = snap.receiveNotes
        s.keyCapture = snap.keyCapture
        s.inputMonitoring = hasInputMonitoring ? .granted : .denied
        s.localNetwork = peers.isEmpty ? localNetwork == .peersVisible ? .searching : localNetwork : .peersVisible
        s.octave = snap.octave
        s.velocity = snap.velocity
        s.heldNotes = snap.heldNotes
        s.midiPortReady = midi != nil
        s.problems = problems
        s.language = language
        if s != state { state = s }
    }
}
#endif
