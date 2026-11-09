#if os(macOS)
import Foundation
import TwinKeysCore

/// Text for cue keys, the delivery check, updates and the menu bar (1.0.0).
extension Strings {
    // MARK: Last cue panel
    var lastCue: String { s("Last cue", "直前のキュー") }
    var receivedCue: String { s("Received cue", "受け取ったキュー") }
    var noCueYet: String { s("No cue yet. Press a cue key.", "まだキューを叩いていません。キューのキーを押すと出ます。") }
    var noCueReceivedYet: String { s("No cue received yet.", "まだキューを受け取っていません。") }
    func cueCount(_ n: Int) -> String { s("Cue \(n) since connecting", "接続してから \(n) 回目") }
    var deliveredToBackup: String { s("Reached the backup", "バックアップに届きました") }
    var waitingForBackup: String { s("Waiting for the backup…", "バックアップの返事を待っています…") }
    var notConfirmed: String { s("No confirmation", "届いた確認がありません") }
    var notConfirmedDetail: String { s("Check that this cue fired on the backup.", "バックアップでこのキューが出ているか確かめてください") }
    var cannotConfirm: String { s("Delivery cannot be checked", "届いたかは確認できません") }
    var cannotConfirmDetail: String { s("The other Mac runs TwinKeys older than 1.0.0", "相手の TwinKeys が 1.0.0 より前です") }
    var cueNotConnected: String { s("Not connected", "接続していません") }
    var cueNotConnectedDetail: String { s("Only this Mac got the cue.", "この Mac だけにキューが出ました") }
    var receivedFromMain: String { s("Received from the main Mac", "メインから受け取りました") }
    func cueAccessibility(_ label: String, _ memo: String, _ status: String) -> String {
        s("Last cue \(label) \(memo). \(status)", "直前のキュー \(label) \(memo)。\(status)")
    }

    // MARK: Mode section
    var cueKeysTitle: String { s("Cue keys", "キューのキー") }
    var cueKeysNone: String { s("No cue keys. Add them in Settings.", "キューのキーがありません。設定で追加できます。") }
    var cueKeysChange: String { s("Change in Settings (⌘,)", "設定（⌘,）で変更") }
    var cueKeysPassThrough: String {
        s("Cue keys also reach other apps: Live on this Mac may react twice. Allow Accessibility to stop this.",
          "キューのキーがほかのアプリにも届いています。この Mac の Live が2回動くおそれがあります。「アクセシビリティ」を許可すると防げます。")
    }
    var openAccessibilitySettings: String { s("Open Accessibility Settings…", "アクセシビリティの設定を開く…") }
    var accessibilityAllowed: String { s("Accessibility: Allowed", "アクセシビリティ: 許可済み") }
    var accessibilityNotAllowed: String { s("Accessibility: Not allowed", "アクセシビリティ: 未許可") }

    // MARK: Settings: cue keys
    var cueKeysSection: String { s("Cue Keys", "キューのキー") }
    var cueKeyColumn: String { s("Key", "キー") }
    var cueMemoColumn: String { s("Memo (your own name)", "メモ（自分用の名前）") }
    var cueMidiColumn: String { s("MIDI", "MIDI") }
    var addCueKey: String { s("Add Key…", "キーを追加…") }
    var addCueKeyHint: String { s("Click Add, then press the key to add.", "追加を押して、登録したいキーを押します") }
    func removeCueKey(_ label: String) -> String { s("Remove \(label)", "\(label) を削除") }
    func memoFor(_ label: String) -> String { s("Memo for \(label)", "\(label) のメモ") }
    var memoPlaceholder: String { s("e.g. Next scene", "例：次のシーン") }
    var blockCueKeys: String { s("Keep cue keys from other apps (recommended)", "キューのキーを、ほかのアプリに渡さない（おすすめ）") }
    var blockCueKeysHelp: String {
        s("Stops Live on the main Mac from also reacting to the arrows or Space, which would move it twice. Needs the Accessibility permission. Turn key capture off to use the keys normally.",
          "メインの Live が矢印キーやスペースにも反応して、2回動くのを防ぎます。「アクセシビリティ」の許可が必要です。キー入力をオフにすると、ふだんどおり使えます。")
    }
    var pianoKeys: String { s("Also use the piano layout (A…; for notes, Z/X for octave)", "ピアノ配列のキーも使う（A〜; で音階、Z/X でオクターブ）") }
    var pianoKeysHelp: String {
        s("For playing instruments. Leave it off for cues, so a wrong key cannot change the notes.",
          "楽器を鳴らすとき用です。キュー出しではオフにしておくと、押し間違いで音が変わりません。")
    }
    var cueKeysFull: String { s("No free notes left.", "割り当てられるノートがもうありません。") }

