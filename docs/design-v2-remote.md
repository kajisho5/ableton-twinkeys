# v2 設計書：iPhone から Live を操作する（TwinKeys Remote）

- 状態：**確認待ち**（この設計書と `docs/design/remote-*` の図を承認いただいてから実装）
- 作成日：2026-11-09
- 対象版：TwinKeys 2.0.0（Mac）＋ TwinKeys Remote 1.0（iPhone・iPad・iPhone Duo）
- ご指定：Live をほぼ丸ごと操作／iPhone アプリ（TestFlight・App Store）／合言葉＋iPhone ごとの許可

凡例：**[事実]** 一次情報で確認済み／**[推測]** 未確認（実装時に確認）

---

## 1. 目的

本番中に、ステージや客席から iPhone で Live を操作したい。今の TwinKeys の考え方（メインとバックアップの2台が、いつも同じ動きをする）は崩さない。

- iPhone で押した操作は、**メインの Mac とバックアップの Mac の両方の Live に、同時に同じ内容で届く**
- iPhone の画面には、メインの Live の状態（シーン名、再生中のクリップ、音量など）が出る
- 2台がずれていないか（届いたかの確認）も iPhone で分かる

## 2. 全体の仕組み

```
iPhone（TwinKeys Remote）
   │  暗号化した通信（同じネットワーク、Bonjour で見つける）
   ▼
メインの Mac：TwinKeys ──(今の2台の接続を使って転送)──▶ バックアップの Mac：TwinKeys
   │ この Mac の中だけの通信                                │ この Mac の中だけの通信
   ▼                                                      ▼
Live ＋ TwinKeys Live Bridge（Live の中で動く部品）        Live ＋ TwinKeys Live Bridge
```

- iPhone は**メインの Mac にだけ**つなぐ。メインが倒れたときは、iPhone から「バックアップに切り替える」を押すと、バックアップの Mac につなぎ直す
- 操作は「シーン 5 を再生」「トラック 3 の音量を 0.8 に」のような**中身のある命令**で送る。両方の Live は同じセットを開いている前提なので、同じ番号で同じものが動く
- メインの TwinKeys が受けた命令は、その Mac の Live に渡すのと同時に、今の2台の接続でバックアップに送る。バックアップも同じ命令を自分の Live に渡す。キューと同じく「届いた」の返事と送り直しをする

## 3. 決めたいこと：Live とつなぐ方法

Live を外から操作するには、Live の中で動く部品（Remote Script。Python で書く Live の拡張）が必要。**[事実]** Live 11 から Remote Script は Python 3。

| 観点 | A. AbletonOSC をそのまま使う | B. AbletonOSC を元に、TwinKeys 用に手を入れて同梱（おすすめ） | C. 自前で一から書く | D. Max for Live |
|---|---|---|---|---|
| できること | ほぼ全部（再生、テンポ、トラック、クリップ、シーン、デバイスの値、変化の通知） | A と同じ | 必要な分だけ | ほぼ全部 |
| 安全 | **同じネットワークの誰からでも操作できる**（全部の通信口で待ち受け、確認なし）。本番では使えない | この Mac の中（127.0.0.1）からだけ受け付ける。外からは TwinKeys が合言葉と許可で守る | B と同じにできる | 設計しだい |
| 作りやすさ | 入れるだけ | 小さな変更で済む | 大きい | Max の知識が要る |
| 必要なもの | Live 11 以降 | Live 11 以降 | Live 11 以降 | Live Suite か Max for Live |
| 将来性 | 外部の個人プロジェクトに依存 | 元の更新を取り込みつつ自分で直せる | 自分しだい | Live に依存 |
| AI での書きやすさ | — | 書きやすい（元のコードがある） | 普通 | 書きにくい |

