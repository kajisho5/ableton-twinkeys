# リリースノートの下書き：QLab モード（docs/design-qlab.md）

`release-notes/` はサイトが読むので、版番号（`VERSION`）が決まるまでここに置きます。版を出すときに `release-notes/ja/<版>.md`・`release-notes/en/<版>.md` に写してください。

## 日本語

### 新しいこと

- **QLab モード**：Figure 53 の QLab 5 を、Live と同じように2台の Mac でそろえて動かせます。「設定」→「QLab」の「TwinKeys が動かすもの」で「QLab」か「両方」を選びます（初期値は今までどおり「Ableton Live」）。
  - 両方の Mac の TwinKeys が、それぞれ自分の QLab に OSC（この Mac の中だけ、TCP 53000）で命令します。
  - GO には「メインで待機していたキューの番号」が付き、バックアップの再生位置が違えば同じ番号のキューで GO します。バックアップにないキューは鳴らしません。
  - 届いたかの確認（0.3 秒で赤）、バックアップの再生位置をメインに合わせる、iPhone で見ていた「次」と違うときは GO しない。
  - キューのキーごとに QLab の動き（GO・次へ・前へ・Panic・Stop・番号のキューを GO）を選べます。
- **TwinKeys Remote**：QLab の GO 画面（今のキューと残り時間、次のキュー、バックアップも同じか）、キューの一覧（タップで2台の再生位置を移す）、PANIC（2台）。Apple Watch にも GO・一覧・PANIC。
- 手順書に「QLab を2台で動かす」を足しました（今の TwinKeys のまま、QLab の Workspace MIDI で動かす方法も）。

### 知っておいてほしいこと

- 本物の QLab・Mac・iPhone では、まだ確かめていません。本番の前にリハーサルで試してください。
- QLab モードは Mac 版だけです（QLab は Mac だけのアプリ）。Windows 版は QLab を動かしません。
- 両方の Mac に、この版の TwinKeys が要ります。

## English

### New

- **QLab mode**: keep Figure 53's QLab 5 on two Macs together, as for Live. In Settings → QLab, set "TwinKeys drives" to QLab or Both (the default stays Ableton Live).
  - Each Mac's TwinKeys sends OSC to its own QLab (on that Mac only, TCP 53000).
  - GO carries the number of the cue standing by on the main Mac; a backup standing by elsewhere GOes the same cue, and a cue the backup does not have is not played.
  - Delivery check (red after 0.3 s), the backup's playhead follows the main's, and no GO when "next" differs from what the iPhone showed.
  - Each cue key can have a QLab action (GO, Next, Previous, Panic, Stop, GO cue number).
- **TwinKeys Remote**: a QLab GO screen (running cue and time left, the next cue, whether the backup stands by on the same one), the cue list (a tap moves both playheads), PANIC (both). On the Apple Watch: GO, the list and PANIC.
- The help has "Running QLab on two Macs" (including driving QLab with today's cue keys through Workspace MIDI).

### Good to know

- Not yet tried with a real QLab, Mac and iPhone. Rehearse before a show.
- QLab mode is Mac only (QLab runs on macOS only). TwinKeys for Windows does not drive QLab.
- Both Macs need this version of TwinKeys.
