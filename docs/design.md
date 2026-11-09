# TwinKeys 詳細設計書（v1 コア）

- 状態：**承認済み（2026-11-09、Q1〜Q7 すべて推奨案）**。実装は Swift＋SwiftUI
- 作成日：2026-11-09
- 対象：仕様書（prompt.md）1〜12 節。最小対応 OS は macOS 13 Ventura（確定済み）

凡例：**[事実]** 一次情報で確認済み／**[推測]** 根拠はあるが実機未確認／**[不明]** 確認できていない

---

## 0. 確認事項と決定（すべて推奨案で決定）

| # | 内容 | 推奨案 |
|---|---|---|
| Q1 | 開発言語（2節の比較を参照）。仕様は Rust 指定ですが、理由の記載がないため代案を出します | **Swift＋SwiftUI**（Rust のままでも可。どちらでも UI・通信仕様・SVG は同じ） |
| Q2 | キー取得の部品：`rdev` は crates.io の最新が 2023-06 の 0.5.3 で止まっている → 仕様 5 節に従い代替を提案 | Apple の CGEventTap を直接使う（Rust なら `objc2-core-graphics`） |
| Q3 | 必要な許可の名前：仕様は「アクセシビリティ許可」だが、キーを**見るだけ**（横取りしない）の監視は「入力監視（Input Monitoring）」許可で足りるはず | 「入力監視」許可を案内。念のため両方の状態を表示 **[推測：実機で確認]** |
| Q4 | 演奏キーの ON/OFF（仕様外）：他アプリで文字入力しても音が出てしまう | 「Key capture」ON/OFF を追加（ショートカット ⌃⌘K） |
| Q5 | ⌘・⌃・⌥ を押しながらのキー（仕様外） | 演奏として扱わない（ショートカット操作で音が出る事故を防ぐ）。Shift も無視 |
| Q6 | ノート信号の二重送信（仕様外・信頼性向上） | ノートオン/オフ/All Notes Off を 2 回送り、受信側は番号で重複を捨てる |
| Q7 | バンドル ID | **`io.github.kajisho5.twinkeys`**（代案：`com.seventhwell.twinkeys` ※独自ドメインを持っている場合のみ） |

---

## 1. 要件の整理（コア／後回し可）

### コア（v1 で必ず作る）
1. 仮想 MIDI ポート「TwinKeys」作成
2. グローバルキー取得 → ノート変換（物理キー位置ベース、JSON で変更可、キーリピート無視、和音対応）
3. mDNS で相手検出・自分自身は除外、UDP 送受信、ハートビート、自動再接続
4. 安全装置（パニック、終了時・切断時 All Notes Off、10 秒自動オフ）
5. 1 画面 UI、メニューバー、ショートカット、許可の案内、空状態
6. .app 化、GitHub Actions で universal ビルド → zip を Release に添付
7. 単体テスト、README、manual-test.md、動作確認レポート

### 後回し可（コア完成後に順番に追加）
- 8 節パリティ P1〜P7（3 台以上、リモート MIDI 機器、複数ポート、プリセット、両機状態、警告音、イベントログ）
- 9 節アイコン：fresnel（CLI `fresnel-icon`）で作成済み。2026-11-09 の指示により、仕様の「文字なし」から「TK」の文字アイコンに変更（Inter Bold を図形に変換、SIL Open Font License）。元データ `design/icon/`、書き出し `Resources/AppIcon.icns`、プレビュー `deliverables/icon/`

### 仕様の過大・リスク指摘
- **追加遅延 5ms 以下**：アプリ内処理は 1ms 未満で設計可能。ただし Wi-Fi の揺らぎは数 ms〜数十 ms あり、アプリでは制御不可。README で「有線 LAN 推奨」と書く **[推測]**
- **メモリ 50MB 以下**：egui（GPU 描画）だと超える可能性あり **[不明：実機で測定]**。SwiftUI ならおおむね収まる見込み **[推測]**
- **スクリーンショット（実 Mac のウィンドウ）**：この開発環境は Linux のため、GitHub Actions の Mac で撮影する仕組みを用意する

---

## 2. 技術選定（Q1 の比較）

