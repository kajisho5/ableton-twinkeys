# TwinKeys

TwinKeys plays the same MIDI notes on two Macs at once. Press keys on the main Mac and the music software on **both** the main Mac and the backup Mac receives the same notes. It is meant for live shows where a main and a backup Mac run the same set side by side.

> **Unofficial third-party tool.** TwinKeys is not made, endorsed or supported by Ableton or by any other DAW maker. "Ableton" and "Live" are trademarks of Ableton AG and are used here only to describe compatibility.

- macOS 13 Ventura or later, Apple silicon and Intel (universal app)
- MIT License
- English and Japanese UI (Settings → Language: Same as System / English / 日本語)
- Made by **Shogo Kajiyama / SEVENTHWELL**

## How it works

- Each Mac runs TwinKeys. Each TwinKeys creates a virtual MIDI input called **TwinKeys**, so your music software sees it like a normal MIDI device. You do not need a forwarding track in your set.
- On the main Mac (**Send my keys**), TwinKeys watches the keyboard, turns key presses into notes, plays them on its own TwinKeys port and sends them over the local network to the other Mac.
- On the backup Mac (**Receive notes**), TwinKeys plays the notes it receives on its own TwinKeys port.
- Tempo and bar position are **not** handled by TwinKeys. Use Ableton Link (built into Live) for that.
- The two Macs find each other automatically with Bonjour. A small UDP protocol carries note on/off, heartbeats and All Notes Off. Each note is sent twice; duplicates and out-of-order packets are dropped.

## Download and first launch

