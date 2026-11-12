#if os(macOS)
import Foundation
import TwinKeysCore

/// Text for the console (Yamaha) takeover (2.4, experimental; docs/design-v2.4-ql.md).
extension Strings {
    // MARK: Settings > Console (Yamaha)
    var deskSection: String { s("Console (Yamaha)", "卓（Yamaha）") }
    var deskSubtitle: String {
        s("Used on the backup Mac only (when the main Mac stops, the Mac still running moves the console).",
          "バックアップの Mac でだけ使います（メインが止まったとき、生きている側が卓を動かすため）")
    }
    var deskModel: String { s("Console model", "卓の機種") }
    var deskAddress: String { s("Console IP address", "卓の IP アドレス") }
    var deskCheck: String { s("Check Connection", "接続を確かめる") }
    var deskPortNote: String {
        s("(TCP 49280. The console’s “For Mixer Control” IP address)", "（TCP 49280。卓の「For Mixer Control」の IP アドレス）")
    }
    func deskReadUnverified(_ model: String) -> String {
        s("Whether \(model) can read levels has not been checked yet. If it cannot, the backup channels go to the set levels.",
          "\(model) で高さを読めるかは、まだ確かめていません。読めないときは決めた高さに上げます。")
    }

    // Status line
    var deskStatusOff: String { s("Off (turn on the experimental feature below)", "オフ（下の「試験的な機能」をオンにすると使えます）") }
    var deskStatusNoAddress: String { s("Enter the console’s IP address", "卓の IP アドレスを入れてください") }
    var deskStatusBadAddress: String { s("Not a valid IP address (for example 192.168.0.128)", "IP アドレスの形が違います（例：192.168.0.128）") }
    var deskStatusNotBackup: String {
        s("Connects only on the backup Mac (this Mac sends the keys)", "バックアップの Mac でだけつなぎます（この Mac はキーを送っています）")
    }
    func deskStatusConnecting(_ m: String) -> String { s("Connecting to \(m)…", "\(m) に接続中…") }
    var deskStatusChecking: String { s("Connected · checking whether levels can be read…", "接続済み ・ 高さを読めるか確かめています…") }
    func deskStatusReading(_ m: String) -> String { s("Connected to \(m) · Reading fader levels", "\(m) に接続済み ・ フェーダーの高さを読めています") }
    func deskStatusStale(_ m: String) -> String { s("Connected to \(m) · Levels are not updating", "\(m) に接続済み ・ 高さが更新されていません") }
    var deskStatusFixed: String { s("Levels cannot be read: raises to the set levels", "高さは読めません：決めた高さに上げます") }
    var deskStatusFixedUnconfirmed: String {
        s("(Sent over OSC, UDP 49900. Whether it arrives cannot be checked)", "（OSC、UDP 49900 で送ります。届いたかは確かめられません）")
    }
    var deskStatusCannotRead: String {
        s("Levels cannot be read: the console is not moved (“Raise to set levels” is off)",
          "高さは読めません：卓は動かしません（「決めた高さに上げる」がオフ）")
    }
    func deskStatusNotReachable(_ m: String) -> String {
        s("Cannot reach \(m). Check the IP address and the console’s network settings.",
          "\(m) に届きません。IP アドレスと、卓のネットワークの設定を確かめてください")
    }
    var deskStatusQLNoOther: String {
        s("QL has no other way in: while it cannot be reached, the console cannot be moved.",
          "QL はほかの方法では動かせないため、届かないあいだは卓を動かせません")
    }

    // Channel table
    var deskMapping: String { s("Channel assignment", "チャンネルの割り当て") }
    var deskColumnKind: String { s("Type", "種類") }
    var deskColumnMain: String { s("Main", "メイン") }
    var deskColumnBackup: String { s("Backup (this Mac)", "バックアップ（この Mac）") }
    var deskColumnLevel: String { s("Level now", "いまの高さ") }
    var deskColumnFixed: String { s("Set level", "決めた高さ") }
    var deskKindInput: String { s("Input", "入力") }
    var deskKindStereo: String { "ST IN" }
    var deskNamePlaceholder: String { s("Name", "名前") }
    var deskAddRow: String { s("+ Add Row", "＋ 行を足す") }
    var deskRowHint: String {
        s("Numbers as on the console (from 1). Numbers above the model’s limit cannot be entered.",
          "番号は卓の画面と同じ（1 から）。機種ごとの上限を超える番号は入れられません")
    }
    var deskRemoveRow: String { s("Remove row", "行を消す") }
    func deskMainChannel(_ row: Int) -> String { s("Main channel, row \(row)", "\(row) 行目のメインのチャンネル") }
    func deskBackupChannel(_ row: Int) -> String { s("Backup channel, row \(row)", "\(row) 行目のバックアップのチャンネル") }
    func deskFixedLevelFor(_ row: Int) -> String { s("Set level in dB, row \(row)", "\(row) 行目の決めた高さ（dB）") }
    func deskChannel(_ c: DeskChannel) -> String {
        c.kind == .input ? "Ch \(c.number)" : "ST IN \(c.number)"
    }
    func deskProblem(_ p: DeskRowProblem, model: String) -> String {
        switch p {
        case let .channelOutOfRange(row, ch, limit):
            return limit == 0 ? s("Row \(row): \(model) has no \(deskChannel(ch))", "\(row) 行目：\(model) に \(deskChannel(ch)) はありません")
                : s("Row \(row): \(deskChannel(ch)) is outside \(model)’s 1–\(limit)", "\(row) 行目：\(deskChannel(ch)) は \(model) の 1–\(limit) の外です")
        case let .noStereoIn(row): return s("Row \(row): \(model) has no ST IN", "\(row) 行目：\(model) に ST IN はありません")
        case let .sameChannel(row): return s("Row \(row): main and backup are the same channel", "\(row) 行目：メインとバックアップが同じチャンネルです")
        case let .usedTwice(ch): return s("\(deskChannel(ch)) is used in more than one row", "\(deskChannel(ch)) が複数の行で使われています")
        case let .fixedLevelMinusInfinity(row): return s("Row \(row): the set level is −∞", "\(row) 行目：決めた高さが −∞ です")
        }
    }

