# App Store の文面（英語）— TwinKeys Remote 1.2.1

App Store Connect の「English (U.S.)」のページに貼る文面です。灰色の枠の中身を、そのままコピーして貼ってください。上限の出典、カテゴリ、年齢制限の答えは [metadata-ja.md](metadata-ja.md) と同じです（カテゴリと年齢制限はアプリ全体で1つ）。

**自動で入れるとき：** GitHub Actions の「appstore-prepare」は [listing.json](listing.json) の文面を入れます。文面を直すときは、このファイルと listing.json の両方を直してください。

- 価格：**1,000円（有料のアプリ。基準の国は日本、ほかの国は Apple が自動で決める）**。アプリ内課金はありません。説明の文には「無料」と書きません（無料なのは Mac の TwinKeys です。iPhone アプリはソースコードを公開していますが、App Store では有料です）。
- 文字数は、この文面を作ったあとにプログラムで数えた数です。キーワードだけは「バイト」で数えます（英数字とカンマは1文字1バイト）。
- 英語のページを「主な言語（Primary Language）」にすると、日本語・英語以外の国でもこの英語の文面が出ます（おすすめ）。

## 上限（Apple の公式ページで確かめたもの、2026年11月12日）

- 名前 2〜30文字、サブタイトル 30文字：[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- プロモーション用テキスト 170文字、説明 4000文字、キーワード 100バイト（1語3文字以上）、新機能 4000文字、App Review へのメモ 4000バイト：[Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- メタデータに商標を詰め込まない、サブタイトルでほかのアプリにふれない：[App Review Guidelines 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)

## 1. 名前（App Name）

上限 30文字 ・ 今の文字数 **15**

```text
TwinKeys Remote
```

## 2. サブタイトル（Subtitle）

上限 30文字 ・ 今の文字数 **28**

```text
Show cue remote for two Macs
```

日本語の意味：「2台の Mac のための、本番のキュー用リモコン」。

## 3. プロモーション用テキスト（Promotional Text）

上限 170文字 ・ 今の文字数 **146**

```text
Fire clips, scenes and cues in Ableton Live on a main and a backup Mac at once. New: GO runs your show from Live's scene list with one big button.
```

## 4. 説明（Description）

上限 4000文字 ・ 今の文字数 **2668**

```text
TwinKeys Remote is a remote control for sound operators who run a show on two Macs: a main Mac and a backup Mac, both playing the same Ableton Live set. Every tap on your iPhone or iPad reaches Live on both Macs at the same time, so the backup is always ready to take over.

TwinKeys Remote works together with TwinKeys, a free Mac app (macOS 13 or later). Install TwinKeys on both Macs first. Without it, TwinKeys Remote cannot do anything.

SCREENS
• Session: the clip grid. Tap a clip to launch it, tap an empty slot to stop that track, or launch a whole scene. Playing clips show the time left.
• Mixer: volume, pan, mute, solo, and Send A / Send B. Drag anywhere in a column. A dashed line marks 0 dB.
• Cues: the same cue keys as on the main Mac, each showing what it does (the memo written on the Mac), plus the last cue and whether it reached the backup.
• GO: Live's scene list becomes your script. The big GO launches the selected scene on both Macs and moves on. Back and Next only choose; they never play.
• Settings: show safety options and the connection.
• Apple Watch: GO, choose scene and All Notes Off, through the iPhone.

MADE FOR THE SHOW
• Top bar: link status, delay to the backup, play, stop, tempo, position and All Notes Off.
• Show lock: freezes tempo and the mixer. You can also lock launches, stops and cues. GO and All Notes Off are never locked.
• Stop and Stop all clips need a long press.
• Faders can be kept at 0 dB or below.
• A warning appears when the backup Mac has a different set open.
• If the main Mac stops, switch to the backup Mac from the iPhone (hold 1 second to confirm).
• Landscape first on iPhone. On iPad the screens spread into two or three columns.

SAFE CONNECTION
• Works only on your local network. No internet connection and no account needed.
• Your iPhone needs the same pairing code as your Macs, and you allow it once on the Mac after checking a 4-digit code.
• All traffic is encrypted.

WHAT YOU NEED
• Two Macs with TwinKeys 2.2 or later (free)
• Ableton Live 11 or 12 on both Macs, with the TwinKeysBridge control surface (TwinKeys installs it for you)
• An iPhone or iPad with iOS 17 or later, on the same network as the Macs; watchOS 10 or later for the Apple Watch

No Mac yet? Tap "Try with sample data" on the first screen to try the screens with made-up data.

PRIVACY
TwinKeys Remote collects no data. No accounts, no analytics, no ads, no in-app purchases.

TwinKeys Remote is made by Shogo Kajiyama / SEVENTHWELL. Its source code is open on GitHub (MIT License).

TwinKeys is an unofficial tool. It is not made, endorsed or supported by Ableton. Ableton and Live are trademarks of Ableton AG.
```

## 5. キーワード（Keywords）

上限 100バイト ・ 今のバイト数 **97**

```text
cue,show,theater,theatre,sound,playback,backup,clip,scene,mixer,stage,concert,operator,midi,tempo
```

- カンマで区切り、スペースは入れません。
- 「TwinKeys」「Remote」（名前に入っている）、「Ableton」「Live」（ほかの会社・アプリの名前）は入れていません。
- どの語も3文字以上です。

## 6. サポート URL（Support URL）

```text
https://kajisho5.github.io/ableton-twinkeys/support/
```

## 7. マーケティング URL（Marketing URL、なくてもよい）

```text
https://kajisho5.github.io/ableton-twinkeys/
```

## 8. プライバシーポリシー URL（Privacy Policy URL）

```text
https://kajisho5.github.io/ableton-twinkeys/privacy/
```

## 9. 著作権（Copyright）

```text
2026 Shogo Kajiyama / SEVENTHWELL
```

## 10. このバージョンの新機能（What's New。1.2.0 の変更を書いた文面）

上限 4000文字 ・ 今の文字数 **436**

```text
• Apple Watch app: GO, choose scene and All Notes Off.
• If the main Mac stops, switch to the backup Mac from the iPhone.
• The backup Mac confirms each action also ran in its Live, and you are told when it did not.
• Choose what the show lock stops. GO and All Notes Off are never stopped.
• "Try with sample data" lets you try the screens without a Mac.
• Privacy policy and support links in Settings.
Needs TwinKeys 2.2 on both Macs.
```

**大事：** App Store で最初に出すバージョンには、この欄が出ません。今回がはじめてなら、次のバージョンのときに使ってください。自動で入れるとき（appstore-prepare）は、前のバージョンがないとこの欄を送りません。