1. Download `TwinKeys-<version>-universal.zip` from the [Releases page](https://github.com/kajisho5/ableton-twinkeys/releases) and unzip it. Move **TwinKeys.app** to the Applications folder.
2. TwinKeys is **not notarized** (no paid Apple developer certificate). The first time:
   - **macOS 13 / 14:** Control-click (right-click) TwinKeys.app → **Open** → **Open**.
   - **macOS 15 or later:** double-click TwinKeys.app, click **Done** in the warning, then open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to the TwinKeys message and confirm with your password.
3. **Input Monitoring** (main Mac only, needed for key capture): click **Open System Settings…** in the TwinKeys window, turn on TwinKeys under **Privacy & Security → Input Monitoring**, then click **Check Again** (or reopen TwinKeys).
4. **Local Network** (both Macs, macOS 15 or later): when macOS asks whether TwinKeys may find devices on your local network, click **Allow**. If you clicked Don't Allow, turn it on in **System Settings → Privacy & Security → Local Network**.
5. **Firewall:** if macOS asks whether TwinKeys may accept incoming network connections, click **Allow**.

Note: because the app is signed ad hoc, macOS may ask for Input Monitoring again after you install a new version.

## Setting up Live (both Macs)

Do this once per Mac, in Live 11 or Live 12:

1. Open **Settings** (Live 12) or **Preferences** (Live 11) and choose the **Link, Tempo & MIDI** tab (labelled **Link/Tempo/MIDI** in some versions).
2. Turn **Link** on, on both Macs, so tempo and bar position stay in sync.
3. In the MIDI ports list, find the input **TwinKeys** and turn on **Track** (to play instruments) and **Remote** (to trigger mapped controls such as clips or scenes).
4. On the **main** Mac, turn **off** Live's own computer MIDI keyboard (the keyboard button in the Control Bar, shortcut M). Otherwise each key plays twice on the main Mac.
5. Set the MIDI tracks you want to play to receive from **TwinKeys** (or "All Ins") and arm or monitor them as usual.

## Using TwinKeys

1. Open TwinKeys on both Macs on the same network (a wired network or a dedicated router is the most reliable).
2. On the main Mac, check **Send my keys**. On the backup Mac, check **Receive notes**. (Both can be on.)
3. In **Nearby TwinKeys**, click **Connect** next to the other Mac. The header shows **Connected to …** and the latency (heartbeat round trip).
4. Play. The default layout follows the common DAW computer keyboard: home row A S D F G H J K L ; = white keys, W E T Y U O P = black keys, **Z / X** = octave down / up, **C / V** = velocity down / up. Keys are matched by physical position, so JIS and US keyboards behave the same.

If the network drops, TwinKeys keeps retrying (every 1 s, slowing to every 5 s) and reconnects by itself. Notes that came from the other Mac are turned off when the link drops; notes played on the main Mac's own keys keep sounding.

### Shortcuts

| Action | Shortcut |
|---|---|
| Connect / Disconnect | ⌘K |
| Key capture on / off | ⌃⌘K |
| All Notes Off (panic) | ⌃⌘P |
| Settings | ⌘, |

Keys pressed together with ⌘, ⌃, ⌥ or ⇧ never play notes, so shortcuts in other apps stay silent. Turn **Key capture** off while typing in other apps.

### Safety

- **All Notes Off** (the red button) stops notes on this Mac and the connected Mac.
- All Notes Off is also sent when you quit TwinKeys or click Disconnect.
- A note that never receives its note-off is stopped automatically after 10 seconds (change in Settings, 0 turns it off).
- TwinKeys does **not** switch audio between Macs. Automatic audio failover needs dedicated hardware and is out of scope.

## Files

| What | Where |
|---|---|
| Settings | `~/Library/Application Support/TwinKeys/settings.json` |
| Key mapping | `~/Library/Application Support/TwinKeys/mapping.json` (created on first launch; Settings → Reload Mapping after editing) |
| Logs | `~/Library/Logs/TwinKeys/TwinKeys-YYYY-MM-DD.log` |

`mapping.json` uses macOS virtual key codes (positions, not characters). Example entry: `{ "keycode": 0, "label": "A", "semitone": 0 }`. Semitone 0 is C of the current octave; octave 3 makes the A key MIDI note 60 (shown as C3).

## Constants you may want to change

| Constant | Value | Where |
|---|---|---|
| Bundle identifier | `io.github.kajisho5.twinkeys` | `Resources/Info.plist` |
| Bonjour service type | `_twinkeys._udp` | `Resources/Info.plist`, `Sources/TwinKeys/NetworkService.swift` |
| Virtual port name | `TwinKeys` | `Sources/TwinKeys/AppModel.swift` |
| Heartbeat / timeout / retry | 1 s / 3 s / 1–5 s | `Sources/TwinKeysCore/LinkStateMachine.swift` |
| Copies of each note packet | 2 | `Sources/TwinKeysCore/Conductor.swift` (`redundancy`) |
| Default auto note-off | 10 s | `Sources/TwinKeysCore/Settings.swift` |
| Default MIDI channel | 1 | `settings.json` (`midi_channel`) |
| App icon | made with fresnel | source: `design/icon/` (`twinkeys.spec.json`, `TwinKeys.icon`); built `.icns`: `Resources/AppIcon.icns` |

## Building from source

Requires macOS with Xcode 16 or later.

```sh
swift test                      # unit tests
scripts/build-app.sh 1.0.0 1    # builds dist/TwinKeys.app (universal) and a zip
```

The platform-independent logic (`Sources/TwinKeysCore`) also builds and tests on Linux with Swift 6.

### Releases (GitHub Actions)

- Every push runs **CI** on a macOS runner: tests, universal build, launch check and screenshots (downloadable from the run page).
- **Release:** change the `VERSION` file (for example to `0.2.0`) and push. GitHub Actions builds the app, creates the tag `v0.2.0` on that commit and publishes a release with `TwinKeys-0.2.0-universal.zip`. Versions 0.x and versions with a suffix such as `1.0.0-beta.1` are marked as pre-releases. Pushing a `v*` tag or running the workflow by hand also works.

## Limitations

- One-to-one link (one main, one backup) in v1.
- TwinKeys cannot know whether your music software has the TwinKeys port turned on; it only knows the port exists.
- Key capture does not see keys typed into password fields (macOS Secure Input).
- Wi-Fi adds variable delay that TwinKeys cannot control. Prefer a wired network.

## Credits

TwinKeys is made by **Shogo Kajiyama / SEVENTHWELL**. Released under the MIT License (see [LICENSE](LICENSE)). The app icon uses the letters "TK" from Inter (SIL Open Font License), converted to outlines.

## Roadmap

- RTP-MIDI (AppleMIDI) compatibility (v2 candidate)
- Menu bar mode (v2 candidate)
- Planned v1.x additions: several backups at once, remote MIDI ports, named virtual ports and routing, presets, status of both Macs, watchdog alarm, event log.

Not planned: Windows, audio processing, automatic audio failover, setlist management.

---

## 日本語の概要

TwinKeys は、2台の Mac で同じ MIDI ノートを同時に鳴らすための小さな Mac アプリです。制作は Shogo Kajiyama / SEVENTHWELL です。メイン機のキーボードを押すと、メイン機とバックアップ機の両方の音楽ソフトに同じノートが届きます。ライブでメインとバックアップの2台を並べて動かす構成向けです。

> **非公式のサードパーティ製ツールです。** Ableton 社ほか DAW メーカーとは関係ありません。「Ableton」「Live」は Ableton AG の商標で、対応状況の説明のためにだけ記載しています。

- 各 Mac に仮想 MIDI 入力「TwinKeys」ができます。Live の設定で TwinKeys の **Track** と **Remote** を ON にするだけで使えます（転送用トラックは不要）。
- テンポと小節位置は Ableton Link（Live 内蔵）で合わせてください。TwinKeys は扱いません。
- 2台は同じネットワーク上で自動的に見つかります。「Connect」を押すだけで接続し、切れても自動で再接続します。
- 赤い **All Notes Off** ボタン（⌃⌘P）で、両方の Mac の音をすべて止められます。
- 初回起動は、上の「Download and first launch」の手順（右クリック→開く、または「このまま開く」）に従ってください。メイン機では「入力監視」、両方の Mac で「ローカルネットワーク」の許可が必要です。
- メイン機では Live 本体のコンピュータMIDIキーボードを OFF にしてください（ON のままだと同じ音が2回鳴ります）。
- 音声そのものの自動切り替え（オーディオフェイルオーバー）は対象外です。
- 表示言語は「設定」（⌘,）の「言語」で、「システムに合わせる」「English」「日本語」から選べます。
