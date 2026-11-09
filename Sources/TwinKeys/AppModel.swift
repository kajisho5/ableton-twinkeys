#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI
import TwinKeysCore

@MainActor
final class AppModel: ObservableObject {
    /// One model for the whole app, created at launch (the engine must not depend on a window).
    static let shared = AppModel()
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
    private var secureInputOn = false
    /// Pairing code as shown ("K7MQ2-WX9TP"); nil if none.
    private var pairingCode: String?
    private var sheet: AppSheet?
    private var listenPort: UInt16?
    private var localAddresses: [String] = []
    private var lastAddressCheck = -10.0
    let updater = Updater()
    /// Live on this Mac (through the Bridge Remote Script) and TwinKeys Remote on iPhones.
    let bridge = LiveBridgeClient()
    private var remote: RemoteServer!
    /// Read from the remote queue: guarded by a lock.
    private let remoteLock = NSLock()
    private var approvedSnapshot: [ApprovedDevice] = []
    private var statusSnapshot: RemoteStatus?
    private var pendingApproval: ((Bool) -> Void)?
    private var remoteClients = 0
    private var lastStatusBroadcast = 0.0
    private var hasAccessibility = KeyMonitor.hasAccessibility
    /// "Restart Now" was clicked: open the new version after the swap.
    private var relaunchAfterQuit = false
    /// Held while linked: no App Nap (timers would be delayed past the link timeout) and no
    /// idle sleep during a show.
    private var showActivity: NSObjectProtocol?

