#if os(macOS)
import Foundation
import TwinKeysCore

/// Text for QLab mode (docs/design-qlab.md 4.1, 10; docs/design/qlab-mac-settings.png).
extension Strings {
    var qlabSection: String { "QLab" }
    var qlabSubtitle: String {
        s("Each Mac sends OSC to its own QLab (on this Mac only, TCP 53000).",
          "両方の Mac が、それぞれ自分の QLab に OSC で命令します（この Mac の中だけ、TCP 53000）")
    }
    var qlabTargetTitle: String { s("TwinKeys drives", "TwinKeys が動かすもの") }
    func qlabTargetName(_ t: QLabTarget) -> String {
        switch t {
        case .live: return "Ableton Live"
        case .qlab: return "QLab"
        case .both: return s("Both", "両方")
        }
    }
    var qlabTargetHelp: String { s("“Both”: to Live and to QLab. Set the same on both Macs.", "「両方」：Live と QLab の両方へ。2台で同じにしてください") }
    var qlabThisMac: String { s("This Mac’s QLab", "この Mac の QLab") }
    var qlabWorkspace: String { s("Workspace", "ワークスペース") }
    var qlabChooseWorkspace: String { s("Choose…", "選んでください") }
    var qlabPasscode: String { s("Passcode (4 digits)", "パスコード（4桁）") }
    var qlabPasscodeSave: String { s("Save", "保存") }
    var qlabPasscodeChange: String { s("Change…", "変更…") }
    var qlabPermissions: String { s("Permissions", "使える権限") }
    var qlabPermView: String { s("View", "見る") }
    var qlabPermControl: String { s("Control", "操作") }
    var qlabPermEdit: String { s("Edit (not needed)", "編集（不要）") }
    var qlabPasscodeNote: String {
        s("The passcode is kept in this Mac’s keychain (never sent to the other Mac). Without the “control” permission TwinKeys cannot GO: add it in QLab’s Settings → Network → OSC Access.",
          "パスコードはこの Mac のキーチェーンに保存します（もう片方の Mac には送りません）。「操作（control）」の権限がないと GO できません。QLab の 設定 → Network → OSC Access で付けます。")
    }

    func qlabState(_ st: QLabEngineSnapshot, port: UInt16) -> String {
        let v = st.version.map { "QLab \($0)" } ?? "QLab"
        switch st.state {
        case .off: return s("Not used (Ableton Live mode)", "使っていません（Ableton Live のモード）")
        case .connecting: return s("QLab is not open (TCP \(port) does not answer)", "QLab が開いていません（TCP \(port) につながらない）")
        case .noAnswer: return s("QLab does not answer. Check that OSC Access is on.", "QLab が返事をしません。OSC Access がオンか確かめてください")
        case .noWorkspace: return s("QLab has no workspace open", "QLab にワークスペースがありません")
        case .choosingWorkspace: return s("Several workspaces are open: choose one", "ワークスペースが2つ以上開いています：使うものを選んでください")
        case .authorizing: return s("Connecting to \(st.workspace?.displayName ?? "QLab")…", "\(st.workspace?.displayName ?? "QLab") に接続中…")
        case .badPasscode: return s("Wrong passcode (QLab makes each wrong try wait longer)", "パスコードが違います（QLab は間違いが続くと待たせます）")
        case .needsPasscode: return s("Enter QLab’s passcode", "QLab のパスコードを入れてください")
        case .viewOnly: return s("Can show, but cannot GO: add “control” in QLab’s Settings → Network → OSC Access",
                                 "表示はできますが GO できません。QLab の 設定 → Network → OSC Access で「control」を付けてください")
        case .ready: return s("Connected to \(v) (TCP 127.0.0.1:\(port))", "\(v) に接続済み（TCP 127.0.0.1:\(port)）")
        case .stale: return s("\(v): no answer for 2 s, checking…", "\(v)：2 秒以上返事がありません。確かめています…")
        }
    }

