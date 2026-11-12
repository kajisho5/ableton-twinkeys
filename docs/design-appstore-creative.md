# App Store の「ヘッダ」と「検索結果」の画像・動画（TwinKeys Remote）

2026-11-12。デザイン案：`docs/design/appstore-header-*.png`、`appstore-header-storyboard-*.png`、`appstore-search-*.png`（日本語・英語）。絵はすべて `design/appstore-creative/make.py` 1つから作ります（案と完成品が同じ絵になる）。

## 1. Apple の仕様（事実。2026-11-12 に公式ページで確認）

- App Store Connect のバージョンのページ →「Product Page Information」→「**Header and Search Results**」タブで入れる「Creative assets（クリエイティブアセット）」。スクリーンショット・App プレビューとは**別もの**で、入れなくてもかまわない。
  出典：<https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>
- 表示されるのは **iOS 27・iPadOS 27 以降**の App Store。それより前の iOS では、今までどおりスクリーンショットが出る。
  出典：<https://developer.apple.com/app-store/asset-best-practices/>
- 大きさ（出典：<https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications>）

| 置き場所 | 画像 | 動画 |
|---|---|---|
| ヘッダ（商品ページのいちばん上） | 21:9・3840×1646（jpg/png） | 21:9・3840×1646・30 または 60 fps・**5〜30 秒**・mov/m4v/mp4 |
| 検索結果 | 3:2・1920×1280〜3840×2560（jpg/png） | 3:2・同じ大きさ・5〜30 秒 |
| 両方に使える「ユニバーサル」 | 16:9・5244×2950（png） | — |

- 画像に透明（アルファ）は使えない。動画は**音なしで流れて、くり返す**（検索結果では音を出せない）。
- Apple の決まり（同じ出典 asset-best-practices）：値段・割引・**Web の URL・©マーク**を入れない／ほかのプラットフォームやストアのロゴを入れない／4+ の内容にする／文字は短く、**アプリの全部の言語に合わせる**（日本語と英語）／大事なものは真ん中に（端は切れることがある）／動画のつなぎ目が目立たないループにする。
- 審査がある。いまのバージョン（1.2.1）と一緒に出すか、あとから「Asset Library」で**アセットだけ**出せる（アプリの更新は要らない）。

## 2. 作るもの

| 置き場所 | 種類 | 中身 |
|---|---|---|
| ヘッダ | **動画 15 秒（ループ）**、日本語版・英語版 | 下の絵コンテ。最初のコマ（ポスター）は画像でも出す |
| 検索結果 | **画像**、日本語版・英語版 | 見出し＋アプリの GO 画面＋Watch＋2台の Mac |

検索結果を動画でなく画像にした理由：Apple は検索結果について「何のアプリか一目でわかるように」「アプリの画面を見せる」と書いている。小さく出るので、動かない絵のほうが読める（推測）。

## 3. ヘッダ動画の絵コンテ（15 秒・30 fps）

| 時間 | 画面 | 下の一言（日本語／英語） |
|---|---|---|
| 0〜2.4 秒 | GO の画面。Watch と2台の Mac が線でつながっている（サイトのデモと同じコの字） | GO を1回。メインとバックアップの Mac が同時に再生／One GO plays on the main and the backup Mac at once |
| 2.4〜5.6 秒 | GO を押す → 光が線を通って**2台に同時に**届く → 2台とも次のシーンが緑に | （同じ） |
| 5.6〜10.6 秒 | メインの Mac が赤く「応答なし」→ iPhone の上に赤い帯 →「長押しで切り替え」が1秒でいっぱいになる | メインの Mac が止まっても／If the main Mac stops… |
| 10.6〜15 秒 | バックアップが「メインに切り替え」。最後に暗くなって最初のコマに戻る（ループ） | iPhone からバックアップに切り替えて、そのまま続行／…switch to the backup from your iPhone and carry on |

見出し（ずっと同じ）：日本語「本番を、止めない。」／英語「Keep the show running.」
画面の中身は、アプリの実際の画面（GO・切り替え）と同じ並び・色・文言で描く。

## 4. 色・文字

- 背景：アイコンと同じ紺のグラデーション（#18223A → #06090F）。緑 #4CD366（GO・つながっている）、赤 #C62A20（止まった）、黄 #F5B83D（バックアップがメイン）。
- 文字：Noto Sans CJK JP（日本語・英語とも）。TwinKeys は自作ツールなので、SEVENTHWELL の書体の決まりは使わない。

## 5. 作り方（技術）

- Python 3（標準ライブラリだけ）で SVG を書き、rsvg-convert（librsvg 2.58）で PNG に、ffmpeg（6.1）で動画（H.264・30 fps・約 12 Mbps・無音のステレオ AAC を付ける）にする。理由：アイコン（`design/icon/make-icons.py`）と同じ道具で、新しく入れるものがない。
- 完成品の置き場所：`deliverables/appstore-creative/`（GitHub の Actions の成果物としても渡す）。

## 6. 入れ方（iPhone の Safari）

App Store Connect API でこのアセットを送れるかは、**確認できていない**（API の説明に見つからない）。なので手で入れる：

1. ファイルを iPhone の「ファイル」に保存する（私が送る）。
2. <https://appstoreconnect.apple.com/apps/6832469018/distribution/ios/version/inflight> →「Product Page Information」→「Header and Search Results」→「Header」→ 動画を選ぶ →「Save」。「Search Results」も同じように画像を選ぶ。
3. 右上の言語を「日本語」に変えて、日本語版も同じように入れる。
4. 「Preview」で、iPhone・iPad での見え方を確かめる。

## 7. 決まったこと（2026-11-12）

- このデザインで作る（承認：「それでいいよ」）。完成品：`deliverables/appstore-creative/`
  - `header-{ja,en}-3840x1646-15s.mp4`（H.264 High・30 fps・15.0 秒・無音のステレオ AAC）
  - `search-results-{ja,en}-3840x2560.png`（透明なし）、`header-poster-{ja,en}-3840x1646.png`（動画の最初のコマ）
- 出す順番は「アプリを先に、アセットはあとから単独で」を選んだ。ただし Apple の説明では、**承認されたバージョンがまだないアプリは、最初のバージョンと同じ提出に入れる**必要がある（「If your app doesn't yet have an approved version, include the asset in the same submission as your first app version.」）。TwinKeys Remote は 1.2.1 が最初の App Store 版なので：
  - まだ審査に出していないなら → 1.2.1 の版のページで入れて、一緒に出す。
  - もう出したなら → 1.2.1 が承認されたあと、Asset Library から単独で出す（アプリの更新は要らない）。
  出典：<https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-assets-from-asset-library>

## 8. わからないこと


- Apple のテンプレートにある「セーフエリア」（切れない範囲）の正確な数字。テンプレートは Figma などのファイルで、ここでは開けていない。なので大事なものを真ん中寄りに置き、App Store Connect の「Preview」で確かめる。
