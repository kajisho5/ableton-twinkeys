# TwinKeys

TwinKeys fires sound cues on two Macs at once. Press a key on the main Mac and **both** the main Mac and the backup Mac receive the same MIDI note, so the same mapped clip launches in Live on both. It is meant for show playback where a backup Mac runs the same set side by side, ready to take over if the main Mac fails.

> **Unofficial third-party tool.** TwinKeys is not made, endorsed or supported by Ableton or by any other DAW maker. "Ableton" and "Live" are trademarks of Ableton AG and are used here only to describe compatibility.

- macOS 13 Ventura or later, Apple silicon and Intel (universal app)
- MIT License
- English and Japanese UI (Settings → Language: Same as System / English / 日本語)
- Made by **Shogo Kajiyama / SEVENTHWELL**

**Guide:** [Using TwinKeys (English)](docs/help/en.md) · [使い方（日本語）](docs/help/ja.md). The same guide opens inside the app from Help → TwinKeys Help (⌘?), even without an internet connection.

## How it works

- Each Mac runs TwinKeys. Each TwinKeys creates a virtual MIDI input called **TwinKeys**, so your music software sees it like a normal MIDI device. You do not need a forwarding track in your set.
- On the main Mac (**Send my keys**), TwinKeys watches the keyboard, turns presses of its **cue keys** (↑ ↓ ← → Space Return Esc to begin with; any key, letters and digits included, can be added) into fixed MIDI notes, plays them on its own TwinKeys port and sends them over the local network to the other Mac. Cue keys can be kept from other apps, so Live on the main Mac reacts only to TwinKeys' MIDI, just like the backup.
- The backup answers every cue. The main Mac shows the last cue, a count both Macs share, and whether the backup confirmed it (sent again for up to 0.3 s, then shown in red).
- On the backup Mac (**Receive notes**), TwinKeys plays the notes it receives on its own TwinKeys port.
- Tempo and bar position are **not** handled by TwinKeys. Use Ableton Link (built into Live) for that.
- The two Macs find each other automatically with Bonjour (or by IP address). A small UDP protocol carries note on/off, heartbeats and All Notes Off, signed and encrypted with keys from a shared pairing code. Each note is sent twice; duplicates and out-of-order packets are dropped.

## Download and first launch

