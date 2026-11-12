# TwinKeys Remote 1.3：見た目を A1「緑のランプ」に（承認 2026-11-12「それで」）

デザイン：`docs/design/restyle-a1.png`（GO 画面と Watch）、`restyle-a1-session.png`、`restyle-a1-mixer.png`、`restyle-a1-cues.png`、`restyle-a1-lost.png`、`restyle-a1-watch.png`。絵の元：`design/restyle/make_a.py`（THEMES["a1"]）、`design/restyle/make_a1.py`。

## 1. 変えるもの・変えないもの

- 変えるのは**見た目だけ**。画面の並び、ボタンの場所、押したときの動き、文言の意味、通信は変えない。
- iPhone・iPad・Apple Watch の全部の画面（ペアリング・設定も同じ色と部品で）。
- 明るい画面（ライトモード）でも A1 の黒い画面にする（本番の暗い現場用）。※いまライトモードがあるなら、それを外すかどうかは実装のときに確かめて、外す場合は理由を書く。

## 2. 色（design/restyle/make_a.py の a1 と同じ値）

| 名前 | 値 | 使うところ |
|---|---|---|
| bg | #000000 | 背景 |
| top | #070707 | 上の帯・右のレール |
| panel | #060606 | カード・ボタン |
| stroke | #2A2A2A | 細い線（2pt 相当） |
| accent | #3DFF7A | 正常・再生中・GO（光る） |
| accentSoft | #9AF5B7 | GO の中の小さな文字 |
| read | #EDEDED | 数字・本文 |
| label | #6B6B6B | 小さな見出し |
| off | #151515 | 消えたメーターの目盛り |
| red | #FF3B30 | 止まった・全ノートオフ |
| yellow | #FFB020 | バックアップがメイン |
| blue | #8AB4FF | 「次」 |

## 3. 部品

- **ランプ（LED）**：小さな丸＋同じ色のぼかし（光）。MAIN・BACKUP・LIVE、Watch の M・B、レールの選択中。
- **表示窓**：TEMPO・POSITION は黒い枠の中に、小さな見出し＋等幅の数字。
- **小さな見出し**：等幅・字間を空けた英大文字（NOW PLAYING、NEXT、SCENES、CUE KEYS、MACS など）。本文と操作の文言は今の日本語・英語のまま。
- **数字**：等幅（SwiftUI の `.monospacedDigit()` か等幅のシステム書体）。
- **メーター**：四角い目盛りを並べる（残り時間、ミキサーの音量は緑→黄→赤）。
- **GO キー**：暗い緑のグラデーション、ふちが緑に光る、大きな等幅の「GO」。
- **全ノートオフ**：暗い赤の地に赤いふち、赤い文字。
- 書体はシステム書体のまま（SF・ヒラギノ）。等幅は SF Mono 相当（`.monospaced`）。

## 4. 確かめること

- 文字の大きさを最大にしても切れない（Dynamic Type）、VoiceOver の読み上げは今と同じ。
- 色のコントラスト：本文・数字・ボタンの文字は背景に対して 4.5:1 以上（label #6B6B6B は小見出しだけに使う）。
- CI の画面写真（iPhone・iPad・Watch）がデザインの絵と同じに見える。
