import Combine
import Foundation
import TwinKeysCore
import WatchConnectivity

/// 2.3: the iPhone side of the Apple Watch app. The watch never talks to the Macs (no keys on the
/// watch): this sends it a small `WatchState` when something it shows changes, and runs its
/// `WatchCommand`s through RemoteModel, so the show lock applies exactly as on the iPhone.
/// Nothing happens when no watch is paired or the watch app is not installed.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private weak var model: RemoteModel?
    private var watching: AnyCancellable?
    private var lastSent: WatchState?
    private var lastSentAt = Date.distantPast
    private var checkQueued = false
    /// GO from the watch: the same 0.5 s guard as the iPhone's GO screen.
    private var lastGo = Date.distantPast
    /// The scene the watch made "next" just now (Live reports the new selection a moment later).
    private var watchChoice: (scene: Int, at: Date)?
    /// At most about two states a second.
    static let minInterval: TimeInterval = 0.5

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Called once when the app's window appears.
    func start(_ model: RemoteModel) {
        guard self.model !== model, let s = session else { return }
        self.model = model
        // Any published change of the model (Live state, status, lock, connection) may change what the
        // watch shows; `stateMayChange` compares and sends only real changes.
        watching = model.objectWillChange.sink { [weak self] _ in self?.stateMayChange() }
        s.delegate = self
        s.activate()
    }

    // MARK: State to the watch

    private var watchReady: Bool {
        guard let s = session, s.activationState == .activated else { return false }
        return s.isPaired && s.isWatchAppInstalled
    }

    /// Connection display: the watch as WatchConnectivity sees it, for the top bar, Settings and the
    /// Mac (RemoteModel sends it with its pings). nil until the session is active.
    private func updateWatchStatus() {
        guard let m = model else { return }
        // `-demo` (screenshots) keeps its sample watch.
        if m.demo && !m.trialMode { return }
        var st: RemoteWatchState?
        if let s = session, s.activationState == .activated {
            let installed = s.isPaired && s.isWatchAppInstalled
            st = RemoteWatchState(paired: s.isPaired, appInstalled: installed, reachable: installed && s.isReachable)
        }
        if m.watch != st { m.watch = st }
    }

    /// WatchConnectivity told something changed: the watch's state, and what the watch shows.
    private func sessionChanged() {
        updateWatchStatus()
        push(force: true)
    }

    private func stateMayChange() {
        guard !checkQueued, watchReady else { return }
        checkQueued = true
        // objectWillChange comes before the change: look at the model on the next turn of the run loop at the earliest.
        let wait = max(0, Self.minInterval - Date().timeIntervalSince(lastSentAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.checkQueued = false
                self.push()
            }
        }
    }

    /// The latest state goes to the application context (the watch gets it when it opens) and, when the
    /// watch app is reachable, also as a message (faster). The watch keeps the newest by `stamp`.
    private func push(force: Bool = false) {
        guard watchReady, let s = session, let st = makeState() else { return }
        if !force, let last = lastSent, last.sameAs(st) { return }
        guard let data = WatchWire.encode(st) else { return }
        lastSent = st
        lastSentAt = Date()
        try? s.updateApplicationContext([WatchWire.stateKey: data])
        if s.isReachable { s.sendMessage([WatchWire.stateKey: data], replyHandler: nil, errorHandler: nil) }
    }

    private func makeState() -> WatchState? {
        guard let m = model else { return nil }
        let live = m.live
        let playing = live.scenes.first { $0.playing }
        var st = WatchState()
        st.names = live.scenes.map(\.name)
        st.playing = playing?.index
        st.selected = live.song.selectedScene
        if let sc = playing {
            // As the GO screen: the longest time left of the clips playing in that scene.
            st.left = live.tracks.filter { $0.playingSlot == sc.index }.compactMap { live.secondsLeft(track: $0.index) }.max()
        }
        st.running = live.song.playing
        st.connected = m.isConnected
        let status = m.status
        st.mainOK = m.isConnected && status?.mainLiveConnected == true
        st.backupOK = m.isConnected && status?.backupLinked == true && status?.backupLiveConnected == true
        if let c = status?.lastCue {
            st.lastCue = c.memo.isEmpty ? c.label : c.memo
            switch c.delivery {
            case "delivered": st.lastCueOK = true
            case "missing": st.lastCueOK = false
            default: st.lastCueOK = nil
            }
        }
        if m.qlabOn, let q = m.qlabStatus {
            st.target = q.target.rawValue
            let now = Date()
            if let r = q.running.first {
                st.qlabNow = r.title
                st.qlabLeft = m.qlabLeft(r, now: now)
                st.qlabTotal = r.duration
                st.running = !r.paused
            }
            if let n = m.qlabNext { st.qlabNext = n.title; st.qlabNextNumber = n.number }
            st.qlabOK = m.isConnected && q.state.canControl && q.backup?.state.canControl == true
            let cues = m.qlabCues
            let at = cues.firstIndex { $0.uniqueID == q.playheadID } ?? 0
            let ids = Set(q.running.map(\.uniqueID))
            let lo = max(0, at - 3), hi = min(cues.count, at + 5)
            st.qlabCues = lo < hi ? cues[lo..<hi].map { WatchQLabCue(number: $0.number, name: $0.name, running: ids.contains($0.uniqueID),
                                                                       next: $0.uniqueID == q.playheadID) } : []
        }
        st.locked = m.locked
        st.problem = m.lastResult
        st.stamp = Date().timeIntervalSince1970
        return st
    }

    // MARK: Commands from the watch

    /// nil: done (sent to the Mac). Otherwise a short code the watch explains.
    private func run(_ cmd: WatchCommand) -> String? {
        guard let m = model else { return "noApp" }
        if case .refresh = cmd { return nil }
        guard m.isConnected else { return "offline" }
        switch cmd {
        case .refresh:
            return nil
        case let .select(i):
            guard i >= 0, i < m.live.scenes.count else { return "end" }
            m.run(.selectScene(i))
            watchChoice = (i, Date())
            return nil
        case let .go(i):
            // As GoView.go(): a second GO within 0.5 s is ignored (a double tap must not skip a cue).
            guard Date().timeIntervalSince(lastGo) >= GoView.goGuard else { return "guard" }
            let live = m.live
            let chosenOnWatch = watchChoice.map { $0.scene == i && Date().timeIntervalSince($0.at) < 3 } ?? false
            // Play only the scene the watch showed as next. If "next" changed meanwhile (on the iPhone,
            // the Mac or in Live), nothing plays and the watch shows the new one.
            guard i == live.song.selectedScene || chosenOnWatch else { return "changed" }
            guard i >= 0, i < live.scenes.count else { return "end" }
            lastGo = Date()
            m.go(scene: i)
            // The Mac selects the next scene after launching this one.
            if i + 1 < live.scenes.count { watchChoice = (i + 1, Date()) } else { watchChoice = nil }
            return nil
        case .allNotesOff:
            m.allNotesOff()
            return nil
        case let .qlabGo(expect):
            guard m.qlabOn else { return "offline" }
            guard Date().timeIntervalSince(lastGo) >= GoView.goGuard else { return "guard" }
            // Only the cue the watch showed as next (as for Live: a changed "next" plays nothing).
            guard expect == (m.qlabNext?.number ?? m.qlabStatus?.playheadNumber) else { return "changed" }
            lastGo = Date()
            m.qlabGo()
            return nil
        case .qlabPanic:
            m.qlab(QLabCommand(action: .panic))
            return nil
        case let .qlabPlayhead(n):
            guard !n.isEmpty else { return "qlab_no_number" }
            m.qlab(QLabCommand(action: .setPlayhead, cueNumber: n))
            return nil
        }
    }

    private func reply(_ cmd: WatchCommand?) -> [String: Any] {
        let err: String?
        if let cmd { err = run(cmd) } else { err = "bad" }
        var r: [String: Any] = [WatchWire.okKey: err == nil]
        if let err { r[WatchWire.errorKey] = err }
        if let st = makeState(), let d = WatchWire.encode(st) { r[WatchWire.stateKey] = d }
        return r
    }
}

extension WatchLink: WCSessionDelegate {
    // WatchConnectivity calls these on its own queue: hop to the main queue (in order) for the model.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.sessionChanged() } }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.updateWatchStatus() } }
    }

    /// The iPhone switched to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.sessionChanged() } }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.sessionChanged() } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let cmd = WatchWire.decode(WatchCommand.self, message[WatchWire.commandKey])
        DispatchQueue.main.async { MainActor.assumeIsolated { replyHandler(self.reply(cmd)) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let cmd = WatchWire.decode(WatchCommand.self, message[WatchWire.commandKey])
        DispatchQueue.main.async { MainActor.assumeIsolated { _ = self.reply(cmd) } }
    }
}