    var qlabKeysTitle: String { s("Cue key → QLab action", "キューのキー → QLab の動き") }
    var qlabKeyColumn: String { s("Key", "キー") }
    var qlabActionColumn: String { s("QLab action", "QLab の動き") }
    var qlabDescColumn: String { s("What it does", "説明") }
    func qlabActionName(_ a: QLabAction?) -> String {
        switch a {
        case nil: return s("None", "なし")
        case .go?: return "GO"
        case .playheadNext?: return s("Next", "次へ")
        case .playheadPrevious?: return s("Previous", "前へ")
        case .panic?: return "Panic"
        case .hardStop?: return "Stop"
        case .goCue?: return s("GO cue number", "番号のキューを GO")
        case .setPlayhead?: return s("Playhead to cue", "番号のキューへ移す")
        case .pause?: return s("Pause all", "一時停止")
        case .resume?: return s("Resume all", "再開")
        }
    }
    func qlabActionDesc(_ k: QLabKeyAction?) -> String {
        switch k?.action ?? nil {
        case nil: return s("(Live only)", "（Live だけ）")
        case .go?: return s("GO the next cue (both Macs)", "次のキューを GO（2台）")
        case .playheadNext?: return s("Playhead one down", "再生位置を1つ下へ")
        case .playheadPrevious?: return s("Playhead one up", "再生位置を1つ上へ")
        case .panic?: return s("Panic on both (again: stop at once)", "2台とも Panic（もう一度で即停止）")
        case .hardStop?: return s("Stop everything at once (hardStop)", "すぐ全部止める（hardStop）")
        case .goCue?: return s("Move to cue \(k?.cue ?? "?") and GO", "キュー \(k?.cue ?? "?") へ移って GO")
        case .setPlayhead?: return s("Playhead to cue \(k?.cue ?? "?") (no GO)", "キュー \(k?.cue ?? "?") へ再生位置を移す（GO しない）")
        case .pause?: return s("Pause every cue", "全部を一時停止")
        case .resume?: return s("Resume every cue", "全部を再開")
        }
    }
    var qlabCueNumberPlaceholder: String { s("Cue no.", "番号") }

    var qlabSyncTitle: String { s("Keep the two Macs together", "2台をそろえる") }
    var qlabFollow: String { s("Move the backup’s playhead to the main’s (recommended)", "バックアップの再生位置をメインに合わせる（おすすめ）") }
    var qlabFollowHelp: String { s("Each time the main’s playhead moves, the backup’s QLab moves to the cue with the same number.", "メインで再生位置が動くたび、バックアップの QLab も同じ番号のキューへ") }
    var qlabRefuseStale: String { s("No GO when “next” differs from what the iPhone showed", "iPhone で見ていた「次」と違うときは GO しない") }
    var qlabRefuseStaleHelp: String { s("Prevents a surprise GO right after someone moved the playhead on the Mac.", "Mac の前で誰かが再生位置を動かした直後の、思わぬ GO を防ぎます") }
    var qlabNotes: String { s("Also send MIDI notes (QLab only mode)", "MIDI ノートも出す（QLab だけのとき）") }
    var qlabNotesHelp: String { s("If QLab’s Workspace MIDI is mapped to TwinKeys, cues then run twice.", "QLab の Workspace MIDI に TwinKeys を割り当てていると、2回動きます") }
    var qlabNumbersNote: String {
        s("The two Macs are matched by cue number. Cues without a number can only be reached with Next / Previous.",
          "キューの番号で2台を対応させます。番号のないキューは「次へ・前へ」だけで動かせます。")
    }