    // MARK: Add key sheet
    var addKeyTitle: String { s("Add Key", "キーを追加") }
    var pressKeyToAdd: String { s("Press the key to add", "登録したいキーを押してください") }
    var pressKeyHint: String { s("Arrows, Space, Return, digits, F1–F12 and so on. Keys with ⌘ ⌃ ⌥ ⇧ are not used.", "矢印・スペース・リターン・数字・F1〜F12 などが使えます。⌘ ⌃ ⌥ ⇧ と一緒に押すキーは使いません") }
    func keyAlreadyUsed(_ label: String) -> String { s("\(label) is already a cue key.", "\(label) はもう登録されています。") }

    // MARK: Updates
    var updatesSection: String { s("Updates", "アップデート") }
    var autoUpdate: String { s("Check for new versions and download them automatically", "新しいバージョンを自動で確認してダウンロードする") }
    var autoUpdateHelp: String {
        s("Checked a minute after launch and every 6 hours. The app is replaced only when TwinKeys quits.",
          "起動の1分後と6時間ごとに確認します。入れ替えは TwinKeys を終了したときだけです。")
    }
    func currentVersion(_ v: String) -> String { s("Current version: \(v)", "今のバージョン: \(v)") }
    var checkNow: String { s("Check Now", "今すぐ確認") }
    var checkForUpdates: String { s("Check for Updates…", "アップデートを確認…") }
    var updateChecking: String { s("Checking…", "確認しています…") }
    var updateUpToDate: String { s("You have the latest version.", "最新です。") }
    var updateFailed: String { s("Could not check for updates. Check the network and try again.", "アップデートを確認できませんでした。ネットワークを確かめて、もう一度お試しください。") }
    func updateDownloading(_ v: String) -> String { s("Downloading TwinKeys \(v)…", "TwinKeys \(v) をダウンロードしています…") }
    func updateReady(_ v: String) -> String { s("TwinKeys \(v) is ready", "TwinKeys \(v) の準備ができました") }
    var updateReadyDetail: String { s("It is installed when TwinKeys quits. Never during a show.", "TwinKeys を終了したときに入れ替わります。本番中には入れ替えません。") }
    var restartNow: String { s("Restart Now", "いま再起動") }
    var restartNowHelp: String { s("Shown only while not connected", "接続していないときだけ使えます") }
    func updateManual(_ v: String) -> String { s("TwinKeys \(v) is available", "TwinKeys \(v) が出ています") }
    func updateManualDetail(_ r: UpdateState.ManualReason) -> String {
        switch r {
        case .notWritable: return s("TwinKeys cannot replace itself in this folder. Download it from the release page.", "このフォルダでは自動で入れ替えられません。リリースのページからダウンロードしてください。")
        case .notSigned: return s("This copy of TwinKeys is not signed, so it is not replaced automatically.", "この TwinKeys は署名がないため、自動では入れ替えません。")
        case .translocated: return s("Move TwinKeys to the Applications folder to update automatically.", "自動で入れ替えるには、TwinKeys を「アプリケーション」フォルダに移してください。")
        }
    }
    var openReleasePage: String { s("Open Release Page", "リリースのページを開く") }

    // MARK: Menu bar and login
    var menuBarSection: String { s("Menu Bar", "メニューバー") }
    var openTwinKeys: String { s("Open TwinKeys", "TwinKeys を開く") }
    var settingsMenu: String { s("Settings…", "設定…") }
    var launchAtLogin: String { s("Open at Login", "ログイン時に起動") }
    var launchAtLoginHelp: String { s("Handy on the backup Mac.", "バックアップの Mac で便利です。") }
    var menuBarOnly: String { s("Show only in the menu bar (no Dock icon)", "メニューバーだけに表示する（Dock に出さない）") }
    var quitTwinKeys: String { s("Quit TwinKeys", "TwinKeys を終了") }
    var reconnecting: String { s("Reconnecting…", "再接続中…") }
}
#endif