| 観点 | A. Rust＋egui（仕様どおり） | B. Swift＋SwiftUI（推奨） | C. Tauri（Rust＋Web画面） |
|---|---|---|---|
| 動作の軽さ | 良い（GPU 描画で常駐メモリはやや多め） | とても良い（OS 標準部品） | 普通（WebView 分の負荷） |
| 配布サイズ | 約 10〜20MB（universal）**[推測]** | 数 MB **[推測]** | 約 10MB 前後 **[推測]** |
| HIG への沿いやすさ | **弱い**：ボタン等が macOS 標準部品ではなく似せて描く。メニューは別部品（muda）が必要 | **最も強い**：標準ボタン・メニュー・ダーク切替・VoiceOver が最初から正しい | 中：見た目は CSS で似せるだけ |
| 外部部品の数 | 多い（MIDI・mDNS・UI・メニュー・ログ） | **ほぼゼロ**（CoreMIDI・Network.framework・CGEventTap は OS 内蔵） | 多い |
| 作りやすさ（この環境） | ロジックは Linux 上でテスト可能 | Linux では画面部分をビルドできず、ビルド確認は毎回 GitHub Actions の Mac 頼み | Rust 側は Linux でテスト可 |
| 対応 OS | Mac（将来 Win も可） | Mac のみ（仕様も Mac のみ） | Mac/Win |
| 将来性 | egui は活発（0.37.0、2026-10） | Apple 公式 | 活発 |
| AI での書きやすさ | 良い | 良い | 良い |

**おすすめ：B. Swift＋SwiftUI。** 理由：仕様 3 節「HIG 必須」と「メモリ 50MB・起動 1 秒」を最も素直に満たせ、保守が止まった部品（rdev）問題も起きないため。
欠点：ビルド確認が GitHub Actions 経由になり 1 回数分かかる。

**Rust のまま（A）を選ぶ場合**の部品は下表。どちらを選んでも、3 章以降（画面・通信・データ・テスト）は共通です。

### 2.1 Rust 案の部品確認結果（crates.io、2026-11-09 時点）

| 用途 | 部品 | 最新安定版 | 最終更新 | 判定 |
|---|---|---|---|---|
| 仮想 MIDI ポート | midir | 0.11.1 | 2026-10-10 | 使用可。macOS では coremidi 0.9 を使用し `create_virtual` あり **[事実]** |
| mDNS | mdns-sd | 0.21.7 | 2026-11-02 | 使用可 |
| キー取得 | rdev | 0.5.3 | **2023-06-26** | **不採用**：crates.io のリリースが 3 年以上なし（GitHub には 2026-05 のコミットあり）。キーリピート判定の情報も出してくれない |
| キー取得（代替） | objc2-core-graphics | 0.3.2 | 2025-10-04 | 採用：`CGEvent::tap_create`、キーコード、キーリピート判定（`KeyboardEventAutorepeat`）、`CGPreflightListenEventAccess` が使える **[事実]** |
| UI | eframe / egui | 0.37.0 | 2026-10-15 | 使用可。VoiceOver 連携（accesskit）は標準で有効 **[事実]** |
| メニューバー | muda | 0.21.2 | 2026-10-08 | 使用可（egui だけでは macOS 標準メニューを作れないため） |
| 設定 JSON | serde 1.0.229 / serde_json 1.0.154 | | | 使用可 |
| ログ | tracing 0.1.44 / tracing-appender 0.2.5 | | | 使用可（日次ローテーション・保持数指定あり：P7 で使用） |

根拠 URL：
- https://crates.io/crates/midir ・ https://crates.io/crates/mdns-sd ・ https://crates.io/crates/rdev ・ https://crates.io/crates/objc2-core-graphics ・ https://crates.io/crates/eframe ・ https://crates.io/crates/muda ・ https://crates.io/crates/tracing-appender
- https://docs.rs/objc2-core-graphics/0.3.2/objc2_core_graphics/struct.CGEvent.html
- Rust ツールチェーン：必要最小 1.95（mdns-sd の rust-version）。この環境は rustc 1.97.0

### 2.2 Swift 案の部品
- 仮想ポート：CoreMIDI `MIDISourceCreateWithProtocol`（OS 内蔵）
- 検出：Network.framework `NWListener`（Bonjour 公開）＋`NWBrowser`（検出）
- 送受信：`NWConnection`（UDP）
- キー取得：`CGEvent.tapCreate`（listenOnly）
- UI：SwiftUI、メニューは `.commands`、設定は `Settings` シーン（⌘, が自動で付く）
- バージョン：実装開始時に GitHub Actions の macOS ランナーの Xcode／Swift 版を確認して記載

### 2.3 OS 側の事実確認
- macOS 15 以降、Bonjour の登録・検出や LAN 宛て通信には「ローカルネットワーク」許可が必要。マルチキャスト用の特別な権限（entitlement）は **macOS では不要** **[事実]** https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Info.plist の `NSLocalNetworkUsageDescription`、`NSBonjourServices` **[事実]** https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices
- `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`（macOS 10.15〜）**[事実]** https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()
  - 「見るだけのキー監視には入力監視許可」という対応関係は Apple 文書の本文で確認できず **[推測]**（Q3）