    // When levels cannot be read
    var deskUnreadableTitle: String { s("When levels cannot be read", "高さを読めないとき") }
    var deskUnreadableLead: String {
        s("On models not checked yet, such as DM5, when levels could not be read:", "DM5 など、まだ確かめていない機種で高さを読めなかったときは：")
    }
    var deskUseFixed: String { s("Raise to set levels (entered per row; 0 dB to begin with)", "決めた高さに上げる（行ごとに入れる。初期値 0 dB）") }
    var deskUseFixedNote: String {
        s("When levels cannot be read, the connection line says in yellow “Levels cannot be read: raises to the set levels”",
          "読めないときは、接続の行に黄色で「高さは読めません：決めた高さに上げます」")
    }

    // When switching
    var deskWhenSwitching: String { s("When switching", "切り替えるとき") }
    var deskTriggerConfirm: String { s("After confirming (recommended)", "確認してから（おすすめ）") }
    var deskTriggerConfirmDetail: String {
        s("Switches the console together with “Make This Mac the Main”", "「この Mac をメインにする」と一緒に、卓も切り替える")
    }
    var deskTriggerAuto: String { s("Automatically (when the main Mac has not answered for 3 s)", "自動（メインが 3 秒応答しないとき）") }
    var deskTriggerAutoDetail: String { s("May also move when the network drops for a moment", "回線が一瞬切れただけでも動くおそれがあります") }
    var deskAutoAlertTitle: String { s("Switch the console automatically?", "卓を自動で切り替えますか？") }
    var deskAutoAlertMessage: String {
        s("When the main Mac has not answered for 3 seconds, TwinKeys moves the console’s faders without asking. It may also move when the network drops for a moment.\n\nIt never moves the console when it is not connected or the levels read are old. The Macs themselves still switch only with “Make This Mac the Main” (or from an iPhone).",
          "メインの Mac が 3 秒応答しないと、確かめずに卓のフェーダーを動かします。回線が一瞬切れただけでも動くおそれがあります。\n\n卓とつながっていない・読んだ高さが古いときは動かしません。Mac の切り替えは、今までどおり「この Mac をメインにする」（または iPhone）で行います。")
    }
    var deskAutoAlertConfirm: String { s("Switch Automatically", "自動にする") }

    // Fade
    var deskFade: String { s("Fade time", "フェード時間") }
    func deskFadeText(_ seconds: Double) -> String {
        if seconds <= 0 { return s("Instant", "すぐ") }
        let n = seconds == seconds.rounded() ? "\(Int(seconds))" : "\(seconds)"
        return s("\(n) s", "\(n) 秒")
    }
    var deskPullMain: String { s("Pull the main channels to −∞ (channel ON is not touched)", "メインの Ch は −∞ まで下げる（チャンネルの ON はさわらない）") }
    var deskExperimental: String {
        s("Turn on the experimental feature (off until checked on a real console)", "試験的な機能をオンにする（実機で確かめるまで、初期状態はオフ）")
    }
    var deskOnlyFaders: String {
        s("Only fader levels are moved. EQ, dynamics, routing and scenes are never touched.",
          "動かすのはフェーダーの高さだけ。EQ・ダイナミクス・ルーティング・シーンにはさわりません。")
    }