    // Two Macs
    var qlabTwoMacs: String { s("The two QLabs", "2台の QLab") }
    var qlabRowQLab: String { "QLab" }
    var qlabRowWorkspace: String { s("Workspace", "ワークスペース") }
    var qlabRowPermissions: String { s("Permissions", "権限") }
    var qlabRowCues: String { s("Cues", "キューの数") }
    var qlabRowPlayhead: String { s("Playhead", "再生位置") }
    var qlabRowRunning: String { s("Running cues", "動いているキュー") }
    var qlabRowShowMode: String { s("Show Mode", "本番モード") }
    var qlabOn: String { s("On", "オン") }
    var qlabOffWord: String { s("Off", "オフ") }
    var qlabSame: String { s("same", "同じ") }
    var qlabConnectedShort: String { s("connected", "接続済み") }
    var qlabNotConnectedShort: String { s("not connected", "未接続") }
    func qlabNotShowMode(_ mac: String) -> String { s("\(mac)’s QLab is not in Show Mode", "\(mac) の QLab が本番モード（Show Mode）ではありません") }
    var qlabPeerOld: String { s("The other Mac’s TwinKeys is older (or Windows): QLab runs on this Mac only.", "相手の TwinKeys が古い（または Windows の）ため、QLab はこの Mac だけ動きます") }
    var qlabPeerNotQLab: String { s("The other Mac does not drive QLab (its setting is Ableton Live).", "相手の Mac は QLab を動かしていません（設定が Ableton Live）") }
    func qlabCuesDiffer(_ a: Int, _ b: Int) -> String { s("The backup’s cues differ (\(a) and \(b))", "バックアップのキューが違います（\(a) と \(b)）") }
    var qlabTargetsDiffer: String { s("The two Macs drive different things or have different key actions", "2台で「動かすもの」かキューのキーの割り当てが違います") }

    // Main window
    var qlabPanelTitle: String { "QLab" }
    func qlabLastLine(_ l: QLabLastCommand) -> String {
        let what = l.action == .go ? "GO" : qlabActionName(l.action)
        return [what, l.number, l.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    func qlabBackupResult(_ b: String) -> String {
        switch b {
        case "delivered": return s("Backup ✓", "バックアップ ✓")
        case "corrected": return s("Backup ✓ (its playhead was corrected)", "バックアップ ✓（再生位置を直しました）")
        case "waiting": return s("Waiting for the backup…", "バックアップの返事を待っています…")
        case "missing": return s("No answer from the backup", "バックアップから返事がありません")
        case "noSuchCue": return s("The backup has no such cue (nothing played there)", "バックアップにそのキューがありません（鳴らしていません）")
        case "notConnected": return s("The backup’s QLab is not connected", "バックアップの QLab につながっていません")
        case "denied": return s("The backup’s QLab refused it (permissions)", "バックアップの QLab が受け付けません（権限）")
        case "badPasscode": return s("The backup’s QLab passcode is wrong", "バックアップの QLab のパスコードが違います")
        case "noAnswer": return s("The backup’s QLab did not answer", "バックアップの QLab から返事がありません")
        case "notLinked": return s("No backup linked", "バックアップ未接続")
        case "unsupported": return s("The backup’s TwinKeys cannot drive QLab", "バックアップの TwinKeys は QLab を動かせません")
        case "notSent": return s("Not sent", "送っていません")
        default: return b
        }
    }
    func qlabMainResult(_ m: String) -> String {
        switch m {
        case "delivered": return s("This Mac ✓", "この Mac ✓")
        case "waiting": return "…"
        case "qlab_next_changed": return s("Not sent: QLab’s next cue changed. Press again.", "送りませんでした：QLab の次のキューが変わりました。もう一度押してください")
        case "qlab_notConnected": return s("Not sent: this Mac’s QLab is not connected", "送りませんでした：この Mac の QLab につながっていません")
        case "qlab_double": return s("Second press ignored", "二度押しをまとめました")
        default: return s("This Mac’s QLab: \(m)", "この Mac の QLab：\(m)")
        }
    }
    var qlabLinkOK: String { "QLab ✓" }
    var qlabBackupLinkOK: String { s("Backup’s QLab ✓", "バックアップの QLab ✓") }
}
#endif