---

## 3. 画面設計（1 画面）

デザイン：`docs/design/main-light.svg` / `main-dark.svg`（既定 560×420）、`min-size-light.svg` / `min-size-dark.svg`（最小 440×330、許可なし＋相手なし）。確認用 PNG も同フォルダ。

### 3.1 構成（上から）
1. **状態ヘッダー（常に表示・スクロールしない）**
   - 状態の丸印＋文言：`Not connected` / `Connecting to <名前>…` / `Connected to <名前>`
   - 補足行：`Latency 2 ms · Sending and receiving` など
   - 右端：**All Notes Off**（パニック、赤塗り・白文字）
2. **Nearby TwinKeys**（相手一覧）：名前、相手のモード、遅延、`Connect` / `Disconnect`。接続中の行は薄い青背景
   - 空状態：`No TwinKeys found on this network` ＋対処文＋`How to Fix…`（手順シートを開く）
3. **Mode and Keyboard**：`Send my keys` / `Receive notes`（チェックボックス、両方可）、Key capture 状態、オクターブ（Z/X）、ベロシティ（C/V）、押下中ノート、DAW 側キーボード OFF の注意
4. **許可の状態**（下端の 1 行）：Input Monitoring／Local Network
   - 未許可時は一覧の上に黄色枠の案内（`Open System Settings…` と `Check Again`）

最小サイズでは 1（接続状態・パニック）が固定表示、2 の接続ボタンも見える高さを確保し、3・4 はスクロール。

### 3.2 メニューバー（macOS 標準構成）
- **TwinKeys**：About TwinKeys／Settings…（⌘,）／Hide・Hide Others・Show All／Quit TwinKeys（⌘Q）
- **Edit**：標準（Undo/Cut/Copy/Paste/Select All。設定画面の文字入力用）
- **Connection**：Connect / Disconnect（⌘K）／Key Capture On/Off（⌃⌘K）／All Notes Off（⌃⌘P）
- **Window**：Minimize（⌘M）／Zoom／Close（⌘W）
- **Help**：TwinKeys Help（README を開く）

ショートカット方針：⌘Q/⌘W/⌘C/⌘V/⌘P（印刷）/⇧⌘P（ページ設定）等の標準と衝突させない。演奏キー（A 列など）は修飾キーなしでしか演奏扱いしないので重ならない。

### 3.3 Settings…（別ウィンドウ、v1 は最小限）
- 自動オフ秒数、マッピングファイルを Finder で開く、設定フォルダを開く、既定に戻す

### 3.4 デザイン規則（仕様 3 節の数値化）
- 文字：本文 13pt、補足 11pt、最小 11pt（10pt 未満なし）、数値表示 17pt。フォントはシステムフォント
- 操作部品：ボタン高さ 28pt、チェックボックスはラベル込みで 20pt 以上のクリック範囲
- 余白：外周 16pt、グループ間 18pt、グループ角丸 8pt、ボタン角丸 6pt
- ホバー：ボタン背景を一段明るく／暗く。キーボード操作時はフォーカス枠を表示
- VoiceOver：全ボタン・チェックボックス・状態表示にラベル（例：「All Notes Off, button. Sends note off to this Mac and the connected Mac」）

### 3.5 色テーマ（外観に自動追従、コントラストは計算済み）

| 役割 | ライト | ダーク | 文字コントラスト（背景比） |
|---|---|---|---|
| ウィンドウ背景 | #ECECEC | #1F1F21 | — |
| グループ背景 | #FFFFFF | #2C2C2E | — |
| 本文 | #1D1D1F | #F2F2F7 | 14.3 / 14.8 |
| 補足文 | #5F5F64 | #AEAEB2 | 5.4 / 7.4（最小 5.1） |
| アクセント（青） | #0060C7 | #5AA9FF | 5.1 / 6.7 |
| 青塗りボタン＋白文字 | #0060C7 | #1A66CC | 6.0 / 5.5 |
| 接続済み（緑） | #1B7A31 | #4FD06A | 4.6 / 8.3 |
| 注意（黄） | #8A5A00 | #F2B13A | 5.0 / 8.7 |
| パニック（赤塗り＋白文字） | #C0241A | #C0241A | 6.0 |
| 選択行背景 | #DCE9FA | #23364F | 本文 13.7 / 11.0 |

すべて WCAG AA（4.5:1）以上。状態は色だけでなく文言でも示す（色覚への配慮）。