**おすすめは B です。**
- AbletonOSC は MIT ライセンス。Live の操作をほぼ全部持っていて、2025-11-19 まで更新されています。**[事実]** https://github.com/ideoforms/AbletonOSC （LICENSE.md、最新コミット 2025-11-19）
- ただし初期設定では `0.0.0.0`（その Mac のすべての通信口）で待ち受け、確認なしで操作を受け付けます。**[事実]** `abletonosc/osc_server.py` 15〜38行
- 本番の Live を、同じ Wi‑Fi の誰でも操作できる状態は避けたいので、**この Mac の中からだけ受け付ける**ように変え、名前を「TwinKeys Live Bridge」として同梱します。ライセンス表記は残します

入れ方（両方の Mac で一度だけ）：
1. TwinKeys の「設定」>「Live との連携」>「Live に組み込む」を押す。TwinKeys が Live のユーザーライブラリの「Remote Scripts」フォルダへ Bridge をコピーする **[事実：場所は「ミュージック/Ableton/User Library/Remote Scripts」と AbletonOSC の説明にある。実機で確認]**
2. Live を再起動し、「環境設定」>「Link, Tempo & MIDI」の「コントロールサーフェス」で「TwinKeys Live Bridge」を選ぶ
3. TwinKeys の画面に「Live: 接続済み」と出れば完了

## 4. iPhone アプリの作り方

| 観点 | A. Swift＋SwiftUI のアプリ（ご指定・おすすめ） | B. Expo（React Native） | C. ブラウザで開く画面 |
|---|---|---|---|
| 動作の軽さ・反応 | 一番速い | 普通 | 普通（Safari の制約あり） |
| 配布 | TestFlight／App Store（runway で Mac なしでビルド・送信できる） | 同じ | 不要 |
| 近くの Mac を探す・暗号 | OS の機能をそのまま使える（Bonjour、CryptoKit）。Mac 版とコードを共有できる | 追加の部品が要る | 探せない（IP 入力） |
| 将来性 | Apple の標準 | 部品の更新に追われる | 機能が限られる |

**A（ご指定どおり）で作ります。** Mac 版の暗号・通信のコード（TwinKeysCore）をそのまま共有できるのが大きな理由です。

- 対応：**iPhone・iPad・iPhone Duo**（1つのアプリで全部）。iOS／iPadOS 17 以降 **[推測：最低版は実装時に見直す]**
- **iOS 27.1 SDK（Xcode 27.1）でビルド**する。iPhone Duo で画面いっぱいに表示し、開閉に合わせて形が変わるのは iOS 27.1 SDK 以降 **[事実]** https://developer.apple.com/iphone-duo/prepare/ （iOS 26 SDK 以前だと、開いたとき真ん中に小さく出るだけ）
- 2027年4月からは App Store への提出に iOS 27 SDK 以降が必要 **[事実：Apple の告知を報じた記事。Apple のページで実装時に再確認]**
- runway の TestFlight ワークフローは Xcode を `xcode` 入力で選べる（今の初期値は 26）。27.1 を指定する **[事実]** runway/.github/workflows/apple-testflight.yml。GitHub の Mac ランナーに Xcode 27.1 が入っているかは **[推測：実装時に確認]**
- ビルドと配布：kajisho5/runway の `apple-testflight.yml` を使う。Mac は不要。iPhone の GitHub アプリから実行できる **[事実]** runway/README.md
- Xcode のプロジェクトは XcodeGen 2.46.0 で設定ファイルから作る（Mac がなくても編集できるように）**[事実]** https://github.com/yonaskolb/XcodeGen （タグ 2.46.0）
- アプリ ID（案）：`io.github.kajisho5.twinkeys.remote`。名前（案）：TwinKeys Remote

### 4.1 画面の大きさへの対応（iPad・iPhone Duo）

iPhone Duo は閉じると 5.4 インチ、開くと 7.6 インチ（1878×2670 ピクセル）**[事実]** https://www.apple.com/iphone-duo/specs/ 。開閉したとき、アプリは止まらずにその場で形が変わる **[事実]** https://developer.apple.com/forums/thread/847644 。Apple は「機種や向き（iPhone か iPad か、縦か横か）で画面の作りを決めず、**今使える広さ**で決める」ように求めている **[事実]** https://developer.apple.com/iphone-duo/prepare/

