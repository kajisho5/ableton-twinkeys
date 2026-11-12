import Foundation
import SwiftUI
import WatchConnectivity
import WatchKit

/// The watch's side of the link to the iPhone app (WatchLink.swift there).
/// State arrives as `WatchState`; commands go out with `sendMessage` only while the iPhone is reachable.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published private(set) var state: WatchState?
    @Published private(set) var reachable = false
    /// A short message after a command did not go through (hidden after a few seconds).
    @Published private(set) var notice: String?
    /// The next scene chosen on the watch (crown or list) until the iPhone shows it as selected.
    @Published private(set) var choice: Int?
    private var choiceAt = Date.distantPast
    private var choiceSent = true
    private var sendChoiceTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    /// The time the countdown of `state.left` starts from.
    private var leftBase = Date()
    private var lastGo = Date.distantPast
    /// The iPhone's last command problem already shown as a notice.
    private var shownProblem: String?
    let demo: Bool

    init(demo: Bool) {
        self.demo = demo
        super.init()
        if demo {
            state = Self.demoState()
            reachable = true
            return
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: What the pages show

    var names: [String] { state?.names ?? [] }

    /// The scene GO plays next (nil: none, e.g. after the last scene).
    var nextIndex: Int? {
        guard let st = state else { return nil }
        let i = choice ?? st.selected
        return i >= 0 && i < st.names.count ? i : nil
    }

    var playingIndex: Int? {
        guard let p = state?.playing, p >= 0, p < names.count else { return nil }
        return p
    }

    func sceneName(_ i: Int) -> String {
        let n = i >= 0 && i < names.count ? names[i] : ""
        return n.isEmpty ? L.s("Scene \(i + 1)", "シーン \(i + 1)") : n
    }

    /// Why GO and the list cannot work now (nil: they can).
    var problem: String? {
        if !reachable { return L.s("Can't reach the iPhone", "iPhone に届きません") }
        guard let st = state else { return L.s("Open TwinKeys Remote on the iPhone", "iPhone で TwinKeys Remote を開いてください") }
        if !st.connected { return L.s("iPhone is not connected to the Mac", "iPhone が Mac につながっていません") }
        return nil
    }

    var canGo: Bool { problem == nil && nextIndex != nil }

    /// Seconds left of the playing scene now (counted down on the watch between states).
    func leftNow(_ now: Date) -> Double? {
        guard let st = state, let left = st.left else { return nil }
        guard st.running else { return left }
        return max(0, left - now.timeIntervalSince(leftBase))
    }

    // MARK: Actions (each press is felt on the wrist)

    /// GO: plays the scene shown as next; the one after it becomes next. A second GO within 0.5 s is ignored.
    func go() {
        guard Date().timeIntervalSince(lastGo) >= WatchWire.goGuard else { return }
        guard canGo, let i = nextIndex else {
            haptic(.failure)
            show(problem ?? L.s("End of the scene list", "シーンの最後です"))
            return
        }
        lastGo = Date()
        haptic(.click)
        // A scene just chosen with the crown is sent first (messages arrive in the order sent).
        if choice != nil, !choiceSent { sendChoiceTask?.cancel(); sendChoice() }
        send(.go(scene: i)) { [weak self] ok, err in
            guard let self else { return }
            if ok {
                self.haptic(.success)
                // Show the following scene at once (the iPhone selects it; Live reports it a moment later).
                if i + 1 < self.names.count { self.setChoice(i + 1, sent: true) } else { self.choice = nil }
            } else {
                self.failed(err)
            }
        }
    }

    /// Makes scene `i` the next one (does not play). From the crown: sent when the crown rests a moment.
    func choose(_ i: Int, now: Bool = false) {
        guard i >= 0, i < names.count else { return }
        if i == nextIndex && (choice == nil || choiceSent) {
            if now { haptic(.click) }
            return
        }
        if now { haptic(.click) }
        guard problem == nil else {
            if now { haptic(.failure); show(problem ?? "") }
            return
        }
        setChoice(i, sent: false)
        sendChoiceTask?.cancel()
        if now { sendChoice(); return }
        sendChoiceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.sendChoice()
        }
    }

    func allNotesOff() {
        haptic(.click)
        send(.allNotesOff) { [weak self] ok, err in
            guard let self else { return }
            if ok { self.haptic(.success) } else { self.failed(err) }
        }
    }

    /// Ask the iPhone for the current state (the app opened or the iPhone became reachable).
    func refresh() {
        guard !demo else { return }
        send(.refresh) { _, _ in }
    }

    // MARK: Inside

    private func setChoice(_ i: Int, sent: Bool) {
        choice = i
        choiceAt = Date()
        choiceSent = sent
    }

    private func sendChoice() {
        guard let c = choice, !choiceSent else { return }
        choiceSent = true
        choiceAt = Date()
        send(.select(scene: c)) { [weak self] ok, err in
            guard let self, !ok else { return }
            if self.choice == c { self.choice = nil }
            self.failed(err)
        }
    }

    private func failed(_ code: String?) {
        guard code != "guard" else { return }    // a double tap the iPhone ignored
        haptic(.failure)
        show(Self.text(for: code ?? "unreachable"))
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func haptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    /// Short texts for the iPhone's answers and its last command problem (`WatchState.problem`).
    static func text(for code: String) -> String {
        switch code {
        case "changed": return L.s("Next scene changed. Check it, then press again.", "次のシーンが変わりました。確かめてから押してください")
        case "end": return L.s("End of the scene list", "シーンの最後です")
        case "offline": return L.s("iPhone is not connected to the Mac", "iPhone が Mac につながっていません")
        case "noApp", "unreachable": return L.s("Can't reach TwinKeys Remote. Open it on the iPhone.", "iPhone に届きません。TwinKeys Remote を開いてください")
        case "locked": return L.s("Show lock is on", "本番ロック中です")
        case "structure_changed": return L.s("Live's scenes changed. Press again.", "Live のシーンが変わりました。もう一度押してください")
        case "late": return L.s("Live ran it late. Do not press again.", "Live で遅れて動きました。押し直さないでください")
        case "no_answer": return L.s("No answer from Live. Check Live first.", "Live から返事がありません。Live を確かめてください")
        case "backup_failedLive", "backup_noLive", "backup_missing":
            return L.s("Ran on the main Mac, not on the backup", "メインでは動き、バックアップでは動いていません")
        default: return L.s("Not run (\(code))", "実行できませんでした（\(code)）")
        }
    }

    /// Sends a command; `done` runs on the main actor with the iPhone's answer.
    private func send(_ cmd: WatchCommand, done: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        if demo { runDemo(cmd); done(true, nil); return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable, let data = WatchWire.encode(cmd) else {
            done(false, "unreachable")
            return
        }
        Self.deliver(data, over: s) { ok, err, st in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let st { self.apply(st) }
                    done(ok, err)
                }
            }
        }
    }

    /// Outside the main actor: WatchConnectivity calls the reply and error handlers on its own queue.
    private nonisolated static func deliver(_ data: Data, over session: WCSession,
                                            then: @escaping @Sendable (Bool, String?, WatchState?) -> Void) {
        session.sendMessage([WatchWire.commandKey: data], replyHandler: { reply in
            then(reply[WatchWire.okKey] as? Bool ?? false, reply[WatchWire.errorKey] as? String,
                 WatchWire.decode(WatchState.self, reply[WatchWire.stateKey]))
        }, errorHandler: { _ in
            then(false, "unreachable", nil)
        })
    }

    fileprivate func apply(_ st: WatchState) {
        // The application context and a message can bring the same state twice, or an older one late.
        if let old = state, !demo, st.stamp < old.stamp, old.stamp - st.stamp < 30 { return }
        let now = Date()
        state = st
        // Count down from the iPhone's clock when it agrees with the watch's, otherwise from arrival.
        let made = Date(timeIntervalSince1970: st.stamp)
        leftBase = abs(now.timeIntervalSince(made)) < 2 ? made : now
        if let c = choice, choiceSent, c == st.selected || now.timeIntervalSince(choiceAt) > 3 { choice = nil }
        if let p = st.problem, p != shownProblem { show(Self.text(for: p)) }
        shownProblem = st.problem
    }

    fileprivate func setReachable(_ r: Bool) {
        let was = reachable
        reachable = r
        if r && !was { refresh() }
    }

    // MARK: Demo (fictional names, as the iPhone app's demo)

    private static func demoState() -> WatchState {
        var st = WatchState()
        st.names = ["オープニング", "SE 拍手", "M1 イントロ", "M1 本編", "暗転", "M2 イントロ", "M2 本編", "エンディング"]
        st.playing = 2
        st.selected = 3
        st.left = 26
        st.running = true
        st.connected = true
        st.mainOK = true
        st.backupOK = true
        st.lastCue = "次のシーン"
        st.lastCueOK = true
        st.stamp = Date().timeIntervalSince1970
        return st
    }

    private func runDemo(_ cmd: WatchCommand) {
        guard var st = state else { return }
        switch cmd {
        case let .select(i): st.selected = i
        case let .go(i):
            st.playing = i
            st.left = 95
            if i + 1 < st.names.count { st.selected = i + 1 }
        case .allNotesOff, .refresh: break
        }
        st.stamp = Date().timeIntervalSince1970
        apply(st)
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let st = WatchWire.decode(WatchState.self, session.receivedApplicationContext[WatchWire.stateKey])
        let r = session.isReachable
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let st { self.apply(st) }
                self.setReachable(r)    // asks for the current state when reachable
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        DispatchQueue.main.async { MainActor.assumeIsolated { self.setReachable(r) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let st = WatchWire.decode(WatchState.self, applicationContext[WatchWire.stateKey]) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(st) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let st = WatchWire.decode(WatchState.self, message[WatchWire.stateKey]) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(st) } }
    }
}
