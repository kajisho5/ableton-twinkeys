# TwinKeys 2.4 の設計案：Yamaha の卓（QL・DM）のフェーダーを引き継ぐ（承認待ち）

図：`docs/design/mac-ql-dark`（中身は架空のサンプル）

## ねらい

メインの Mac が止まったとき、卓でメインの Mac の音が入っているチャンネルを下げ、バックアップの Mac のチャンネルを、メインが直前まで出ていた高さまで上げる。

## 対応する機種

| 機種 | 入力の Ch | 高さを読む | 高さを書く |
|---|---|---|---|
| QL1 | 1–32、ST IN 1–8 | ○（非公式） | ○（Yamaha 公式のスクリプト例） |
| QL5 | 1–64、ST IN 1–8 | ○（非公式。QL5 での報告あり） | ○（同上） |
| DM3 / DM3 Standard | 1–16、ST IN 1 | ○（非公式） | ○（公式 OSC） |
| DM7 | 1–120 | ○（非公式。DM7 での報告あり） | ○（公式 OSC） |
| DM7 Compact | 1–72 | ○（非公式。報告あり） | ○（公式 OSC） |
| DM5 | 1–60 | ？ 未確認 | ○（公式 OSC） |
| DM5 Compact | 1–48 | ？ 未確認 | ○（公式 OSC） |

チャンネル数は Yamaha の仕様のページによる（QL：https://usa.yamaha.com/business/audio/products/mixers/ql-series/specs.html 、DM3：…/dm3/specs.html 、DM7：…/dm7/specs.html 、DM5：…/dm5/specs.html）。

## 調べたこと

| 区分 | 内容 | 出典 |
|---|---|---|
| 事実 | QL シリーズは Yamaha のサイトで「生産完了（Discontinued）」 | https://usa.yamaha.com/business/audio/products/mixers/ql-series/index.html |
| 事実 | QL・CL 向けに、Yamaha が公式の Python スクリプト例（2019年）を出している。`set MIXER:Current/InCh/Fader/Level <ch> 0 <値>`（ch は 0 から、値は dB×100、−∞ は −32768）、TCP 49280、ファームウェア V3.11 以降。読み取り（get）や知らせ（NOTIFY）は書かれていない | https://usa.yamaha.com/files/download/other_assets/0/1266290/Python_Script_Template_V100.zip |
| 事実 | DM7・DM5 は公式の「DM Series OSC Specifications V2.0.0」（UDP 49900、最大4台）。DM3 は「DM3 OSC Specifications V1.0.0」。どちらもフェーダーは「書く（set）」だけで、読み取りの方法は書かれていない | https://data.yamaha.com/files/download/other_assets/5/2234295/DM_osc_specs_V200_en.pdf ・ https://data.yamaha.com/files/download/other_assets/2/2063222/DM3_osc_specs_v100_en.pdf |
| 事実（非公式） | 同じ TCP 49280 で `get` すると今の高さが返り、卓の上でフェーダーを動かすと `NOTIFY set …` が届く（QL5 で確認したという報告）。DM7・DM7 Compact でも同じしくみが動くという報告 | https://github.com/samuelklsn/QLMix ・ https://github.com/vk0eppel/Yamaha-RCP-Chataigne-Module ・ https://github.com/watatatata810/Tools_DM7-ExternalMeter |
| 事実（非公式） | DM3 の一覧（Companion の部品）に `InCh` 16、`StInCh` 2（ST IN の L/R）がある | https://github.com/bitfocus/companion-module-yamaha-rcp |
| 事実 | 公式に高さを読めるのは MIDI だけ（QL：背面の MIDI 端子で NRPN か SysEx。DM3・DM7：USB-MIDI の Control Change） | QL5/QL1 リファレンスマニュアル V5.8 ・ DM7 シリーズ リファレンスマニュアル |
| 不明 | 同時につなげる数、つないでいる全員に NOTIFY が届くか、DM5 で読めるか、ST IN の L だけ動かすと R も動くか | 実機で確かめる |
| 事実（非公式） | QL5 では StageMix を同時に使っても困らなかった、DM7 では DM7 Editor と同時に使えた、という報告 | 上の QLMix、DM7 External Meter |

## しくみ

（2026-11-12 変更：両方の Mac が卓につながる形にした。承認待ち）

1. **両方の Mac が卓につながる**（TCP 49280）。動かすのは、止まっていない側（受信している側）の Mac だけ。メインの Mac は、メインでいる間は読むだけで動かさない。切り替えたあとに今のメインが止まっても、もう片方が同じように動かせる。
   - 卓の設定（機種・IP・割り当て・切り替え方・フェード）は、片方の Mac で変えるともう片方に自動で写す（Mac どうしのいつもの暗号化された回線で送る）。
   - 割り当ての表は役割ではなく Mac の名前で書く（「Main Stage Mac の Ch ⇄ Backup Stage Mac の Ch」）。止まった側の Ch を下げ、止まっていない側の Ch を上げる。
   - 不明：卓が同時に何台までつなげるか（TwinKeys 2台＋StageMix・Editor）。実機で確かめる。
2. つないだら、割り当てたメイン用チャンネルの高さを `get` で読み、そのあとは卓から届く `NOTIFY` で更新する。念のため数秒ごとに読み直す。つながりが切れないよう、決まった間隔で短い問い合わせを送る。
3. 切り替えのとき：
   - バックアップ用チャンネルを、メイン用チャンネルの**直前の高さ**まで上げる（フェード時間に合わせて少しずつ）。
   - 同時に、メイン用チャンネルを −∞ まで下げる（ON/OFF はさわらない）。
   - 動かしたあと、卓から読み直して、思った高さになったか確かめる。違ったら画面に出す。
4. **高さを読めないとき**（DM5 など、まだ確かめていない機種）：公式の OSC（UDP 49900）で、行ごとに決めた高さに上げる。接続の行に黄色で「高さは読めません：決めた高さに上げます」と出す。
5. 「卓を元に戻す」で逆向きに戻せる。
6. 切り替えの起こし方：
   - **確認してから（初期値）**：「この Mac をメインにする」の確認に「卓のフェーダーも切り替える」を付ける（iPhone からの切り替えでも同じ）。
   - **自動**：メインが 3 秒応答しないとき、すぐ切り替える。回線が一瞬切れただけでも動くおそれがあるため、選ぶときに注意を出す。

## 安全のための決めごと

- 動かすのはフェーダーの高さだけ。EQ・ダイナミクス・ルーティング・シーンにはさわらない。
- 卓とつながっていない・読んだ高さが古い（2 秒以上更新がない）ときは、自動の切り替えはしない。確認の画面では「卓は動かせません」と出し、Mac の切り替えだけ行う。
- 機種ごとの上限を超えるチャンネル番号は入れられない。
- 実機で確かめるまでは「試験的な機能」とし、初期状態はオフ。

## 作り方と確かめ方

- 卓の真似をする試験用の小さなサーバー（`get`・`set`・`NOTIFY` に答える）を作り、テストはそれで行う。
- 実機での確認項目を確認表に足す（つなぐ・高さを読む・卓のフェーダーを動かして追いかけるか・切り替え・元に戻す・回線を抜く・StageMix や Editor と同時に使う）。
- 実機で確かめられるのは、手元にある機種だけ。確かめた機種は表の「非公式」を「確認済み」に変える。

## 承認してほしいこと

1. 対応する機種と、読み書きの方法（上の表）
2. 高さを読めないときは「決めた高さに上げる」で動くこと
3. 設定と確認の画面（図 `mac-ql-dark`）
4. 実機で確かめるまで「試験的な機能」として出すこと
