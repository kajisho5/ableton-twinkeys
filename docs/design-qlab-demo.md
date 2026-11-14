# QLab のデモ：iPhone の「サンプルで試す」とサイトの見本（設計・確認待ち）

絵：`docs/design/qlab-demo-app.png`（A）、`qlab-demo-site-go.png`・`qlab-demo-site-list.png`（B）。絵の元：`design/qlab-demo/make.py`。
データはすべて架空（ワークスペース「sample-show」、キュー「雨の音（遠く）」など。今の QLab サンプルと同じ）。

## 1. ねらい

QLab モードを、Mac も QLab もない人が iPhone とサイトで試せるようにする。

## 2. 技術

新しい技術は使わない。今のものに足す。

| 場所 | 使うもの | 理由 |
|---|---|---|
| A. iPhone アプリ | Swift・SwiftUI（今のアプリ） | 今の QLab サンプル（`-demo -target qlab`）をそのまま使える |
| B. サイト | Astro と素の TypeScript（今の「触って試す」） | 今の見本（`RemoteDemo.astro`、`remote-demo.ts`）に QLab の状態を足す。ライブラリは増やさない |

## 3. A：iPhone アプリ（TwinKeys Remote 1.4.0 に入れる）

### 画面
1. 最初の画面：「サンプルで試す」ボタン1つを、2つの大きなボタンに分ける。
   - 「Live のサンプル」（シーンとクリップ）／「QLab のサンプル」（キューの一覧と GO）。
   - 上に小見出し「MAC がなくても試せます」。下の説明文は今のまま。
2. 「QLab のサンプル」を押すと、QLab モードの GO 画面が開く（中身は今の QLab 画面）。上の帯の Mac の名前に「・サンプル」が付く（今と同じ）。
3. サンプル中の設定：「サンプル」の欄に3行。
   - 「見ているサンプル：QLab」（または Live）
   - 「Live のサンプルに切り替える」（QLab のときは「QLab のサンプルに切り替える」）
   - 「サンプルを終わって Mac につなぐ」（今のまま）

### 動き
- QLab のサンプルでは、GO・前へ・次へ・一覧のタップ・STOP・PANIC が、今の画面写真用サンプル（`applyDemoQLab`）と同じく画面の中だけで動く。何も送らない。
- Apple Watch も QLab の3画面（GO・一覧・PANIC）になる（今の Watch の仕組みのまま）。
- App Review の担当者にも2つのボタンが見える。審査メモに「QLab のサンプル」も書き足す。

### 作り（ファイル）
- `RemoteModel.swift`：`startTrial(target:)`（`.live` か `.qlab`）。`loadDemoQLab` を起動引数がなくても使えるようにする。
- `PairView.swift`：ボタン2つ。`Panes.swift`：サンプルの欄。
- テスト：CI の画面写真に「最初の画面」と「サンプル中の設定」を足す。VoiceOver の読み上げ名を付ける。

## 4. B：サイトの「触って試す」

### 画面
- 見出しの右に切り替え「Ableton Live｜QLab」（初めは Ableton Live、今の見本のまま）。
- QLab にすると、中身だけが QLab になる。見た目（白い地、緑の GO、黒い iPhone）は今の見本と同じ。
  - iPhone（横）：上の帯に ワークスペース・動いている・リスト・PANIC（2台）。左に「いま鳴っている」「次」「バックアップも 13 で待機中」、右に大きな GO。右のレールは 一覧・キュー・GO・設定（動くのは 一覧 と GO。今の見本と同じく、ほかは「アプリで使えます」）。
  - 一覧：16 個のキュー。鳴っているキューは緑、次は青。タップで「次」がそこに移る（鳴らさない）。「追従」で一覧が自動で流れる。
  - Apple Watch：M・B・Q のランプ、いま鳴っているキュー、GO と残り時間、「次：13 雷鳴 1」。3画面（GO・一覧・PANIC）。
  - Mac のカード：「QLab ✓」「▶ 12 雨の音（遠く）」「待機：13 雷鳴 1」。
  - つながり：各 Mac の先に「QLab（この Mac の中だけ）」。卓は出さない。
  - 「メインの Mac を止めてみる」：今と同じ流れ（バックアップの QLab は鳴り続け、iPhone に切り替えの案内）。
- 下の説明文を QLab 用に替える。

### 動き（状態）
- `remote-demo.ts` に `mode: 'live' | 'qlab'` と QLab の状態（キュー一覧、いま鳴っているキューと始まった時刻、次のキュー、最後の GO）を足す。今と同じく「状態を受けて新しい状態を返す」関数だけで作る。
- GO：次のキューを鳴らす（残り時間が減る）。グループは飛ばす。0.5 秒以内の2回目は無視（アプリと同じ）。
- PANIC：鳴っているものを全部止める。STOP：長押し。
- 切り替えると、どちらも初めの状態に戻る。選んだ方は URL の `#demo-qlab` で覚える（共有できる）。
- 文言は日本語・英語（`remote-demo-text.ts`）。

### 作り（ファイル）
- `site/src/lib/remote-demo.ts`（状態と動き）、`remote-demo-text.ts`（文言）、`remote-demo-map.ts`（つながりの図）、`components/RemoteDemo.astro`（表示）。
- テスト：今の見本のテスト（あれば）に QLab の GO・一覧・PANIC・止めてみる を足す。Playwright で日・英の画面写真を撮って確かめる。

## 5. 確かめること
- 縦・横、日本語・英語、ダーク（アプリ）、スマホ幅（サイト、横スクロールなし）。
- サイトの見本はキーボードでも操作できる（今と同じ）。