    // MARK: "Make this Mac the main" confirmation
    func deskConfirmCheckbox(_ model: String, rows: Int, fade: Double) -> String {
        s("Also switch the console’s faders (\(model): \(rows) row\(rows == 1 ? "" : "s"), \(deskFadeText(fade)))",
          "卓（\(model)）のフェーダーも切り替える（\(rows) 行、\(deskFadeText(fade))）")
    }
    func deskCannotMove(_ why: DeskNotReady) -> String {
        s("The console cannot be moved (\(deskReason(why))). Only the Mac switches.",
          "卓は動かせません（\(deskReason(why))）。Mac だけ切り替えます。")
    }
    func deskReason(_ r: DeskNotReady) -> String {
        switch r {
        case .off: return s("the feature is off", "機能がオフです")
        case .noRows: return s("no channels assigned", "チャンネルの割り当てがありません")
        case .invalidRows: return s("the channel assignment has a problem", "チャンネルの割り当てに問題があります")
        case .busy: return s("the faders are moving", "フェーダーを動かしています")
        case .alreadyMoved: return s("already switched", "もう切り替えてあります")
        case .nothingToRestore: return s("nothing to restore", "元に戻すものがありません")
        case .notConnected: return s("not connected", "つながっていません")
        case .checking: return s("still checking the connection", "接続を確かめています")
        case .stale: return s("the levels read are old", "読んだ高さが古くなっています")
        case .unreadable: return s("levels cannot be read and “Raise to set levels” is off", "高さを読めず、「決めた高さに上げる」がオフです")
        }
    }

    // MARK: Window banner
    func deskSwitching(_ fade: Double) -> String { s("Switching the console… (\(deskFadeText(fade)))", "卓を切り替えています…（\(deskFadeText(fade))）") }
    func deskSwitched(_ fade: Double) -> String { s("Console switched (\(deskFadeText(fade)))", "卓を切り替えました（\(deskFadeText(fade))）") }
    var deskRestoring: String { s("Restoring the console…", "卓を元に戻しています…") }
    func deskRestored(_ fade: Double) -> String { s("Console restored (\(deskFadeText(fade)))", "卓を元に戻しました（\(deskFadeText(fade))）") }
    var deskRestore: String { s("Restore the Console", "卓を元に戻す") }
    var deskHide: String { s("Hide", "閉じる") }
    var deskFixedUsed: String { s("Levels could not be read: the backup channels went to the set levels.", "高さを読めなかったので、バックアップの Ch は決めた高さにしました。") }
    var deskCheckWaiting: String { s("Reading the levels back from the console…", "卓から読み直して確かめています…") }
    var deskCheckOK: String { s("Read back from the console: every level is as planned.", "卓から読み直しました：思った高さになっています。") }
    var deskCheckNotPossible: String { s("Levels cannot be read, so whether the faders moved was not checked.", "高さを読めないため、動いたかは確かめていません。") }
    var deskCheckInterrupted: String {
        s("The connection to the console dropped before the move finished. Check the faders on the console.",
          "動かし終わる前に卓との接続が切れました。卓のフェーダーを確かめてください。")
    }
    func deskMismatch(_ m: DeskMismatch) -> String {
        let ch = deskChannel(m.channel), want = DeskLevel.text(m.expected)
        switch m.problem {
        case let .level(v): return s("\(ch): should be \(want), the console shows \(DeskLevel.text(v))", "\(ch)：\(want) のはずが \(DeskLevel.text(v))")
        case .refused: return s("\(ch): the console refused \(want)", "\(ch)：卓が \(want) を受け付けませんでした")
        case .noAnswer: return s("\(ch): no answer when reading back", "\(ch)：読み直しに答えがありません")
        }
    }
    func deskRefused(_ r: DeskRefusal) -> String {
        if r.restore { return s("The console was not restored: \(deskReason(r.reason))", "卓を元に戻せませんでした：\(deskReason(r.reason))") }
        let what = r.automatic ? s("The console was not switched automatically", "卓は自動で切り替えませんでした")
            : s("The console was not switched", "卓は切り替えませんでした")
        return "\(what)\(s(": ", "："))\(deskReason(r.reason))"
    }
    var deskRestoreTitle: String { s("Restore the console?", "卓を元に戻しますか？") }
    func deskRestoreMessage(_ fade: Double) -> String {
        s("The backup channels go back to their levels before the switch, and the main channels to theirs (\(deskFadeText(fade))).",
          "バックアップの Ch を切り替える前の高さに、メインの Ch を元の高さに戻します（\(deskFadeText(fade))）。")
    }
    var deskRestoreConfirm: String { s("Restore", "元に戻す") }

    // MARK: Connection row
    func deskChipTitle(_ model: String, connected: Bool) -> String {
        s("Console \(model)", "卓 \(model)") + (connected ? " ✓" : "")
    }
    var deskChipReading: String { s("Reading levels", "高さを読めています") }
    var deskChipFixed: String { s("Raises to set levels", "決めた高さに上げます") }
    var deskChipNotConnected: String { s("Not connected", "つながっていません") }
    var deskChipStale: String { s("Levels not updating", "高さが更新されていません") }
    var deskChipChecking: String { s("Checking…", "確かめています…") }
    var deskChipCannotMove: String { s("Cannot be moved", "動かせません") }
}
#endif