そこで、**使える横幅だけ**で次の3つの形を切り替える（機種名では分けない）。

| 横幅 | 主な機種 | 形 |
|---|---|---|
| 狭い（〜599pt） | iPhone、閉じた iPhone Duo、Split View の iPad | 今の図どおり。下のタブで「セッション／ミキサー／キュー／設定」を切り替える |
| 中くらい（600〜999pt） | 開いた iPhone Duo、縦の iPad | 2列。左にセッション（シーン一覧＋クリップのます目を広く、8トラックまで）、右にキューと状態。ミキサーはタブ |
| 広い（1000pt〜） | 横の iPad | 3列。シーン一覧／クリップのます目／ミキサー（縦の細いフェーダー）。キューと状態は右上の小窓、オールノートオフは常に右下 |

- オールノートオフと本番ロックは、どの形でも常に見える場所に置く
- 開閉や回転、iPad で幅を変えたときも、押している途中の操作（フェーダーを動かしている最中など）は途切れさせない。形が変わる前に指を離したものとして扱い、最後の値を送る
- テストは Xcode 27.1 の iPhone Duo シミュレーターと、大きさを自由に変えられるシミュレーター（Device Hub）で、CI のスクリーンショットとして3つの形を毎回撮る **[事実：ツール名は上の Apple のページ]**
- App Store には iPhone Duo のスクリーンショットも出す（Duo 対応の印が付く）**[事実]** 同上

## 5. 安全（合言葉＋iPhone ごとの許可）

1. iPhone アプリで合言葉（Mac と同じ10文字）を入れる
2. iPhone が近くの TwinKeys を探して一覧に出す。メインの Mac を選ぶ
3. **Mac 側に「この iPhone を許可しますか？」と出る**。iPhone の名前と、両方に同じ4桁の確認番号を出すので、一致を見て「許可」を押す
4. 許可した iPhone は Mac に記録され、次からは自動でつながる。「設定」>「iPhone」で一覧・取り消しができる

- 通信は、合言葉から作った鍵と、iPhone ごとの鍵（iPhone の中で作り、外に出さない）の両方で守る。盗み見・なりすまし・再送は今の2台の接続と同じ考え方で防ぐ
- 許可していない端末、合言葉が違う端末からは何も操作できない
- バックアップの Mac も同じ iPhone の一覧を持つ（メインで許可すると、つながっているバックアップにも伝える）。メインが倒れて切り替えたときに、すぐ使えるようにするため

## 6. iPhone でできること（2.0 の範囲）

| 画面 | できること |
|---|---|
| セッション | シーンの一覧（名前・色・再生中）、シーンを再生、クリップのます目（トラック × シーン）でクリップを再生・トラックごとに停止、全クリップ停止 |
| ミキサー | トラックの音量・パン・ミュート・ソロ、マスター音量 |
| トランスポート（常に上に表示） | 再生／停止、テンポ（表示と変更）、今の拍 |
| キュー | TwinKeys のキューのキーをボタンで押す、オールノートオフ（赤） |
| 状態 | メインとバックアップの接続、2台の Live との接続、届いたかの確認、遅延 |

2.0 では**やらない**こと（必要なら 2.x で）：デバイスのつまみの操作、クリップの中身の編集、アレンジメント画面、録音、ブラウザ、プラグインの画面。

### 6.1 本番での安全装置

- **本番ロック**：画面の右上の鍵。ロック中は「再生・シーン・キュー・オールノートオフ」だけが押せ、音量やミュートなどは触れても変わらない。解除は長押し（1秒）
- 「全クリップ停止」「再生停止」は長押し（0.5秒）で実行（うっかり触れても止まらない）
- 押すと軽く振動して、押したことが手で分かる
- 音量などの連続した操作は、1秒に30回までに間引いて送る

## 7. 2台の Live をそろえる

