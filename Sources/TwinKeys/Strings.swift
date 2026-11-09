#if os(macOS)
import Foundation
import TwinKeysCore

/// UI language. "system" follows the first preferred language of macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ja
    var id: String { rawValue }

    /// The macOS language, read once at launch (macOS asks to reopen apps after a language change).
    static let systemResolved: AppLanguage = {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("ja") ? .ja : .en
    }()
}

/// All user-facing text in English and Japanese.
/// Japanese follows the wording of macOS itself (システム設定, 入力監視, 接続解除 …)
/// and keeps sentences short.
struct Strings {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang == .system ? AppLanguage.systemResolved : lang }
    private func s(_ en: String, _ ja: String) -> String { lang == .ja ? ja : en }

    // MARK: Header
    var notConnected: String { s("Not connected", "未接続") }
    func connecting(_ name: String) -> String { s("Connecting to \(name)…", "\(name) に接続中…") }
    func connected(_ name: String) -> String { s("Connected to \(name)", "\(name) に接続済み") }
    var sendingAndReceiving: String { s("Sending and receiving", "送信・受信中") }
    var sending: String { s("Sending", "送信中") }
    var receiving: String { s("Receiving", "受信中") }
    var bothOff: String { s("Sending and receiving are off", "送信も受信もオフ") }
    var searching: String { s("Searching for TwinKeys…", "TwinKeys を探しています…") }
    var chooseMac: String { s("Choose a Mac below and click Connect", "下の一覧から Mac を選んで「接続」をクリック") }
    func retrying(_ attempt: Int) -> String { s("No answer yet, retrying (attempt \(attempt))", "応答がありません。再試行中（\(attempt) 回目）") }
    var waitingForAnswer: String { s("Waiting for an answer…", "応答を待っています…") }
    func latencyLine(_ latency: String, _ roles: String) -> String { s("Latency \(latency)  ·  \(roles)", "遅延 \(latency)  ·  \(roles)") }
    var measuring: String { s("measuring…", "測定中…") }
    func statusLabel(_ h: String, _ d: String) -> String { s("Connection status: \(h). \(d)", "接続状態：\(h)。\(d)") }

    var allNotesOff: String { s("All Notes Off", "オールノートオフ") }
    var allNotesOffHelp: String { s("Stop every sounding note on this Mac and the connected Mac (⌃⌘P)", "この Mac と接続先の Mac で鳴っている音をすべて止めます（⌃⌘P）") }
    var allNotesOffHint: String { s("Sends All Notes Off to this Mac and to the connected Mac", "この Mac と接続先の Mac にオールノートオフを送ります") }

    // MARK: Banners
    var needsInputMonitoring: String { s("Key capture needs Input Monitoring permission.", "キー入力を使うには「入力監視」の許可が必要です。") }
    var openSystemSettings: String { s("Open System Settings…", "システム設定を開く…") }
    var openSystemSettingsHint: String { s("Opens Privacy & Security, Input Monitoring", "「プライバシーとセキュリティ」の「入力監視」を開きます") }
    var checkAgain: String { s("Check Again", "もう一度確認") }
    var midiPortFailed: String { s("The TwinKeys MIDI port could not be created. Notes cannot reach your music software.", "TwinKeys の MIDI ポートを作成できませんでした。音楽ソフトにノートが届きません。") }

    func problem(_ p: AppProblem) -> String {
        switch p {
        case let .settingsUnreadable(backup):
            return s("settings.json could not be read. It was kept as \(backup) and default settings are in use.",
                     "settings.json を読み込めなかったため、\(backup) として残し、初期設定で起動しました。")
        case .duplicateID:
            return s("Another Mac was using the same TwinKeys ID (its settings were copied from this Mac). A new ID was made: quit and reopen TwinKeys.",
                     "ほかの Mac が同じ TwinKeys の ID を使っていました（この Mac から設定がコピーされたためです）。新しい ID を作成したので、TwinKeys を終了してから開き直してください。")
        case .mappingUnreadable:
            return s("mapping.json could not be read. Using the default mapping.", "mapping.json を読み込めなかったため、初期のキー配置を使っています。")
        case .midiPort:
            return midiPortFailed
        case .listenFailed:
            return s("Could not start listening for other Macs.", "ほかの Mac からの接続を待ち受けられませんでした。")
        case .keyCaptureFailed:
            return s("Key capture could not start even though permission is granted. Quit and reopen TwinKeys.", "許可はあるのに、キー入力を開始できませんでした。TwinKeys を終了して開き直してください。")
        }
    }

    // MARK: Peers
    var nearbyTwinKeys: String { s("Nearby TwinKeys", "近くの TwinKeys") }
    var noPeersTitle: String { s("No TwinKeys found on this network", "このネットワークに TwinKeys が見つかりません") }
    var noPeersBody: String {
        s("Make sure both Macs are on the same Wi-Fi or wired network, and that TwinKeys is allowed in System Settings > Privacy & Security > Local Network.",
          "2台の Mac が同じ Wi-Fi か有線ネットワークにつながっているか、「システム設定」>「プライバシーとセキュリティ」>「ローカルネットワーク」で TwinKeys がオンになっているか確認してください。")
    }
    var noPeersDenied: String {
        s("macOS is blocking local network access for TwinKeys. Allow it in System Settings > Privacy & Security > Local Network.",
          "TwinKeys のローカルネットワークへのアクセスが許可されていません。「システム設定」>「プライバシーとセキュリティ」>「ローカルネットワーク」でオンにしてください。")
    }
    var howToFix: String { s("How to Fix…", "対処方法…") }
    var connect: String { s("Connect", "接続") }
    var disconnect: String { s("Disconnect", "接続解除") }
    func connectTo(_ name: String) -> String { s("Connect to \(name)", "\(name) に接続") }
    func disconnectFrom(_ name: String) -> String { s("Disconnect from \(name)", "\(name) との接続を解除") }
    var disconnectHelp: String { s("Disconnect (⌘K)", "接続解除（⌘K）") }
    var incompatible: String { s("Different TwinKeys version. Use the same version on both Macs.", "TwinKeys のバージョンが違います。両方の Mac で同じバージョンを使ってください。") }
    var connectingShort: String { s("connecting…", "接続中…") }
    var anotherMac: String { s("another Mac", "相手の Mac") }
    func modes(_ p: PeerInfo) -> String {
        switch (p.sends, p.receives) {
        case (true, true): return s("Send + Receive", "送信・受信")
        case (true, false): return s("Send", "送信")
        case (false, true): return s("Receive", "受信")
        case (false, false): return s("Idle", "待機")
        }
    }

    // MARK: Mode and keyboard
    var modeAndKeyboard: String { s("Mode and Keyboard", "モードとキーボード") }
    var sendMyKeys: String { s("Send my keys", "キーを送信") }
    var sendMyKeysHint: String { s("Keys you press play notes here and on the connected Mac", "押したキーの音を、この Mac と接続先の Mac で鳴らします") }
    var receiveNotes: String { s("Receive notes", "ノートを受信") }
    var receiveNotesHint: String { s("Notes from the connected Mac play on this Mac", "接続先の Mac から届いたノートを、この Mac で鳴らします") }
    var keyCapture: String { s("Key capture", "キー入力") }
    var keyCaptureOn: String { s("Key capture: On", "キー入力: オン") }
    var keyCaptureOff: String { s("Key capture: Off", "キー入力: オフ") }
    var keyCaptureNotSending: String { s("Key capture: Not sending", "キー入力: 送信していません") }
    var valueOn: String { s("On", "オン") }
    var valueOff: String { s("Off", "オフ") }
    var valueNotSending: String { s("Not sending", "送信していません") }
    var valueNeedsPermission: String { s("Needs permission", "許可が必要") }
    var keyCaptureNeedsPermission: String { s("Key capture: Needs permission", "キー入力: 許可が必要") }
    var keyCapturePaused: String { s("Key capture: Paused (password field)", "キー入力: 一時停止中（パスワード入力中）") }
    var valuePaused: String { s("Paused", "一時停止中") }
    var keyCaptureHelp: String { s("Turn key capture on or off (⌃⌘K)", "キー入力のオン／オフ（⌃⌘K）") }
    var octave: String { s("Octave", "オクターブ") }
    var velocity: String { s("Velocity", "ベロシティ") }
    var heldNotes: String { s("Held notes", "発音中のノート") }
    func changeWith(_ title: String, _ value: String, _ a: String, _ b: String) -> String {
        s("\(title) \(value). Change with \(a) and \(b)", "\(title) \(value)。\(a) と \(b) で変更")
    }
    var doubleNotesHint: String {
        s("Turn off the computer MIDI keyboard in your music software to avoid double notes.",
          "音が二重に鳴らないよう、音楽ソフト側のコンピュータ MIDI キーボードはオフにしてください。")
    }

    // MARK: Permissions row
    var inputMonitoringAllowed: String { s("Input Monitoring: Allowed", "入力監視: 許可済み") }
    var inputMonitoringNotAllowed: String { s("Input Monitoring: Not allowed", "入力監視: 未許可") }
    var inputMonitoringChecking: String { s("Input Monitoring: Checking…", "入力監視: 確認中…") }
    var localNetworkVisible: String { s("Local Network: Peer found", "ローカルネットワーク: 相手を検出") }
    var localNetworkSearching: String { s("Local Network: Searching", "ローカルネットワーク: 検索中") }
    var localNetworkNotAllowed: String { s("Local Network: Not allowed", "ローカルネットワーク: 未許可") }

    // MARK: Help sheet
    var helpTitle: String { s("Finding the other Mac", "相手の Mac が見つからないとき") }
    var helpSteps: [String] {
        lang == .ja ? [
            "両方の Mac で TwinKeys を開きます。",
            "2台を同じネットワークにつなぎます。有線か、専用のルーターを使うと安定します。",
            "それぞれの Mac で「システム設定」>「プライバシーとセキュリティ」>「ローカルネットワーク」を開き、TwinKeys をオンにします。macOS 15 以降では、初回に確認が表示されます。",
            "macOS のファイアウォールから受信接続を許可するか聞かれたら、「許可」をクリックします。",
            "それでも見つからないときは、VPN と、このネットワークの「IPアドレスのトラッキングを制限」をオフにしてみてください。",
        ] : [
            "Open TwinKeys on both Macs.",
            "Connect both Macs to the same network. A wired network or a dedicated router is the most reliable.",
            "On each Mac, open System Settings > Privacy & Security > Local Network and turn on TwinKeys. (macOS 15 or later asks for this the first time.)",
            "If the macOS firewall asks whether TwinKeys may accept incoming connections, click Allow.",
            "Turn off VPN software and “Limit IP Address Tracking” for this network if the Macs still cannot see each other.",
        ]
    }
    var openLocalNetworkSettings: String { s("Open Local Network Settings…", "ローカルネットワークの設定を開く…") }
    var done: String { s("Done", "完了") }

    // MARK: Settings
    func autoNoteOff(_ seconds: Int) -> String { s("Automatic note-off after \(seconds) s", "\(seconds) 秒で自動ノートオフ") }
    var autoNoteOffDisabled: String { s("Automatic note-off: Off", "自動ノートオフ: オフ") }
    var autoNoteOffHelp: String { s("Protects against stuck notes if a note-off is lost. Notes from the other Mac wait at least 3 s. 0 turns it off.", "ノートオフが届かなかったときに、音が鳴り続けるのを防ぎます。相手の Mac から届いた音は最低 3 秒待ちます。0 にするとオフになります。") }
    var autoNoteOffHint: String { s("A note that never receives its note-off is stopped after this time. 0 turns it off.", "ノートオフが届かない音を、この時間で止めます。0 でオフ。") }
    var showMappingFile: String { s("Show Mapping File in Finder", "キー配置ファイルをFinderで表示") }
    var reloadMapping: String { s("Reload Mapping", "キー配置を再読み込み") }
    var restoreMapping: String { s("Restore Default Mapping", "キー配置を初期状態に戻す") }
    var mappingHelp: String { s("Edit mapping.json to change which physical keys play which notes.", "どのキーでどの音を鳴らすかは、mapping.json で変更できます。") }
    var language: String { s("Language", "言語") }
    func languageName(_ l: AppLanguage) -> String {
        switch l {
        case .system: return s("Same as System", "システムに合わせる")
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
    var languageNote: String {
        s("Standard menu items such as Hide TwinKeys and Quit TwinKeys follow the macOS language.",
          "「TwinKeysを非表示」「TwinKeysを終了」などの標準メニュー項目は、macOS の言語で表示されます。")
    }

    // MARK: Menus and About
    var connectionMenu: String { s("Connection", "接続") }
    var keyCaptureMenuOff: String { s("Turn Key Capture Off", "キー入力をオフ") }
    var keyCaptureMenuOn: String { s("Turn Key Capture On", "キー入力をオン") }
    var help: String { s("TwinKeys Help", "TwinKeysヘルプ") }
    var helpMissing: String { s("The help file is not included in this build.", "このビルドにはヘルプのファイルが入っていません。") }
    var helpOnGitHub: String { s("Open on GitHub", "GitHubで開く") }
    var showLogs: String { s("Show Log Folder in Finder", "ログフォルダをFinderで表示") }
    var aboutMenu: String { s("About TwinKeys", "TwinKeysについて") }
    var aboutCredits: String {
        s("Made by Shogo Kajiyama / SEVENTHWELL\nUnofficial third-party tool. Not affiliated with Ableton.\nMIT License",
          "制作: Shogo Kajiyama / SEVENTHWELL\n非公式のサードパーティ製ツールです。Ableton 社とは関係ありません。\nMIT License")
    }
}

/// Problems shown in the window, translated at display time.
enum AppProblem: Hashable {
    case settingsUnreadable(backup: String)
    case duplicateID
    case mappingUnreadable
    case midiPort
    case listenFailed
    case keyCaptureFailed
}
#endif
