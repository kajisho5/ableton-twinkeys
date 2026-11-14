# TwinKeys for Windows — release notes

Kept here, not in `release-notes/`, because that folder holds the Mac app's notes (the website and
the Mac release workflow read every file in it).

---
version: 0.3.0 (test version)
date: 2026-11-14
---

## 日本語

> **試験版です。まだ本物の Windows PC では試していません。**

### 新しくなったこと
- Microsoft Store に出せる形（MSIX）を作れるようにしました。Store 版は Store が署名と更新をします（SmartScreen の警告が出ません）。
- Store 版では、「サインイン時に起動」を Windows のスタートアップ タスクで行います（Store 版はレジストリの Run キーが使えないため）。
- プライバシーポリシーに Windows 版のこと（キーボードフック、保存する場所）を足しました。
- Mac 版 2.4.0 と組めます（Mac 版の QLab モードは Mac だけの機能です）。

### まだできないこと
- Store での公開（名前の予約とアップロードは、手順書 `docs/windows-store-submit.md` のとおり）。

## English

> **Test version, not yet tried on a real Windows PC.**

### New
- CI builds a Microsoft Store package (MSIX). The Store signs and updates it (no SmartScreen warning).
- In the Store version, "Start at sign-in" uses a Windows startup task (packaged apps cannot use the Run registry key).
- The privacy policy now covers TwinKeys for Windows (keyboard hook, where data is kept).
- Works with TwinKeys 2.4.0 for Mac (QLab mode is Mac only).

### Not yet
- Publishing in the Store (reserve the name and upload as in `docs/windows-store-submit.md`).

---
version: 0.2.0 (test version)
date: 2026-11-13
---

## 日本語

> **試験版です。まだ本物の Windows PC・Windows の Live・本物の iPhone では試していません。** ビルドとテストは GitHub Actions（Windows Server 2025、Windows 11 Arm64、Linux、macOS）だけで行っています。本番の前に必ず自分の PC・Live・iPhone で試してください。

### 新しくなったこと
- Live との連携（TwinKeysBridge）：「設定」>「Live」から Live のユーザーライブラリに組み込めます。ウインドウの下に Live の状態が出ます。
- バックアップの PC が、メイン（Mac でも PC でも）が iPhone から送った Live の操作を自分の Live で行い、届いたことと Live で動いたことを返します。これまでは Mac に「届いていない」と出ていました。
- 2台の Live のセット（トラックとシーンの名前）を見比べ、違うときはウインドウに出します。
- 「メインのコンピューターが止まったときは」の帯と「この PC をメインにする」「メインに戻す」。
- iPhone リモート（TwinKeys Remote）の受け口：「設定」>「iPhone リモート」でオンにすると、iPhone から Live を操作できます。端末ごとに一度、4桁の番号を確かめて許可します。
- Mac 版の TwinKeys も、Windows の相手を一覧で「Windows」と表示するようになります（Mac 版の次の版から）。

### まだできないこと
- キューのキーを MIDI を使わずに Live の操作へ結びつける方式（M3）。TwinKeysBridge の変更が要るので、Mac 版と一緒に入れます。
- Yamaha 卓の引き継ぎ、TwinKeys が自分で MIDI 入力を作る方式、Microsoft Store 版と自動アップデート。

## English

> **Test version, not yet tried on a real Windows PC, with Live on Windows, or with a real iPhone.** It is only built and tested by GitHub Actions (Windows Server 2025, Windows 11 Arm64, Linux, macOS). Try it with your own PC, Live and iPhone before any show.

### New
- The Live link (TwinKeysBridge): install it into Live's User Library from Settings > Live. The bottom of the window shows Live's status.
- A backup PC runs the Live actions the main (Mac or PC) forwards from the iPhone on its own Live, and reports that they arrived and ran. Before, the Mac showed them as not delivered.
- The two computers compare their Live sets (track and scene names) and the window warns when they differ.
- The "When the main computer has stopped" banner with Make This PC the Main, and Return to Main.
- The iPhone remote server (TwinKeys Remote): turn it on in Settings > iPhone Remote to control Live from an iPhone. Each device is allowed once, after checking its 4-digit code.
- The Mac version of TwinKeys labels a Windows peer "Windows" in its list (from the Mac's next version).

### Not yet
- Tying cue keys directly to Live actions without MIDI (M3). It needs a TwinKeysBridge change, which will come together with the Mac version.
- The Yamaha console takeover, TwinKeys creating its own MIDI input, a Microsoft Store version and automatic updates.

---
version: 0.1.0 (test version)
date: 2026-11-13
---

## 日本語

> **試験版です。まだ本物の Windows PC で試していません。** ビルドとテストは GitHub Actions（Windows Server 2025、Windows 11 Arm64、Linux、macOS）だけで行っています。本番の前に必ず自分の PC と Live で試してください。

### 新しくなったこと
- TwinKeys の Windows 版（Windows 11、x64 と ARM64）の最初の試験版です。署名なしの ZIP で配ります。
- Mac 版と同じ通信（合言葉、暗号化、届いた確認、回数、オールノートオフ、メインの切り替え）で動きます。Mac メイン＋Windows バックアップ、Windows メイン＋Mac バックアップ、Windows 2台のどれでもつながります。Mac 版は変えていません。
- キューのキーはキーの位置で判定します（JIS 配列と US 配列で同じ）。「キューのキーを、ほかのアプリに渡さない」は Windows では許可なしで使えます。
- Live へは、自分で作るループバック MIDI ポート「TwinKeys」（Windows MIDI Services または loopMIDI）に送ります。初回に準備の画面が出ます。
- 相手は mDNS で探し、見つからないときは IP アドレスで接続できます。
- 通知領域（タスクトレイ）のメニュー、Ctrl+Alt+K（キー入力）と Ctrl+Alt+P（オールノートオフ）はどのアプリが前でも効きます。
- 日本語と英語。設定は Windows のユーザーごとに保存し、合言葉は暗号化して別に保存します。

### まだできないこと
- Live との連携（TwinKeysBridge）、iPhone リモート、Yamaha 卓の引き継ぎ。
- TwinKeys が自分で MIDI 入力を作る方式（Windows MIDI Services の SDK 正式版を待っています）。
- Microsoft Store 版と自動アップデート。

## English

> **Test version, not yet tried on a real Windows PC.** It is only built and tested by GitHub Actions (Windows Server 2025, Windows 11 Arm64, Linux, macOS). Try it with your own PC and Live before any show.

### New
- The first test version of TwinKeys for Windows (Windows 11, x64 and ARM64), as an unsigned ZIP.
- Speaks the Mac version's protocol (pairing code, encryption, delivery check, cue count, All Notes Off, switching the main): a Mac main with a Windows backup, a Windows main with a Mac backup, or two PCs. The Mac version is unchanged.
- Cue keys are matched by key position (the same on JIS and US keyboards). "Keep cue keys from other apps" needs no permission on Windows.
- Cues go to a loopback MIDI port named "TwinKeys" that you create (Windows MIDI Services or loopMIDI). A setup screen opens the first time.
- Finds the other computer with mDNS, or connect by IP address.
- Notification-area (tray) menu; Ctrl+Alt+K (key capture) and Ctrl+Alt+P (All Notes Off) work whichever app is in front.
- Japanese and English. Settings are per Windows user; the pairing code is stored encrypted, separately.

### Not yet
- The Live link (TwinKeysBridge), the iPhone remote, the Yamaha console takeover.
- TwinKeys creating its own MIDI input (waiting for the final Windows MIDI Services SDK).
- A Microsoft Store version and automatic updates.