1. Download `TwinKeys-<version>.dmg` from the [Releases page](https://github.com/kajisho5/ableton-twinkeys/releases), open it and drag **TwinKeys** to **Applications**. The app is signed with a Developer ID and notarized by Apple, so it opens normally.
2. **Input Monitoring** (main Mac only, needed for key capture): click **Open System Settings…** in the TwinKeys window, turn on TwinKeys under **Privacy & Security → Input Monitoring**, then click **Check Again** (or reopen TwinKeys).
   **Accessibility** (main Mac only, to keep cue keys from other apps): turn on TwinKeys under **Privacy & Security → Accessibility**.
3. **Local Network** (both Macs, macOS 15 or later): when macOS asks whether TwinKeys may find devices on your local network, click **Allow**. If you clicked Don't Allow, turn it on in **System Settings → Privacy & Security → Local Network**.
4. **Firewall:** if macOS asks whether TwinKeys may accept incoming network connections, click **Allow**.

If the window shows **Local Network: Not allowed**, TwinKeys could not announce itself on the network: turn TwinKeys on in **System Settings → Privacy & Security → Local Network** and reopen it.

Releases up to 0.3.0 were not notarized. If you still have one of those, replace it with the current release.

## Pairing code (both Macs, once)

Only Macs with the same pairing code can connect, and their traffic is encrypted.

1. On one Mac, click **Set Up Pairing Code…** (or Settings → Pairing Code) and then **Make New Code**. A 10-character code such as `K7MQ2-WX9TP` appears.
2. On the other Mac, click **Enter Code…** and type the same code. Case and hyphens do not matter.
3. The code is stored in the keychain, so you do this only once. A Mac with a different code is shown as **Different pairing code** and cannot connect.

If the other Mac is not listed (for example on a network that blocks Bonjour, or across subnets), use **Connect by IP Address…** (⇧⌘K) and type its IP address, shown on the other Mac under Settings → Pairing Code. TwinKeys listens on UDP port 47801.

## Setting up Live (both Macs)

Do this once per Mac, in Live 11 or Live 12:

1. Open **Settings** (Live 12) or **Preferences** (Live 11) and choose the **Link, Tempo & MIDI** tab (labelled **Link/Tempo/MIDI** in some versions).
2. If your set plays to tempo or bars, turn **Link** on, on both Macs, so tempo and bar position stay in sync.
3. In the MIDI ports list, find the input **TwinKeys** and turn on **Track** (to play instruments) and **Remote** (to trigger mapped controls such as clips or scenes).
4. Map your cues in **MIDI Map Mode** (⌘M): click a clip slot, scene up/down, launch selected scene, Play or Stop, press a cue key on the main Mac, and leave MIDI Map Mode. Use the same mapping on both Macs (the same Set file is the safest way). Remove the same keys from Live's Key Map Mode (⌘K).
5. Keep each clip's **Launch Mode** at **Trigger** (the default). Gate and Repeat stop the clip on key release, so they would also stop when TwinKeys turns notes off after a network drop.
6. On the main Mac, turn **off** Live's computer MIDI keyboard (shortcut M).

## Using TwinKeys

1. Open TwinKeys on both Macs on the same network (a wired network or a dedicated router is the most reliable).
2. On the main Mac, check **Send my keys**. On the backup Mac, check **Receive notes**. (Both can be on.)
3. In **Nearby TwinKeys**, click **Connect** next to the other Mac. The header shows **Connected to …** and the latency (heartbeat round trip).
4. Press cue keys. Each sends its own fixed note (MIDI channel 1, from C1 up, velocity 127). Add keys (one by one, or A–Z and 0–9 at once) and memos in **Settings → Cue Keys**. Keys are matched by physical position, so JIS and US keyboards behave the same.

**Updates:** TwinKeys downloads new versions in the background and replaces itself **only when it quits** (never during a show). **Restart Now** appears only while not connected. **Menu bar:** a keyboard icon shows the link (filled = connected) and has a menu; closing the window keeps TwinKeys running. Open at Login and menu-bar-only are in Settings.

If the network drops, TwinKeys keeps retrying (every 1 s, slowing to every 5 s) and reconnects by itself. Notes that came from the other Mac are turned off when the link drops; notes played on the main Mac's own keys keep sounding.

### Shortcuts

| Action | Shortcut |
|---|---|
| Connect / Disconnect | ⌘K (connects when only one other Mac is listed) |
| Key capture on / off | ⌃⌘K |
| All Notes Off (panic) | ⌃⌘P |
| Connect by IP Address | ⇧⌘K |
| TwinKeys Help | ⌘? |
| Settings | ⌘, |

Keys pressed together with ⌘, ⌃, ⌥ or ⇧ never play notes, so shortcuts in other apps stay silent. Turn **Key capture** off while typing in other apps.

### Safety

- **All Notes Off** (the red button) stops notes on this Mac and the connected Mac.
- All Notes Off is also sent when you quit TwinKeys or click Disconnect.
- A note that never receives its note-off is stopped automatically after 10 seconds (change in Settings, 0 turns it off). Notes whose keys are still held keep sounding. Notes received from the other Mac always wait at least 3 seconds.
- When the link drops, only notes that came from the other Mac stop; notes played on this Mac keep sounding.
- TwinKeys does **not** switch audio between Macs. Automatic audio failover needs dedicated hardware and is out of scope.

## Files

| What | Where |
|---|---|
| Settings | `~/Library/Application Support/TwinKeys/settings.json` |
| Logs | `~/Library/Logs/TwinKeys/TwinKeys-YYYY-MM-DD.log` |

Cue keys are stored in `settings.json` (`cue_keys`) with macOS virtual key codes (positions, not characters), for example `{ "keycode": 125, "label": "↓", "memo": "Next scene", "note": 37 }`.

## Constants you may want to change

| Constant | Value | Where |
|---|---|---|
| Bundle identifier | `io.github.kajisho5.twinkeys` | `Resources/Info.plist` |
| Bonjour service type | `_twinkeys._udp` | `Resources/Info.plist`, `Sources/TwinKeys/NetworkService.swift` |
| Virtual port name | `TwinKeys` | `Sources/TwinKeys/AppModel.swift` |
| Heartbeat / timeout / retry | 1 s / 3 s / 1–5 s | `Sources/TwinKeysCore/LinkStateMachine.swift` |
| Copies of each note packet | 2 | `Sources/TwinKeysCore/Conductor.swift` (`redundancy`) |
| Cue resend / give up | every 0.1 s / after 0.3 s | `Sources/TwinKeysCore/Conductor.swift` (`cueResendInterval`, `cueAnswerTimeout`) |
| Cue keys: channel / first note | 2 / C1 (36) | `Sources/TwinKeysCore/CueKeys.swift` |
| Update check | 1 min after launch, then every 6 h | `Sources/TwinKeysCore/Updates.swift` |
| Default auto note-off | 10 s | `Sources/TwinKeysCore/Settings.swift` |
| Default MIDI channel | 1 | `settings.json` (`midi_channel`) |
| UDP port | 47801 (falls back to any free port) | `Sources/TwinKeys/NetworkService.swift` (`fixedPort`) |
| Pairing key derivation | PBKDF2-HMAC-SHA256, 100 000 rounds | `Sources/TwinKeysCore/Pairing.swift` |
| App icon | made with fresnel | source: `design/icon/` (`twinkeys.spec.json`, `TwinKeys.icon`); built `.icns`: `Resources/AppIcon.icns` |

## Building from source

Requires macOS 13 or later with Xcode 16 or later (CI uses Xcode 26.6 on macOS 26).

```sh
swift test                      # unit tests
scripts/build-app.sh            # builds dist/TwinKeys.app (universal, ad-hoc signed) and a zip; version from VERSION
```

The platform-independent logic (`Sources/TwinKeysCore`) also builds and tests on Linux with Swift 6.

### Releases (GitHub Actions)

- Every push runs **CI** on a macOS runner: tests, universal build, launch and memory check, an end-to-end check (`scripts/e2e-midi.swift`: a fake second Mac sends notes over the network and they must come out of the TwinKeys MIDI port) and screenshots (downloadable from the run page).
- **Release:** signing with a Developer ID and Apple notarization are done by [kajisho5/runway](https://github.com/kajisho5/runway) (`mac-notarize.yml`); this repository is listed in runway's `repos.txt`, which gives it the signing secrets. Change the `VERSION` file (for example to `0.2.0`) on `main` (directly or by merging a pull request). GitHub Actions builds the app, signs and notarizes it, checks the .dmg on a clean Mac, creates the tag `v0.2.0` on that commit and publishes a release with `TwinKeys-0.2.0.dmg`. Versions with a suffix such as `1.0.0-beta.1` are marked as pre-releases; plain versions (1.0.0 and later) are full releases. Releases up to 0.5.0 were pre-releases. Pushing a `v*` tag that points at a commit on `main`, or running the workflow by hand with a version, also works; anything not on `main` is refused.

## Limitations

- One-to-one link (one main, one backup) in v1.
- TwinKeys cannot know whether your music software has the TwinKeys port turned on; it only knows the port exists.
- Key capture does not see keys typed while macOS Secure Input is on (most password fields, and Terminal with Secure Keyboard Entry). TwinKeys ends held notes when that starts.
- Security: hellos are signed with a key derived from the pairing code (PBKDF2-HMAC-SHA256, 100 000 rounds) and all other traffic is encrypted with ChaCha20-Poly1305 using per-launch keys (details: [docs/design-pairing.md](docs/design-pairing.md)). Anyone who learns the pairing code can connect: make a new code if it leaks.
- TwinKeys 0.5.0 and later cannot connect to 0.4.x (protocol version 2). Use the same version on both Macs.
- Wi-Fi adds variable delay that TwinKeys cannot control. Prefer a wired network.

## Credits

TwinKeys is made by **Shogo Kajiyama / SEVENTHWELL**. Released under the MIT License (see [LICENSE](LICENSE)). The app icon uses the letters "TK" from Inter (SIL Open Font License), converted to outlines.

## Roadmap

- RTP-MIDI (AppleMIDI) compatibility (v2 candidate)
- Planned v1.x additions: several backups at once, remote MIDI ports, named virtual ports and routing, presets, status of both Macs, watchdog alarm, event log.

Not planned: Windows, audio processing, automatic audio failover, setlist management.

---

## 日本語の概要

TwinKeys は、音響のキュー出しを2台の Mac で同時に行う Mac アプリです。メインの Mac でキーを叩くと、メインとバックアップの両方の Live に同じ MIDI ノートが届き、割り当てたクリップが2台で同時に再生されます。メインの Mac が止まっても、バックアップにすぐ切り替えられる構成向けです。制作は Shogo Kajiyama / SEVENTHWELL です。

> **非公式のサードパーティ製ツールです。** Ableton 社ほか DAW メーカーとは関係ありません。「Ableton」「Live」は Ableton AG の商標で、対応状況の説明のためにだけ記載しています。

**詳しい使い方：** [使い方（日本語）](docs/help/ja.md)。アプリの「ヘルプ」>「TwinKeysヘルプ」（⌘?）でも、ネットにつながっていなくても読めます。

### 入れ方

1. [リリースのページ](https://github.com/kajisho5/ableton-twinkeys/releases)から `TwinKeys-<バージョン>.dmg` をダウンロードして開き、TwinKeys を「アプリケーション」にドラッグします。Apple の公証を受けているので、そのまま開けます。
2. メインの Mac では、TwinKeys の画面にある「システム設定を開く…」から「入力監視」で TwinKeys をオンにし、「もう一度確認」をクリックします。
3. 両方の Mac で、ローカルネットワークの利用を確認されたら「許可」をクリックします（macOS 15 以降）。
4. ファイアウォールから受信接続を許可するか聞かれたら「許可」をクリックします。

0.3.0 までのバージョンは公証されていません。お使いの場合は、最新のバージョンに入れ替えてください。

画面の下に「ローカルネットワーク: 未許可」と出るときは、ほかの Mac から TwinKeys が見えていません。「システム設定」>「プライバシーとセキュリティ」>「ローカルネットワーク」で TwinKeys をオンにして、TwinKeys を開き直してください。

### 使い方の流れ

- 各 Mac に仮想 MIDI 入力「TwinKeys」ができます。Live の設定（「Link, Tempo & MIDI」）で TwinKeys の「トラック」と「リモート」をオンにするだけで使えます。転送用のトラックはいりません。
- キューを出すキーは「設定」の「キューのキー」で決めます（最初は ↑ ↓ ← → Space Return Esc）。英字・数字を含め、Mac のどのキーでも登録できます。キーごとに決まったノート（MIDI チャンネル 1、C1 から順、ベロシティ 127）を送ります。
- Live の MIDI 割り当てモード（⌘M）で、クリップ・シーンの上下・選んだシーンの再生・再生／停止などを、キューのキーに割り当てます。2台で同じ割り当てにしてください。クリップの起動モードは「トリガー」のままにしてください。
- メインの Mac では「アクセシビリティ」で TwinKeys をオンにします。キューのキーがほかのアプリ（Live を含む）に届かなくなり、メインの Live が2回動くのを防ぎます。
- 画面の「直前のキュー」に、押したキー・メモ・接続してからの回数と、バックアップに届いたか（✓／赤い「届いた確認がありません」）が出ます。
- 新しいバージョンは自動でダウンロードし、TwinKeys を終了したときだけ入れ替えます。本番中に入れ替えることはありません。
- メニューバーに鍵盤のアイコンが出ます。ウインドウを閉じても TwinKeys は動き続けます。
- テンポや小節に合わせて再生するセットでは、Ableton Link（Live に内蔵）で合わせてください。TwinKeys は扱いません。
- 最初に一度だけ、2台で同じ「合言葉」を設定します。片方の Mac で「合言葉を設定…」>「新しく作る」を押し、出てきた10文字（例 `K7MQ2-WX9TP`）を、もう片方の Mac の「合言葉を入力…」に入れます。合言葉が同じ Mac どうしだけがつながり、通信の中身も暗号化されます。
- メインの Mac で「キーを送信」、バックアップの Mac で「ノートを受信」にチェックを入れ、メインの Mac の一覧で相手の「接続」をクリックします。切れても自動でつなぎ直します。
- 一覧に相手が出ないときは「IPアドレスで接続…」（⇧⌘K）から、相手の IP アドレスを入れてつなげます。
- メインの Mac では、Live のコンピュータ MIDI キーボードをオフにしてください。
- 赤い「オールノートオフ」ボタン（⌃⌘P）で、両方の Mac の音をすべて止められます。
- 表示言語は「設定」（⌘,）の「言語」で、「システムに合わせる」「English」「日本語」から選べます。

### 注意

- 音声そのものの自動切り替え（オーディオフェイルオーバー）は対象外です。専用の機材が必要です。
- つなげるのは、同じ合言葉を設定した Mac だけです。合言葉が漏れたときは「新しく作る」で作り直してください。
- 0.5.0 からは 0.4.x 以前の TwinKeys とはつながりません。届いたかの確認は 1.0.0 どうしで使えます。2台とも同じバージョンにしてください。
- Wi-Fi は遅れが揺れやすいので、有線ネットワークをおすすめします。
