# App Store の文面（日本語）— TwinKeys Remote 1.2.0

App Store Connect（アップストア コネクト。App Store に出すための Apple のサイト）の「日本語」のページに貼る文面です。灰色の枠の中身を、そのままコピーして貼ってください。英語の文面は [metadata-en.md](metadata-en.md)、出し方の手順は [submit-steps.md](submit-steps.md) にあります。

- アプリ：TwinKeys Remote（バンドル ID `io.github.kajisho5.twinkeys.remote`）
- バージョン：1.2.0、iOS 17 以降、iPhone と iPad（Apple Watch アプリつき、watchOS 10 以降）
- 文字数は、この文面を作ったあとにプログラムで数えた数です（全角も半角も1文字）。キーワードだけは「バイト」で数えます（日本語の1文字は3バイト、英数字とカンマは1バイト）。

## 上限（Apple の公式ページで確かめたもの、2026年11月12日）

| 項目 | 上限 | 出典 |
|---|---|---|
| 名前 | 2〜30文字 | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) |
| サブタイトル | 30文字 | 同上 |
| プロモーション用テキスト | 170文字 | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| 説明 | 4000文字（HTML は使えない） | 同上 |
| キーワード | 100バイト。1語は3文字以上。アプリ名・会社名と同じ語は不要。ほかのアプリ名・会社名は禁止 | 同上 |
| このバージョンの新機能 | 4000文字。**最初のバージョンには出ない欄** | 同上 |
| App Review へのメモ | 4000バイト | 同上 |
| 名前の30文字、商標を詰め込まない、サブタイトルでほかのアプリにふれない | — | [App Review Guidelines 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) |

## 1. 名前（App Name）

上限 30文字 ・ 今の文字数 **15**

```text
TwinKeys Remote
```

英語と同じ名前にします。

## 2. サブタイトル（Subtitle）

上限 30文字 ・ 今の文字数 **22**

```text
2台の Mac を同時に操作する本番リモコン
```

Apple のルール（2.3.7）で、サブタイトルにはほかのアプリの名前を入れられないので、「Live」は入れていません。

## 3. プロモーション用テキスト（Promotional Text）

上限 170文字 ・ 今の文字数 **101**

```text
iPhone から、メインとバックアップの2台の Mac の Ableton Live を同時に操作。新しい「GO」画面では、Live のシーンの並びを台本にして、大きなボタン1つで本番を進められます。
```

この欄は、審査に出し直さなくても、あとからいつでも書き換えられます。

## 4. 説明（Description）

上限 4000文字 ・ 今の文字数 **1576**

```text
TwinKeys Remote は、2台の Mac（メインとバックアップ）で同じ Ableton Live のセットを動かして本番をする、音響オペレーターのためのリモコンです。iPhone・iPad で押した操作が、2台の Live に同時に届きます。メインの Mac が止まっても、バックアップがすぐに代われます。

TwinKeys Remote は、無料の Mac アプリ「TwinKeys」（macOS 13 以降）と組み合わせて使います。先に両方の Mac に TwinKeys を入れてください。TwinKeys がないと、このアプリだけでは何もできません。

■ 画面
・セッション：クリップのます目。押すとクリップを再生、空いたます目でそのトラックを停止、シーンごとの再生もできます。再生中のクリップには残り時間が出ます。
・ミキサー：音量、パン、ミュート、ソロ、Send A・Send B。列のどこをなぞっても動きます。点線が 0 dB です。
・キュー：メインの Mac のキューのキーと同じボタン。何をするか（Mac で書いたメモ）が大きく出ます。直前のキューと、バックアップに届いたかも分かります。
・GO：Live のシーンの並びを台本として使います。大きな「GO」で、選んでいるシーンを2台で再生して、次へ進みます。「前へ」「次へ」は選ぶだけで、鳴らしません。
・設定：本番の安全のための設定と、接続の状態。
・Apple Watch：GO、シーンを選ぶ、オールノートオフ。iPhone を通して動きます。

■ 本番のために
・上の帯に、つながりの状態、バックアップまでの遅れ、再生、停止、テンポ、位置、オールノートオフ。
・本番ロック：テンポとミキサーを動かなくします。止めるもの（クリップ・シーンの再生、停止、キュー）は選べます。GO とオールノートオフは止めません。
・「停止」と「全クリップ停止」は長押しで動きます。
・フェーダーを 0 dB より上げないようにできます。
・2台で違うセットを開いていると、警告が出ます。
・メインの Mac が止まったら、iPhone からバックアップの Mac に切り替えられます（1秒長押しで確認）。
・iPhone は横向きが基本です。iPad では画面が2列・3列に広がります。

■ 安全なつながり
・使うのは手元のネットワークだけです。インターネットとアカウントは要りません。
・iPhone には Mac と同じ合言葉を入れ、Mac で4桁の番号を確かめて、一度だけ許可します。
・通信はすべて暗号化しています。

■ 用意するもの
・TwinKeys 2.2 以降を入れた Mac 2台（TwinKeys は無料）
・両方の Mac に Ableton Live 11 か 12 と、Live 用の部品 TwinKeysBridge（TwinKeys から入れられます）
・iOS 17 以降の iPhone・iPad（Mac と同じネットワークにつなぎます）。Apple Watch は watchOS 10 以降

Mac がなくても、最初の画面の「サンプルで試す」で、架空のデータで画面を試せます。

■ プライバシー
データを一切集めません。アカウント、利用状況の分析、広告、アプリ内課金はありません。

TwinKeys Remote は無料のオープンソース（MIT License）で、Shogo Kajiyama / SEVENTHWELL が作っています。

TwinKeys は非公式のツールです。Ableton 社が作ったり、認めたり、サポートしたりしているものではありません。Ableton、Live は Ableton AG の商標です。
```

