# TwinKeys for Windows — release notes

Kept here, not in `release-notes/`, because that folder holds the Mac app's notes (the website and
the Mac release workflow read every file in it).

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
