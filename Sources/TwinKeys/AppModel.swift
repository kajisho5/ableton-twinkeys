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
    /// 2.4 (experimental): the Yamaha console's faders, from the backup Mac.
    let desk = DeskClient()
    /// The settings the console link last got (nil: stopped).
    private var deskConfig: DeskSettings?
    /// Linked to the main Mac since the last automatic takeover attempt (it runs once per loss).
    private var deskAutoArmed = false
    private var remote: RemoteServer!
    /// Read from the remote queue: guarded by a lock.
    private let remoteLock = NSLock()
    private var approvedSnapshot: [ApprovedDevice] = []
    private var statusSnapshot: RemoteStatus?
    /// The device waiting for Allow / Don't Allow (the server asks about one at a time).
    private var approval: ApprovalRequest?
    private struct ApprovalRequest {
        let token: Int
        let name: String
        let code: String
        let answer: (Bool) -> Void
        /// The alert on screen for it, if shown yet.
        var alert: NSAlert?
    }
    private var remoteClients = 0
    /// Connection display: the Apple Watch as this Mac's iPhones report it.
    private var remoteWatch: WatchLevel = .absent
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
            openReleasePage: { [weak self] in if let u = self?.updater.releasePage { NSWorkspace.shared.open(u) } },
            becomeMain: { [weak self] in self?.confirmBecomeMain() },
            handOverMain: { [weak self] in self?.conductor.handOverMain(); self?.refresh() },
            // macOS 13 (from 14 on the window uses SettingsLink, as the menu bar menu does).
            openSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            // Memberwise order: ViewActions declares the desk actions after openSettings.
            restoreDesk: { [weak self] in self?.confirmRestoreDesk() },
            dismissDeskBanner: { [weak self] in self?.desk.dismiss(); self?.refresh() }
        )
    }

    func start() {
        guard !started else { return }
        started = true
        let deskLog = self.log
        desk.onLog = { deskLog.write($0) }
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
        desk.stop()
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
        // Backup: run it and tell the main Mac what Live did (2.2).
        conductor.onLiveCommandRun = { cmd, answer in
            bridge.run(cmd) { ok, err in answer(ok ? .ran : err == "no_answer" ? .noAnswer : .refused) }
        }
        let r = RemoteServer(serverID: settings.instanceID.uuidString, serverName: name)
        remote = r
        bridge.onUpdate = { [weak r] u in r?.broadcast(u) }
        r.onLog = { log.write($0) }
        r.isApproved = { [weak self] hello in
            guard let self else { return false }
            self.remoteLock.lock(); defer { self.remoteLock.unlock() }
            return ApprovedDevice.isApproved(hello, in: self.approvedSnapshot)
        }
        r.askApproval = { [weak self] token, deviceName, code, answer in
            guard let self else { answer(false); return }
            // The server asks about one device at a time; never leave an older alert open.
            if let old = self.approval { self.approval = nil; self.closeAlert(old.alert); old.answer(false) }
            self.approval = ApprovalRequest(token: token, name: deviceName, code: code, answer: answer, alert: nil)
            self.refresh()
            if NSApp.isActive {
                self.showApprovalAlert()
            } else {
                // Never take the screen from Live mid-show: bounce the Dock icon and show the
                // question when TwinKeys is next brought to the front (or from the menu bar).
                NSApp.requestUserAttention(.informationalRequest)
            }
        }
        r.cancelApproval = { [weak self] token in self?.dismissApproval(token: token) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showApprovalAlertSoon() }
        }
        r.currentStructure = { bridge.snapshot().song.structure }
        r.currentSceneCount = { let s = bridge.snapshot(); return s.song.sceneCount ?? s.scenes.count }
        r.runCommand = { cmd, done, late in
            // Both Macs: forward to the backup and run here at the same moment. Only this Mac's
            // command carries the layout it was aimed at (the backup's layout is its own).
            let id = conductor.forwardLive(cmd)
            bridge.run(cmd, checkStructure: true, done: { ok, err in
                // Wait for the backup's own Live to answer too (it has up to 1 s, like this one).
                bridge.queue.asyncAfter(deadline: .now() + 1.2) {
                    done(ok, err, id.map { conductor.liveDelivery($0) } ?? "notLinked")
                }
            }, late: { ok, _ in late(ok) })
        }
        r.onApproved = { [weak self] h in
            let d = ApprovedDevice(id: h.deviceID, name: h.deviceName, publicKey: h.devicePublicKey)
            // Also into the lock-protected copy right away, so the next check sees it.
            self?.remoteLock.lock(); self?.approvedSnapshot.append(d); self?.remoteLock.unlock()
            DispatchQueue.main.async { self?.rememberDevice(d) }
        }
        r.pressCue = { conductor.pressCue(keycode: $0) }
        // An iPhone switched to this Mac because the main stopped answering (2.3).
        r.becomeMain = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.becomeMain() } }
        }
        conductor.onRoleChange = { [weak self] isMain in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.roleChanged(isMain: isMain) } }
        }
        r.allNotesOff = { conductor.panic() }
        r.snapshot = { bridge.snapshot() }
        r.status = { [weak self] in
            guard let self else { return nil }
            self.remoteLock.lock(); defer { self.remoteLock.unlock() }
            return self.statusSnapshot
        }
        r.onClientsChanged = { [weak self] n in self?.remoteClients = n; self?.refresh() }
        r.onWatchChanged = { [weak self] w in self?.remoteWatch = w; self?.refresh() }
        // 2.2: an older TwinKeysBridge from a previous TwinKeys is replaced with the one in this app.
        if LiveBridgeInstaller.updateIfOutdated() { log.write("Live Bridge: installed copy updated to version \(LiveBridgeInstaller.bundledVersion)") }
        bridge.start()
    }

    /// Asks on screen (as a sheet on the TwinKeys window when it is open, otherwise as a window),
    /// only while TwinKeys is the active app. Each alert answers only its own request.
    private func showApprovalAlert() {
        guard NSApp.isActive, var req = approval, req.alert == nil else { return }
        let t = state.t
        let alert = NSAlert()
        alert.messageText = t.approveTitle
        alert.informativeText = t.approveMessage(req.name, req.code)
        alert.addButton(withTitle: t.approveAllow)
        alert.addButton(withTitle: t.approveDeny)
        alert.buttons.first?.keyEquivalent = ""          // never allowed by pressing Return by accident
        req.alert = alert
        approval = req
        let token = req.token
        if let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.attachedSheet == nil }) {
            alert.beginSheetModal(for: w) { [weak self] r in self?.answerApproval(token: token, allow: r == .alertFirstButtonReturn) }
        } else {
            let r = alert.runModal()
            answerApproval(token: token, allow: r == .alertFirstButtonReturn)
        }
    }

    /// From the menu bar: show the waiting request now.
    func showApprovalRequest() {
        NSApp.activate(ignoringOtherApps: true)
        showApprovalAlertSoon()
    }

    /// Next turn of the main loop, not inside a notification or menu action (the alert may run
    /// its own modal loop).
    private func showApprovalAlertSoon() {
        DispatchQueue.main.async { [weak self] in self?.showApprovalAlert() }
    }

    /// An approval alert was answered. Ignored unless `token` is still the open request.
    private func answerApproval(token: Int, allow: Bool) {
        guard let req = approval, req.token == token else { return }
        approval = nil
        if allow { log.write("Remote: \(req.name) allowed") }
        req.answer(allow)
        refresh()
    }

    /// The server gave up on request `token` (time limit, or the device left): close its alert.
    private func dismissApproval(token: Int) {
        guard let req = approval, req.token == token else { return }
        approval = nil
        closeAlert(req.alert)
        refresh()
    }

    /// Closes an approval alert without answering (its completion is then ignored).
    private func closeAlert(_ alert: NSAlert?) {
        guard let alert else { return }
        if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .abort)
        } else if NSApp.modalWindow === alert.window {
            NSApp.abortModal()
        }
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
                              backupName: peerName, backupLinked: peerName != nil,
                              backupLiveConnected: peerName != nil && conductor.peerLiveConnected == true,
                              latencyMs: { if case let .connected(_, ms) = s.link { return ms }; return nil }(),
                              lastCue: cue, cueKeys: settings.cueKeys.map { .init(keycode: $0.keycode, label: $0.label, memo: $0.memo) },
                              setDiff: s.setDiff)
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

    // MARK: Switching to the backup (2.3)

    /// When the link to the other Mac was lost (nil while linked or never linked).
    private var linkLostAt: Date?
    private var wasLinked = false

    /// Asks first: making this Mac the main changes which Mac sends the cues.
    private func confirmBecomeMain() {
        let t = state.t
        let alert = NSAlert()
        alert.messageText = t.becomeMainTitle
        alert.informativeText = t.becomeMainMessage
        alert.addButton(withTitle: t.becomeMainConfirm)
        alert.addButton(withTitle: t.cancel)
        alert.buttons.first?.keyEquivalent = ""          // not by pressing Return by accident
        let deskBox = addDeskLine(to: alert, t)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var moveDesk = false
        if let deskBox {
            moveDesk = deskBox.state == .on
            if settings.desk.moveDeskWhenConfirming != moveDesk {
                settings.desk.moveDeskWhenConfirming = moveDesk      // remembered (also for the iPhone)
                try? store.save(settings)
            }
        }
        becomeMain(moveDesk: moveDesk)
    }

    /// Called for an iPhone that switched to this Mac: the console follows the last answer
    /// given in the confirmation on this Mac.
    func becomeMain() {
        let d = settings.desk
        becomeMain(moveDesk: d.enabled && !d.rows.isEmpty && d.moveDeskWhenConfirming)
    }

    private func becomeMain(moveDesk: Bool) {
        // The console first: the link still runs as on the backup Mac.
        if moveDesk {
            let r = desk.takeover(automatic: false)
            log.write("Console takeover with Make This Mac the Main: \(r)")
        }
        conductor.claimMain()
        refresh()
    }

    /// The conductor changed this Mac's role (this Mac claimed it, or the other Mac did).
    private func roleChanged(isMain: Bool) {
        settings.sendKeys = isMain
        settings.receiveNotes = !isMain
        log.write(isMain ? "Role: this Mac is the main Mac" : "Role: the other Mac is the main Mac; this Mac only receives")
        persistModes()
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

    // MARK: Console takeover (2.4, experimental)

    var deskActions: DeskSettingsActions {
        DeskSettingsActions(
            update: { [weak self] d in self?.setDeskSettings(d) },
            setTrigger: { [weak self] tr in self?.setDeskTrigger(tr) },
            check: { [weak self] in self?.desk.checkNow() }
        )
    }

    func setDeskSettings(_ new: DeskSettings) {
        var d = new
        d.host = d.host.trimmingCharacters(in: .whitespaces)
        d.fade = DeskSettings.nearestFade(d.fade)
        d.rows = Array(d.rows.prefix(DeskSettings.maxRows))
        for i in d.rows.indices { d.rows[i].fixedLevel = DeskLevel.clamped(d.rows[i].fixedLevel) }
        guard d != settings.desk else { return }
        if d.enabled != settings.desk.enabled { log.write("Console takeover (experimental) \(d.enabled ? "on" : "off")") }
        settings.desk = d
        try? store.save(settings)
        refresh()
    }

    /// Automatic switching moves the console without asking: say so before choosing it.
    private func setDeskTrigger(_ trigger: DeskTrigger) {
        guard trigger != settings.desk.trigger else { return }
        if trigger == .automatic {
            let t = state.t
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = t.deskAutoAlertTitle
            alert.informativeText = t.deskAutoAlertMessage
            alert.addButton(withTitle: t.deskAutoAlertConfirm)
            alert.addButton(withTitle: t.cancel)
            alert.buttons.first?.keyEquivalent = ""
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        var d = settings.desk
        d.trigger = trigger
        setDeskSettings(d)
    }

    /// The console line of "Make this Mac the main?": a checkbox when the console can be moved
    /// now, otherwise "The console cannot be moved" (and only the Mac switches). Nil: no checkbox.
    private func addDeskLine(to alert: NSAlert, _ t: Strings) -> NSButton? {
        let d = settings.desk
        guard d.enabled, !d.rows.isEmpty else { return nil }
        let snap = desk.snapshot()
        if snap?.canRestore == true { return nil }           // already switched
        let readiness = snap?.readiness ?? .notReady(.notConnected)
        if case let .notReady(why) = readiness {
            let note = NSTextField(wrappingLabelWithString: t.deskCannotMove(why))
            note.textColor = .systemOrange
            note.preferredMaxLayoutWidth = 300
            note.frame.size = note.fittingSize
            alert.accessoryView = note
            return nil
        }
        let box = NSButton(checkboxWithTitle: t.deskConfirmCheckbox(d.model.shortName, rows: d.rows.count, fade: d.fade),
                           target: nil, action: nil)
        box.state = d.moveDeskWhenConfirming ? .on : .off
        box.sizeToFit()
        alert.accessoryView = box
        return box
    }

    /// Restoring moves faders during the show: asks first.
    private func confirmRestoreDesk() {
        guard let snap = desk.snapshot(), snap.canRestore else { return }
        let t = state.t
        let alert = NSAlert()
        alert.messageText = t.deskRestoreTitle
        alert.informativeText = t.deskRestoreMessage(snap.move?.fade ?? settings.desk.fade)
        alert.addButton(withTitle: t.deskRestoreConfirm)
        alert.addButton(withTitle: t.cancel)
        alert.buttons.first?.keyEquivalent = ""
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        log.write("Console restore: \(desk.restore())")
        refresh()
    }

    /// Runs the console link only while it is wanted: the feature is on, an address is set, and
    /// this Mac receives (the backup) or still has a takeover to undo or a message to show.
    /// Automatic mode switches the console once when the main Mac has been silent for 3 s.
    private func updateDesk(_ s: inout ViewState) {
        let d = settings.desk
        var snap = desk.snapshot()
        let wanted: DeskSettings? = d.enabled && d.hasValidHost && (!settings.sendKeys || snap?.needsLink == true) ? d : nil
        if wanted != deskConfig {
            deskConfig = wanted
            desk.configure(wanted)
            if wanted == nil { snap = nil }
        }
        s.deskSettings = d
        s.deskActive = wanted != nil
        s.desk = d.enabled ? snap : nil
        guard wanted != nil, d.trigger == .automatic else { deskAutoArmed = false; return }
        if case .connected = s.link, !settings.sendKeys {
            deskAutoArmed = true
        } else if s.mainLost, deskAutoArmed {
            // The Mac's own role still switches only as before (by a person or an iPhone).
            deskAutoArmed = false
            log.write("Console takeover (automatic, main Mac silent for 3 s): \(desk.takeover(automatic: true))")
            s.desk = desk.snapshot()
        }
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
        s.approvalRequest = approval?.name
        s.lastCue = snap.lastCue
        s.cueKeys = settings.cueKeys
        s.blockCueKeys = settings.blockCueKeys
        s.cueKeysBlocked = keyMonitor.isBlocking
        s.accessibility = hasAccessibility ? .granted : .denied
        s.update = updater.state
        s.appVersion = updater.currentVersion
        s.autoUpdate = settings.autoUpdate
        updateShowActivity(linked: s.linkedPeerID != nil)
        if case .connected = s.link { wasLinked = true; linkLostAt = nil }
        else if wasLinked, linkLostAt == nil { linkLostAt = Date() }
        s.claimsMain = conductor.claimsMain
        s.mainLost = !settings.sendKeys && linkLostAt.map { Date().timeIntervalSince($0) >= 3 } == true
        s.liveConnected = bridge.isConnected
        conductor.setLiveConnected(s.liveConnected)
        conductor.setLocalSet(s.liveConnected ? SetSummary(bridge.snapshot()) : nil)
        s.setDiff = conductor.setDiff
        s.backupLiveConnected = conductor.peerLiveConnected
        s.bridgeInstalled = LiveBridgeInstaller.isInstalled
        // Live still runs an older script (it loads the new files at its next start).
        s.bridgeNeedsRestart = s.liveConnected && (bridge.snapshot().song.bridgeVersion ?? 0) < LiveBridgeInstaller.bundledVersion
        s.approvedDevices = settings.approvedDevices
        s.remoteClients = remoteClients
        s.remoteEnabled = settings.remoteEnabled
        s.remoteWatch = remoteWatch
        // Connection display: the other Mac learns this Mac's iPhones (the backup shows the line),
        // and this Mac the other's.
        conductor.setRemoteSummary(RemoteSummary(phones: remoteClients, watch: remoteWatch))
        s.peerRemote = conductor.peerRemoteSummary
        updateDesk(&s)
        updateRemoteStatus(s, snap)
        if s != state { state = s }
    }
}
#endif
