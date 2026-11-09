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
    func s(_ en: String, _ ja: String) -> String { lang == .ja ? ja : en }

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
    var sendMyKeysHint: String { s("Cue keys you press go to this Mac and to the connected Mac", "押したキューのキーを、この Mac と接続先の Mac に送ります") }
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

    // MARK: Pairing
    var pairingTitle: String { s("Pairing Code", "合言葉") }
    var pairingExplain: String { s("Macs that use the same pairing code can connect to each other, and nothing else can. Their traffic is also encrypted.", "2台の Mac で同じ合言葉を使うと、その2台だけがつながります。通信の中身も暗号化されます。") }
    var pairingNeeded: String { s("To connect, both Macs need the same pairing code.", "接続するには、2台で同じ合言葉を使います。") }
    var pairingNeededHint: String { s("You only need to do this once.", "一度設定すれば、次からは不要です") }
    var setUpPairing: String { s("Set Up Pairing Code…", "合言葉を設定…") }
    var needsPairingDetail: String { s("Set a pairing code to connect", "合言葉を設定すると接続できます") }
    var thisMacCode: String { s("This Mac’s pairing code", "この Mac の合言葉") }
    var noCodeYet: String { s("Not set", "未設定") }
    var makeNewCode: String { s("Make New Code", "新しく作る") }
    var copy: String { s("Copy", "コピー") }
    var enterCode: String { s("Enter Code…", "合言葉を入力…") }
    var enterCodeTitle: String { s("Enter Pairing Code", "合言葉を入力") }
    var enterCodeExplain: String { s("Type the 10 characters shown on the other Mac under Settings > Pairing Code.", "もう1台の Mac の「設定」>「合言葉」に出ている10文字を入れてください。") }
    var enterCodeRule: String { s("Upper or lower case and hyphens do not matter.", "大文字・小文字、ハイフンの有無は区別しません。") }
    var invalidCode: String { s("That is not a valid code: it has 10 letters and digits (no 0, 1, I, L or O).", "合言葉の形になっていません。10文字の英数字です（0・1・I・L・O は使いません）。") }
    var haveOtherCode: String { s("If the other Mac already has a code:", "もう1台の Mac で作った合言葉があるときは") }
    var replaceCodeTitle: String { s("Make a new pairing code?", "新しい合言葉を作りますか？") }
    var replaceCodeMessage: String { s("The current code stops working. Enter the new code on the other Mac too.", "今の合言葉は使えなくなります。もう1台の Mac にも新しい合言葉を入れてください。") }
    var makeNew: String { s("Make New", "作る") }
    var cancel: String { s("Cancel", "キャンセル") }
    var save: String { s("Save", "保存") }
    var codeMismatch: String { s("Different pairing code", "合言葉が違います") }
    func thisMacAddress(_ a: String) -> String { s("This Mac’s IP address: \(a)", "この Mac の IP アドレス: \(a)") }
    var noAddress: String { s("none (not on a network)", "なし（ネットワーク未接続）") }
    var connectByIP: String { s("Connect by IP Address…", "IPアドレスで接続…") }
    var connectByIPHint: String { s("If the other Mac is not listed (⇧⌘K)", "一覧に出ないときはこちら（⇧⌘K）") }
    var connectByIPTitle: String { s("Connect by IP Address", "IPアドレスで接続") }
    var connectByIPExplain: String { s("Use this when the other Mac is not listed. Type the IP address shown on the other Mac under Settings > Pairing Code. Both Macs need the same pairing code.", "相手が一覧に出ないときに使います。相手の Mac の「設定」>「合言葉」に出ている IP アドレスを入れてください。合言葉が同じ必要があります。") }
    func portLabel(_ p: UInt16) -> String { s("Port \(p)", "ポート \(p)") }
    var invalidAddress: String { s("Type an IP address such as 192.168.1.20.", "192.168.1.20 のような IP アドレスを入れてください。") }

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
    case midiPort
    case listenFailed
    case keyCaptureFailed
}
#endif