- 命令は番号で送る（シーン 5、トラック 3）。**両方の Mac で同じセットを開いていることが前提**
- つないだとき、メインとバックアップの Live のセットを比べる（トラック数・シーン数・名前）。違うときは、Mac と iPhone の両方に「バックアップの Live のセットが違います（シーン数 24 と 23）」と黄色で出す
- 「届いたかの確認」はキューと同じ仕組み（返事・0.1 秒ごとの送り直し・0.3 秒で赤）。iPhone の画面にもバックアップの ✓ を出す
- 音量などは「最後の値」が届けばよいので、送り直しはせず、1秒ごとに今の値をそろえる

## 8. 画面（`docs/design/remote-*.svg`、ライト／ダーク）

| ファイル | 内容 |
|---|---|
| `remote-session-*` | iPhone：セッション（シーン一覧＋クリップのます目）。上にトランスポート、下にタブ |
| `remote-mixer-*` | iPhone：ミキサー |
| `remote-cues-*` | iPhone：キューと状態（2台の接続、届いたか） |
| `remote-pair-*` | iPhone：合言葉の入力と、Mac 側の「この iPhone を許可しますか？」 |
| `remote-duo-open-*` | 開いた iPhone Duo（中くらいの幅）：セッションとキューの2列 |
| `remote-ipad-*` | 横の iPad（広い幅）：シーン／ます目／ミキサーの3列 |

デザインの決まりは Mac 版と同じ色（青 #0060C7／#5AA9FF、赤のオールノートオフ）。押せる場所は最小 44×44pt（Apple の目安）**[推測：HIG の該当箇所は実装時に確認]**

## 9. 作るもの（予定）

- `Sources/TwinKeysCore/`：Remote の通信（命令の形、暗号、許可した iPhone の一覧）、Live の状態の型、2台への転送。Linux でテストする
- `Sources/TwinKeys/`：iPhone の待ち受け（Bonjour `_twinkeys-remote._tcp`）、許可のシート、Bridge との通信、設定の「Live との連携」「iPhone」
- `LiveBridge/`：Remote Script（AbletonOSC を元に変更。127.0.0.1 だけ、TwinKeys 用の命令を追加）
- `iOS/`：iPhone アプリ（SwiftUI、XcodeGen の設定ファイル、テスト）
- `.github/workflows/testflight.yml`：runway の TestFlight ワークフローを呼ぶ
- ドキュメント：使い方（Mac・iPhone）、README、手順書、サイトに「iPhone」のページ

## 10. あなたの操作が必要なこと（実装の途中でお願いします）

1. App Store Connect でアプリの記録を作る（https://appstoreconnect.apple.com/apps の「＋」>「新規 App」。手順は実装時に1つずつお伝えします）
2. runway の `repos.txt` にこのリポジトリがあるか確認（Mac 版の公証で登録済み。TestFlight 用の設定が足りなければお伝えします）
3. TestFlight の内部テストに自分を追加

## 11. 進め方（大きいので3回に分けて出す）

| 段階 | 中身 | 出し方 |
|---|---|---|
| 2.0 前半 | Live Bridge、Mac 側の命令の受け口と2台への転送、iPhone アプリ（セッション・トランスポート・キュー・状態）、安全（合言葉＋許可、本番ロック） | TestFlight |
| 2.0 後半 | ミキサー、セットの違いの検出、バックアップへの切り替え | TestFlight |
| 2.0 正式 | 実機で2台＋iPhone の確認後、Mac 版 2.0.0 と App Store 公開 | App Store |

## 12. 確認していただきたいこと

1. Live との連携は B（AbletonOSC を元に、Mac の中からだけ受け付ける形にして同梱）でよいか
2. 2.0 でできること（6章の表）と、やらないことの線引きでよいか
3. 本番ロック・長押しで止める、の安全装置でよいか
4. iPhone はメインの Mac にだけつなぎ、倒れたら手で「バックアップに切り替え」、でよいか
5. 図の画面でよいか
6. アプリ名「TwinKeys Remote」でよいか
7. iPad・iPhone Duo では、横幅に合わせて2列・3列に広げる形でよいか（図 `remote-duo-open-*`、`remote-ipad-*`）