    init() {
        let store = ConfigStore()
        let loaded = store.loadSettingsReportingProblem()
        var settings = loaded.0
        let settingsProblem = loaded.1
        var problems: [AppProblem] = []
        if let settingsProblem { problems.append(.settingsUnreadable(backup: settingsProblem)) }
        let log = FileLog(dir: store.paths.logsDir)

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
        let conductor = Conductor(instanceID: settings.instanceID, displayName: name,
                                  settings: settings, midi: port, net: network,
                                  clock: { ProcessInfo.processInfo.systemUptime },
                                  nanos: { DispatchTime.now().uptimeNanoseconds })
        conductor.log = { log.write($0) }
        log.write("TwinKeys started (\(name))")

        self.settings = settings
        self.log = log
        self.approvedSnapshot = settings.approvedDevices
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
            recheckPermissions: { [weak self] in self?.checkPermissions() },
            setSheet: { [weak self] s in self?.sheet = s; self?.refreshAddresses(); self?.refresh() },
            makeNewPairingCode: { [weak self] in self?.applyPairingCode(Pairing.generate(), save: true) },
            savePairingCode: { [weak self] code in
                guard let self, let n = Pairing.normalize(code) else { return false }
                self.applyPairingCode(Pairing.formatted(n), save: true)
                return true
            },
            copyPairingCode: { [weak self] in
                guard let code = self?.pairingCode else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            },
            connectByAddress: { [weak self] address in self?.connectByAddress(address) ?? false },
            openAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() },
            restartForUpdate: { [weak self] in self?.restartForUpdate() },
            openReleasePage: { [weak self] in if let u = self?.updater.releasePage { NSWorkspace.shared.open(u) } }
        )
    }

    func start() {
        guard !started else { return }
        started = true
        let conductor = self.conductor
        let network = self.network
        startRemote(name: Host.current().localizedName ?? "Mac")
        // Key callbacks first: refresh() below may already start the key tap.
        keyMonitor.onKey = { input in conductor.handleKey(input) }
        keyMonitor.onEventsMissed = { conductor.releaseHeldKeys() }
        conductor.isKnownPeer = { network.isVisible($0) }
        network.onDatagram = { bytes, known in conductor.receive(bytes, knownPeer: known) }
        network.onNewRoute = { peer in conductor.newRoute(to: peer) }
        network.onDuplicateID = { [weak self] in self?.handleDuplicateID() }
        let log = self.log
        network.onLog = { log.write($0) }
        network.onListenPort = { [weak self] port in self?.listenPort = port; self?.refresh() }
        if let code = PairingStore.load(), let n = Pairing.normalize(code) {
            applyPairingCode(Pairing.formatted(n), save: false)
        }
        network.onPeersChanged = { [weak self] list in
            guard let self else { return }
            self.peers = list
            for p in list { conductor.setPeerName(p.name, for: p.id) }
            conductor.prune(keeping: Set(list.map(\.id)))
            self.refresh()
        }
        network.onLocalNetworkState = { [weak self] s in self?.localNetwork = s; self?.refresh() }
        network.onProblem = { [weak self] msg in
            guard let self else { return }
            if !self.problems.contains(.listenFailed) { self.problems.append(.listenFailed) }
            self.log.write(msg); self.refresh()
        }
        network.start(sends: settings.sendKeys, receives: settings.receiveNotes)

        let log2 = self.log
        updater.log = { log2.write($0) }
        updater.onChange = { [weak self] in self?.refresh() }
        // Only while actually connected: a link that keeps retrying must not hold updates forever.
        updater.isInShow = { [weak self] in
            if case .connected = self?.state.link { return true }
            return false
        }
        updater.start(enabled: settings.autoUpdate)
        applyMenuBarOnly()
        checkPermissions()

        // Link timing (heartbeats, timeouts, auto note-off) runs off the main thread.
        let t = DispatchSource.makeTimerSource(queue: network.queue)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
        t.setEventHandler { conductor.tick() }
        t.resume()
        tickTimer = t

        // Going to sleep: key-ups will be missed and the link will drop; end held cue notes now.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            conductor.releaseHeldKeys()
        }
        // Common modes: keep checking permissions and Secure Input while a menu is open.
        let ui = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(ui, forMode: .common)
        uiTimer = ui
    }

    func shutdown() {
        log.write("TwinKeys quitting: All Notes Off")
        // Stop new input first, so no note can start after the final All Notes Off.
        keyMonitor.stop()
        tickTimer?.cancel()
        uiTimer?.invalidate()
        conductor.prepareForQuit()
        network.flush(timeout: 0.3)
        network.stop()
        remote?.stop()
        bridge.stop()
        try? store.save(settings)
        updater.installOnQuit(relaunch: relaunchAfterQuit)
    }

    // MARK: Actions

    func connect(_ id: String) {
        guard peers.first(where: { $0.id == id })?.isCompatible ?? true else { return }
        conductor.connect(to: id)
        settings.lastPeerID = id
        try? store.save(settings)
        refresh()
    }

    /// Uses a pairing code: derives the key off the main thread (about 100 000 HMAC rounds).
    private func applyPairingCode(_ code: String, save: Bool) {
        if save { PairingStore.save(code) }
        pairingCode = code
        let conductor = self.conductor
        DispatchQueue.global(qos: .userInitiated).async {
            let secret = PairingSecret(code: code)
            conductor.setPairing(secret)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.remote?.configure(pairing: self.settings.remoteEnabled ? secret : nil)
            }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        refresh()
    }

    private func connectByAddress(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespaces)
        guard AddressCheck.isValid(address) else { return false }
        let placeholder = network.addManual(host: address)
        conductor.connect(to: placeholder)
        settings.manualAddress = address
        try? store.save(settings)
        log.write("Connecting by address \(address)")
        refresh()
        return true
    }

    private func refreshAddresses() {
        lastAddressCheck = ProcessInfo.processInfo.systemUptime
        localAddresses = NetworkService.localAddresses()
    }

    func showSheet(_ s: AppSheet) {
        sheet = s
        refreshAddresses()
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


    /// Another Mac advertises our instance ID (its settings were copied from this Mac).
    /// Make a new ID; it takes effect after reopening TwinKeys.
    private func handleDuplicateID() {
        guard !problems.contains(.duplicateID) else { return }
        settings.instanceID = UUID()
        try? store.save(settings)
        problems.append(.duplicateID)
        log.write("Another Mac uses this Mac's TwinKeys ID; a new ID was made (reopen TwinKeys)")
        refresh()
    }

    func checkPermissions() {
        hasInputMonitoring = KeyMonitor.hasPermission
        lastPermissionCheck = ProcessInfo.processInfo.systemUptime
        if hasInputMonitoring {
            lastTapAttempt = lastPermissionCheck
            if !keyMonitor.isRunning, !keyMonitor.start(blocking: settings.blockCueKeys) {
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
            // Permission was taken away: the tap no longer delivers events. Drop it so it is
            // created again when permission comes back.
            if !hasInputMonitoring, keyMonitor.isRunning {
                keyMonitor.stop()
                conductor.releaseHeldKeys()
            }
            // Accessibility appeared (or went away): make the tap blocking (or not) again.
            let ax = KeyMonitor.hasAccessibility
            if ax != hasAccessibility {
                hasAccessibility = ax
                restartKeyMonitor()
            }
            // Secure Input (password fields) hides key events, including key-ups.
            let secure = IsSecureEventInputEnabled()
            if secure, !secureInputOn { conductor.releaseHeldKeys() }
            secureInputOn = secure
        }
        // TwinKeys' own text fields and sheets get the keys (no cues while typing a memo,
        // a pairing code or an address, and Return / Esc work there).
        keyMonitor.passThrough = Self.ownInputHasFocus()
        // Start the tap once permission appears (after start(): callbacks are set); retry every 2 s.
        if started, hasInputMonitoring, !keyMonitor.isRunning, now - lastTapAttempt >= 2 {
            lastTapAttempt = now
            _ = keyMonitor.start(blocking: settings.blockCueKeys)
        }
        if keyMonitor.isRunning, problems.contains(.keyCaptureFailed) {
            problems.removeAll { $0 == .keyCaptureFailed }
        }
    }

    // MARK: TwinKeys Remote and Live

    private func startRemote(name: String) {
        let conductor = self.conductor, bridge = self.bridge, log = self.log
        bridge.onLog = { log.write($0) }
        // Backup: Live commands forwarded by the main Mac run on this Mac's Live.
        conductor.onLiveCommand = { cmd in bridge.run(cmd) }
        let r = RemoteServer(serverID: settings.instanceID.uuidString, serverName: name)
        remote = r
        bridge.onUpdate = { [weak r] u in r?.broadcast(u) }
        r.onLog = { log.write($0) }
        r.isApproved = { [weak self] hello in
            guard let self else { return false }
            self.remoteLock.lock(); defer { self.remoteLock.unlock() }
            return ApprovedDevice.isApproved(hello, in: self.approvedSnapshot)
        }
        r.askApproval = { [weak self] deviceName, code, answer in
            guard let self else { answer(false); return }
            // One request at a time; a new one replaces (and refuses) an older unanswered one.
            self.pendingApproval?(false)
            self.pendingApproval = answer
            self.sheet = .approveDevice(name: deviceName, code: code)
            self.refresh()
            self.showApprovalAlert(name: deviceName, code: code)
        }
        r.runCommand = { cmd, done in
            // Both Macs: forward to the backup and run here at the same moment.
            let id = conductor.forwardLive(cmd)
            bridge.run(cmd) { ok, err in
                bridge.queue.asyncAfter(deadline: .now() + Conductor.cueAnswerTimeout + 0.05) {
                    done(ok, err, id.map { conductor.liveDelivery($0) } ?? "notLinked")
                }
            }
        }
        r.onApproved = { [weak self] h in
            let d = ApprovedDevice(id: h.deviceID, name: h.deviceName, publicKey: h.devicePublicKey)
            // Also into the lock-protected copy right away, so the next check sees it.
            self?.remoteLock.lock(); self?.approvedSnapshot.append(d); self?.remoteLock.unlock()
            DispatchQueue.main.async { self?.rememberDevice(d) }
        }
        r.pressCue = { conductor.pressCue(keycode: $0) }
        r.allNotesOff = { conductor.panic() }
        r.snapshot = { bridge.snapshot() }
        r.status = { [weak self] in
            guard let self else { return nil }
            self.remoteLock.lock(); defer { self.remoteLock.unlock() }
            return self.statusSnapshot
        }
        r.onClientsChanged = { [weak self] n in self?.remoteClients = n; self?.refresh() }
        bridge.start()
    }

    /// Asks on screen (as a sheet on the TwinKeys window when it is open, otherwise as a window).
    private func showApprovalAlert(name: String, code: String) {
        let t = state.t
        let alert = NSAlert()
        alert.messageText = t.approveTitle
        alert.informativeText = t.approveMessage(name, code)
        alert.addButton(withTitle: t.approveAllow)
        alert.addButton(withTitle: t.approveDeny)
        alert.buttons.first?.keyEquivalent = ""          // never allowed by pressing Return by accident
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.attachedSheet == nil }) {
            alert.beginSheetModal(for: w) { [weak self] r in self?.answerApproval(r == .alertFirstButtonReturn) }
        } else {
            answerApproval(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    /// The approval sheet was answered.
    func answerApproval(_ allow: Bool) {
        guard case let .approveDevice(name, _)? = sheet else { return }
        sheet = nil
        let answer = pendingApproval
        pendingApproval = nil
        if allow { log.write("Remote: \(name) allowed") }
        answer?(allow)
        refresh()
    }

    /// Called by the server through `askApproval` → `answerApproval`; stores an allowed device.
    func rememberDevice(_ d: ApprovedDevice) {
        settings.approvedDevices.removeAll { $0.id == d.id }
        settings.approvedDevices.append(d)
        saveApproved()
    }

    func removeDevice(_ id: String) {
        settings.approvedDevices.removeAll { $0.id == id }
        saveApproved()
        remote?.revoke(deviceID: id)
        log.write("Remote: a device was removed from the allowed list")
        refresh()
    }

    private func saveApproved() {
        remoteLock.lock(); approvedSnapshot = settings.approvedDevices; remoteLock.unlock()
        try? store.save(settings)
    }

    func setRemoteEnabled(_ on: Bool) {
        settings.remoteEnabled = on
        try? store.save(settings)
        if let code = pairingCode { applyPairingCode(code, save: false) } else { remote?.configure(pairing: nil) }
        refresh()
    }

    func installBridge() -> String? {
        let err = LiveBridgeInstaller.install()
        log.write(err == nil ? "Live Bridge installed into \(LiveBridgeInstaller.installed.path)" : "Live Bridge install failed: \(err!)")
        refresh()
        return err
    }

    func revealBridgeFolder() {
        let url = LiveBridgeInstaller.isInstalled ? LiveBridgeInstaller.installed : LiveBridgeInstaller.remoteScripts
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func updateRemoteStatus(_ s: ViewState, _ snap: ConductorSnapshot) {
        let peerName: String? = { if case let .connected(n, _) = s.link { return n }; return nil }()
        let cue = snap.lastCue.map { c -> RemoteStatus.CueSummary in
            let d: String
            switch c.delivery {
            case .delivered: d = "delivered"
            case .waiting: d = "waiting"
            case .missing: d = "missing"
            case .unconfirmed: d = "unconfirmed"
            case .notConnected: d = "notConnected"
            case .received: d = "received"
            }
            return .init(label: c.label, memo: c.memo, count: c.count, delivery: d)
        }
        let st = RemoteStatus(mainName: Host.current().localizedName ?? "Mac", mainLiveConnected: s.liveConnected,
                              backupName: peerName, backupLinked: peerName != nil, backupLiveConnected: false,
                              latencyMs: { if case let .connected(_, ms) = s.link { return ms }; return nil }(),
                              lastCue: cue, cueKeys: settings.cueKeys.map { .init(keycode: $0.keycode, label: $0.label, memo: $0.memo) })
        remoteLock.lock()
        let changed = statusSnapshot != st
        statusSnapshot = st
        remoteLock.unlock()
        let now = ProcessInfo.processInfo.systemUptime
        if changed || now - lastStatusBroadcast > 1 {
            lastStatusBroadcast = now
            remote?.broadcastStatus()
        }
    }

    private func updateShowActivity(linked: Bool) {
        if linked, showActivity == nil {
            showActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                reason: "TwinKeys is linked to another Mac (show in progress)")
        } else if !linked, let a = showActivity {
            ProcessInfo.processInfo.endActivity(a)
            showActivity = nil
        }
    }

    /// True while TwinKeys is in front and a text field or a sheet of its own has the keyboard.
    static func ownInputHasFocus() -> Bool {
        guard NSApp.isActive, let w = NSApp.keyWindow else { return false }
        return w.firstResponder is NSText || w.isSheet || w.attachedSheet != nil
    }

    /// Recreates the key tap (blocking or listen-only, as the settings and permissions allow).
    private func restartKeyMonitor() {
        guard keyMonitor.isRunning || hasInputMonitoring else { return }
        keyMonitor.stop()
        conductor.releaseHeldKeys()
        lastTapAttempt = ProcessInfo.processInfo.systemUptime
        _ = keyMonitor.start(blocking: settings.blockCueKeys)
    }

    private func openAccessibilitySettings() {
        KeyMonitor.requestAccessibility()
        Self.openSettingsPane("Privacy_Accessibility")
    }

    // MARK: Cue keys

    func setCueKeys(_ keys: [CueKey]) {
        settings.cueKeys = CueKey.sanitized(keys)
        conductor.setCueKeys(settings.cueKeys)
        try? store.save(settings)
        refresh()
    }

    func addCueKey(_ code: UInt16) { addCueKeys([code]) }

    /// Adds keys that are not cue keys yet (each gets the next free note).
    func addCueKeys(_ codes: [UInt16]) {
        let before = settings.cueKeys.count
        setCueKeys(CueKey.adding(codes, to: settings.cueKeys))
        for k in settings.cueKeys.dropFirst(before) { log.write("Cue key added: \(k.label) = \(noteName(k.note))") }
    }

    func removeCueKey(_ code: UInt16) {
        setCueKeys(settings.cueKeys.filter { $0.keycode != code })
    }

    func setCueMemo(_ memo: String, for code: UInt16) {
        guard let i = settings.cueKeys.firstIndex(where: { $0.keycode == code }), settings.cueKeys[i].memo != memo else { return }
        var keys = settings.cueKeys
        keys[i].memo = memo
        setCueKeys(keys)
    }

    private var recordingToken = 0

    func setRecordingCueKey(_ on: Bool) {
        keyMonitor.paused = on
        recordingToken += 1
        if on {
            conductor.releaseHeldKeys()
            // Safety net: never leave cue keys paused, even if the sheet goes away unnoticed.
            let token = recordingToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                guard let self, self.recordingToken == token, self.keyMonitor.paused else { return }
                self.keyMonitor.paused = false
                self.log.write("Adding cue keys ended after 2 minutes; key capture resumed")
            }
        }
    }

    func setBlockCueKeys(_ on: Bool) {
        settings.blockCueKeys = on
        conductor.setBlockCueKeys(on)
        try? store.save(settings)
        if on && !hasAccessibility { KeyMonitor.requestAccessibility() }
        restartKeyMonitor()
        refresh()
    }

    // MARK: Updates, login, menu bar

    func setAutoUpdate(_ on: Bool) {
        settings.autoUpdate = on
        try? store.save(settings)
        updater.start(enabled: on)
        refresh()
    }

    func checkForUpdates() { updater.check() }

    /// Quits and opens the new version. Only while not connected (never during a show).
    private func restartForUpdate() {
        guard state.canRestartForUpdate else { return }
        relaunchAfterQuit = true
        NSApp.terminate(nil)
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            log.write("Open at login \(on ? "on" : "off")")
        } catch {
            log.write("Open at login could not be changed: \(error)")
        }
        // macOS may ask the person to allow it under Login Items first.
        if on, SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        objectWillChange.send()
    }

    func setMenuBarOnly(_ on: Bool) {
        settings.menuBarOnly = on
        try? store.save(settings)
        applyMenuBarOnly()
        objectWillChange.send()
    }

    func applyMenuBarOnly() {
        NSApp.setActivationPolicy(settings.menuBarOnly ? .accessory : .regular)
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
        NSWorkspace.shared.activateFileViewerSelecting([store.paths.settingsFile])
    }

    // MARK: State

    private func refresh() {
        maintainKeyMonitor()
        let snap = conductor.snapshot()
        var s = ViewState()
        let nameFor: (String) -> String = { id in
            snap.peerNames[id] ?? self.peers.first { $0.id == id }?.name
                ?? (id.hasPrefix(PeerInfo.manualPrefix) ? String(id.dropFirst(PeerInfo.manualPrefix.count)) : Strings(self.language).anotherMac)
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
        s.heldNotes = snap.heldNotes
        s.midiPortReady = midi != nil
        s.problems = problems
        s.language = language
        s.secureInput = secureInputOn
        s.isPaired = snap.isPaired
        s.pairingCode = pairingCode
        s.mismatchedPeers = snap.mismatchedPeers
        s.listenPort = listenPort
        if ProcessInfo.processInfo.systemUptime - lastAddressCheck > 5 { refreshAddresses() }
        s.localAddresses = localAddresses
        s.lastManualAddress = settings.manualAddress ?? ""
        s.sheet = sheet
        s.lastCue = snap.lastCue
        s.cueKeys = settings.cueKeys
        s.blockCueKeys = settings.blockCueKeys
        s.cueKeysBlocked = keyMonitor.isBlocking
        s.accessibility = hasAccessibility ? .granted : .denied
        s.update = updater.state
        s.appVersion = updater.currentVersion
        s.autoUpdate = settings.autoUpdate
        updateShowActivity(linked: s.linkedPeerID != nil)
        s.liveConnected = bridge.isConnected
        s.bridgeInstalled = LiveBridgeInstaller.isInstalled
        s.approvedDevices = settings.approvedDevices
        s.remoteClients = remoteClients
        s.remoteEnabled = settings.remoteEnabled
        updateRemoteStatus(s, snap)
        if s != state { state = s }
    }
}
#endif