### 3.6 HIG と egui の衝突（Rust 案を選んだ場合に起きること）
- ボタン等が macOS 標準部品ではない → 見た目を上記トークンで近づけるのが限界
- システムのアクセントカラー設定・ウィンドウの半透明表現には追従しない
- 標準メニューは muda で別途作る
→ HIG 優先の方針なら Swift 案のほうが確実（Q1）

---

## 4. 内部構成

### 4.1 部品の分け方（スレッド）
```
[キー監視] --KeyEvent--> [演奏エンジン] --Note--> [MIDI 出力(自機ポート)]
                              |                         ^
                              +--Note--> [ネット送信]    |
[ネット受信] --Note-----------------------------------+
[接続管理（状態機械・ハートビート・再接続）] <--> [UI]
[安全装置（10 秒自動オフ・切断時/終了時 All Notes Off）]
```
- キー監視：専用スレッドの RunLoop で CGEventTap（listenOnly）。押下/解放とキーコードだけを最短で渡す
- 演奏エンジン：押下中キー集合を持ち、二重押下・キーリピートを排除してノートオン/オフを生成
- 遅延対策：キー → 自機ポート出力とネット送信を同じスレッドで即時実行（UI スレッドを経由しない）

### 4.2 状態（UI に出すもの）
```
AppState {
  mode: { send: bool, receive: bool },
  key_capture: On | Off | NoPermission,
  octave: i8 (-2..=8, 既定 3), velocity: u8 (既定 100),
  held_notes: Set<u8>,
  peers: [ Peer { id, name, modes, addr, last_seen } ],
  link: Idle | Connecting{peer, attempt, next_retry} | Connected{peer, rtt_ms} ,
  permissions: { input_monitoring: Granted|Denied|Unknown, local_network: PeersSeen|NoneSeen },
}
```

### 4.3 再接続の状態遷移（単体テスト対象）
- Idle →（Connect 押下）→ Connecting →（Hello 応答）→ Connected
- Connected →（3 秒ハートビート応答なし）→ All Notes Off（自機）→ Connecting
- Connecting の再試行間隔：1s → 2s → 4s → 5s → 5s …（最大 5 秒）
- Disconnect 押下 → 相手と自機へ All Notes Off → Idle

### 4.4 All Notes Off を出す条件（単体テスト対象）
- パニック押下（自機ポート＋相手）／アプリ終了／切断判定／手動切断／Send を OFF にしたとき（押下中ノートがある場合）
- 送り方：全 16ch に CC123（All Notes Off）＋押下中ノートの個別ノートオフ（CC123 を無視する機器への保険）

---

## 5. 通信仕様（独自 UDP）

- サービス名：`_twinkeys._udp`（Info.plist の `NSBonjourServices` に記載）
- TXT：`id`（起動ごとではなく初回生成して保存する UUID）、`v`（プロトコル版）、`modes`（s/r/sr）
- ポート：OS が空きを割り当て、mDNS で公表（固定ポート不要）
- 自分自身の除外：`id` が自分と同じものは一覧に出さない

パケット（ビッグエンディアン、最大 24 バイト程度）：
```
magic "TK" (2) | version (1) | type (1) | seq u32 (4) | payload
type: 0x01 Hello{id 16B} / 0x02 HelloAck{id 16B}
      0x10 NoteOn{ch, note, vel} / 0x11 NoteOff{ch, note}
      0x20 AllNotesOff
      0x30 Heartbeat{t_ns u64} / 0x31 HeartbeatAck{t_ns u64 をそのまま返す}
```
- seq：送信側で 1 ずつ増加。受信側は「最後に受けた番号より新しいもののみ受理」（番号の一周は循環比較で処理）→ 重複と順序入れ替わりを破棄
- ハートビート 1 秒ごと、遅延表示 = 往復時間（直近 5 回の中央値を表示）
- 3 秒間応答なしで切断判定

---

## 6. データ構造（設定ファイル）

保存先：`~/Library/Application Support/TwinKeys/`、ログ：`~/Library/Logs/TwinKeys/`

`settings.json`
```json
{ "version": 1, "instance_id": "UUID", "mode": { "send": true, "receive": false },
  "auto_note_off_seconds": 10, "midi_channel": 1, "last_peer_id": null }
```
`mapping.json`（既定値を同梱、キーは Mac の物理キーコード＝JIS/US 共通位置）
```json
{ "version": 1, "base_octave": 3,
  "notes": [ { "keycode": 0, "label": "A", "semitone": 0 },
             { "keycode": 13, "label": "W", "semitone": 1 } ],
  "octave_down": 6, "octave_up": 7, "velocity_down": 8, "velocity_up": 9,
  "velocity_step": 20 }
```
- 白鍵：A S D F G H J K L ;（keycode 0,1,2,3,5,4,38,40,37,41）→ C D E F G A B C D E
- 黒鍵：W E T Y U O P（13,14,17,16,32,31,35）→ C# D# F# G# A# C# D#
- Z/X=6/7（オクターブ）、C/V=8/9（ベロシティ）
- 上記キーコードは Apple の HIToolbox 定義値 **[事実：一般に公開されている定義。実装時に objc2 側の定数名と照合]**、Live の配列との一致は manual-test で確認 **[推測]**