## 5. キーワード（Keywords）

上限 100バイト ・ 今のバイト数 **96**

```text
キュー,舞台音響,効果音,バックアップ,ミキサー,シーン,リモコン,MIDI,cue
```

- カンマで区切り、スペースは入れません（スペースもバイトに数えられるため）。
- 「TwinKeys」「Remote」は名前に入っているので入れていません（Apple の説明では、名前と会社名はもともと検索に使われます）。
- 「Ableton」「Live」は、ほかの会社・アプリの名前なので入れていません（キーワードでは禁止）。
- 1語3文字以上のルールがあるので、「音響」「演劇」「本番」のような2文字の語は避けました。

## 6. サポート URL（Support URL）

```text
https://kajisho5.github.io/ableton-twinkeys/ja/support/
```

## 7. マーケティング URL（Marketing URL、なくてもよい）

```text
https://kajisho5.github.io/ableton-twinkeys/ja/
```

## 8. プライバシーポリシー URL（Privacy Policy URL）

```text
https://kajisho5.github.io/ableton-twinkeys/ja/privacy/
```

サポートとプライバシーのページは、サイトの変更が GitHub の main に入って公開されてから開けるようになります。審査に出す前に、iPhone の Safari で3つの URL が開けるか確かめてください（開かない URL があると審査で断られます）。

## 9. カテゴリ（Category）

- メイン（Primary）：**ミュージック（Music）**
- サブ（Secondary）：**ユーティリティ（Utilities）**

理由：Apple の説明では、ミュージックは「音楽を演奏・録音・編集するアプリ」、ユーティリティの例に「リモコン」が入っています。([App Store categories](https://developer.apple.com/app-store/categories/))

## 10. 年齢制限（Age Rating）の答え

アプリ全体で1つです（日本語・英語で分けません）。「App 情報」の「年齢制限」で「設定」を押して答えます。([手順](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating) / [項目の一覧](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions))

| 質問のまとまり | 答え |
|---|---|
| アプリ内の制限（In-App Controls：Parental Controls、Age Assurance） | どれも選ばない |
| できること（Capabilities：Unrestricted Web Access、User-Generated Content、Social Media、Messaging and Chat、Advertising） | どれも「いいえ」 |
| 大人向けの話題（Mature Themes：Profanity or Crude Humor、Horror/Fear Themes、Alcohol, Tobacco, or Drug Use） | すべて「なし（None）」 |
| 医療・健康（Medical or Treatment Information、Health or Wellness Topics） | すべて「なし」 |
| 性的な内容（Mature or Suggestive Themes、Sexual Content or Nudity、Graphic Sexual Content） | すべて「なし」 |
| 暴力（Cartoon or Fantasy Violence、Realistic Violence、Prolonged Graphic Violence、Guns or Other Weapons） | すべて「なし」 |
| 運しだいのもの（Gambling、Simulated Gambling、Contests、Loot Boxes） | すべて「なし」または「いいえ」 |
| Age Categories and Override | Not Applicable（当てはまらない） |

これで **4+** になる見込みです。

メモ：画面に出るトラック名やメモは、その人が自分の Mac で付けたものです。ほかの人と共有する仕組み（投稿・チャットなど）はないので、User-Generated Content は「いいえ」にしています。

## 11. 著作権（Copyright）

```text
2026 Shogo Kajiyama / SEVENTHWELL
```

「©」は Apple が自動で付けるので、入れません。

## 12. このバージョンの新機能（What's New、1.2.0）

上限 4000文字 ・ 今の文字数 **274**

```text
・Apple Watch アプリ：GO、シーンを選ぶ、オールノートオフ。
・メインの Mac が止まったら、iPhone からバックアップの Mac に切り替えられるようにしました。
・押した操作がバックアップの Live でも動いたかを確かめて、動かなかったときに知らせます。
・本番ロックで止めるものを選べるようにしました。GO とオールノートオフは止めません。
・Mac がなくても「サンプルで試す」で画面を試せます。
・設定にプライバシーポリシーとサポートへのリンクを足しました。
両方の Mac に TwinKeys 2.2 が必要です。
```

**大事：** App Store で最初に出すバージョンには、この欄が出ません（Apple の説明：「最初のバージョンには使えず、2つ目以降は必須」）。TwinKeys Remote を App Store に出すのが今回はじめてなら、この文面は使わず、次のバージョンのときに使ってください。

## スクリーンショット

`docs/appstore/screenshots/` にあります。くわしくは [submit-steps.md](submit-steps.md) の「スクリーンショット」を見てください。画面の文字は英語（シーン名などは日本語）なので、日本語のページにも同じ画像を使います。