---

## 7. フォルダ構成（確定：Swift Package）

```
ableton-twinkeys/
├─ Package.swift                 swift-tools-version 5.10、macOS 13 以上
├─ Sources/
│  ├─ TwinKeysCore/              OS に依存しない中心部分（Linux でもテスト可）
│  │   KeyMapping / PerformanceEngine / NoteGuard / WireProtocol(+SequenceFilter)
│  │   LinkStateMachine / Safety / Conductor / Settings / Peers / MIDIMessage
│  └─ TwinKeys/                  Mac アプリ
│      Main / TwinKeysApp / AppModel / ViewState / ContentView / HelpView / SettingsView
│      Theme / Components / VirtualMIDIPort(CoreMIDI) / KeyMonitor(CGEventTap)
│      NetworkService(Network.framework) / FileLog / Snapshot(スクリーンショット生成)
├─ Tests/TwinKeysCoreTests/      単体テスト（2台模擬テストを含む）
├─ Resources/                    Info.plist, mapping.default.json, AppIcon-1024.png
├─ scripts/build-app.sh          universal .app と zip を作る
├─ .github/workflows/            ci.yml（毎 push）, release.yml（v* タグ）
├─ docs/                         design.md, design/, manual-test.md, test-report.md
└─ deliverables/                 スクリーンショット・アイコン PNG
```

ビルド環境：GitHub Actions `macos-26`（Xcode 26.6）。根拠：https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
この開発環境での中心部分テスト：Swift 6.4.2（Linux）。根拠：https://www.swift.org/install/

### 参考：当初の Rust 案の構成（不採用）

```
ableton-twinkeys/
├─ Cargo.toml
├─ src/
│  ├─ main.rs            起動・スレッド組み立て
│  ├─ app/ (ui.rs, theme.rs, menu.rs, a11y.rs)
│  ├─ engine/ (mapping.rs, keystate.rs, safety.rs)     ← Linux でテスト可
│  ├─ net/ (protocol.rs, link.rs[状態機械], discovery.rs, transport.rs)
│  ├─ midi/ (virtual_port.rs)
│  ├─ platform/macos/ (event_tap.rs, permissions.rs)
│  └─ config/ (settings.rs, paths.rs)
├─ resources/ (Info.plist, mapping.default.json, AppIcon.icns)
├─ scripts/ (bundle.sh: universal 化と .app 組み立て)
├─ .github/workflows/ (ci.yml, release.yml)
├─ docs/ (design.md, design/*.svg, manual-test.md, test-report.md)
├─ deliverables/ (アイコン PNG、UI スクリーンショット)
└─ README.md / LICENSE(MIT)
```

---

## 8. パッケージングと配布
- `.app` は自作スクリプトで組み立て（arm64 と x86_64 を別々にビルド → `lipo` で結合 → Info.plist・アイコンを配置 → 署名なし／ad-hoc 署名）
- Info.plist：`CFBundleIdentifier`（Q7）、`LSMinimumSystemVersion 13.0`、`NSLocalNetworkUsageDescription`、`NSBonjourServices = [_twinkeys._udp]`
- Release ワークフロー：タグ `v*` を push すると macOS ランナーでビルド → `TwinKeys-<版>-universal.zip` を Release に添付
- README に「右クリック → 開く」での初回起動手順（macOS 15 以降で手順が変わる点も調べて記載）

## 9. テスト計画
- 単体：マッピング変換（JIS/US 同一キーコード、オクターブ端、リピート無視、和音）、プロトコル（往復変換、壊れたパケット拒否、seq 重複・逆順・一周）、再接続状態遷移（時間を差し替えてテスト）、All Notes Off 条件
- CI：Linux でロジックのテスト、macOS ランナーでビルドと全テスト
- 実機：`docs/manual-test.md`（Live 11 / Live 12 の結果欄を別々に用意）

## 10. 作業ブロック（承認後）
(1) 雛形＋仮想ポート → (2) キー取得＋変換 → (3) 検出＋通信＋再接続 → (4) UI＋安全装置 → (5) .app＋Release。各ブロックでビルド・テスト確認後に push。その後 P1〜P7。
