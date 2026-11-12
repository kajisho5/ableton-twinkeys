# TwinKeys Remote 1.2.0 を App Store に出す手順（iPhone だけでできます）

iPhone の Safari で、App Store Connect（アップストア コネクト。App Store にアプリを出すための Apple のサイト）を使って出します。Mac は要りません。ビルド（アプリの本体）は、GitHub Actions がもう TestFlight に送ってあります。

- アプリ：TwinKeys Remote（`io.github.kajisho5.twinkeys.remote`）、バージョン 1.2.0、iOS 17 以降、iPhone と iPad（Apple Watch アプリつき）、無料
- 文面：[metadata-ja.md](metadata-ja.md)（日本語）、[metadata-en.md](metadata-en.md)（英語）
- プライバシーと暗号の答え：[compliance.md](compliance.md)
- スクリーンショット：`docs/appstore/screenshots/`
- かかる時間：入力に1〜2時間。審査はふつう1〜3日（Apple しだい）。

ボタンの名前は、Apple の説明（英語）の名前を先に書き、（ ）に日本語表示のときの名前の目安を書いています。日本語表示では少し違う言葉のこともあります。

---

## 0. 先にやっておくこと

### 0-1. サイトに2つのページを出す

App Store には、次の URL を書きます。審査の前に、iPhone の Safari で**全部開ける**ことを確かめてください（開かない URL があると断られます。ガイドライン 2.1）。

- プライバシーポリシー：<https://kajisho5.github.io/ableton-twinkeys/privacy/>（日本語 <https://kajisho5.github.io/ableton-twinkeys/ja/privacy/>）
- サポート：<https://kajisho5.github.io/ableton-twinkeys/support/>（日本語 <https://kajisho5.github.io/ableton-twinkeys/ja/support/>）
- マーケティング（サイトのトップ）：<https://kajisho5.github.io/ableton-twinkeys/>

ページのもとは `docs/privacy/`、`docs/support/` と `site/` にあります。GitHub の main に入ると、GitHub Actions の「Pages」が自動で公開します。

### 0-2. スクリーンショットを iPhone の「ファイル」に入れる

1. Safari で GitHub の `docs/appstore/screenshots/iphone/` を開きます（main に入ったあと）。
   <https://github.com/kajisho5/ableton-twinkeys/tree/main/docs/appstore/screenshots/iphone>
2. 画像を1つずつ開き、右上の「…」かダウンロードのボタン（Download raw file）を押して保存します。「ファイル」App の「ダウンロード」に入ります。
3. `ipad/` も同じようにします。<https://github.com/kajisho5/ableton-twinkeys/tree/main/docs/appstore/screenshots/ipad>
4. 「ファイル」App で、`iPhone用`・`iPad用` のようにフォルダを分けておくと、あとで選びやすくなります。

### 0-3. 文面をすぐコピーできるようにする

GitHub で `docs/appstore/metadata-ja.md` と `metadata-en.md` を開いておきます。灰色の枠を長押しして、中身をコピーします。

---

## 1. Safari で App Store Connect を開く

1. Safari で <https://appstoreconnect.apple.com/apps> を開き、Apple Account でサインインします。
2. 画面がせまくてボタンが見えないときは、**パソコン用の表示**にします：アドレスバーのページメニュー（「ぁあ」や「…」のボタン）→「**デスクトップ用 Web サイトを表示**」。
   同じメニューの「Web サイトの設定」で「デスクトップ用 Web サイトを表示」をオンにすると、次から自動でパソコン用になります。
3. 横向きにすると、表が見やすくなります。
4. 一覧から **TwinKeys Remote** を押します。左側（サイドバー）に、項目が並びます。

メモ：アプリのページの URL は `https://appstoreconnect.apple.com/apps/（番号）/...` の形です。この番号（Apple ID）は TwinKeys Remote ごとに決まっています。下に書く URL の形は目安で、変わることがあります。迷ったら、サイドバーから選んでください。

---

## 2. 契約と、EU の「トレーダー」の申告

1. <https://appstoreconnect.apple.com/business> を開きます（上の「Business（ビジネス）」）。
2. **無料のアプリだけなら、有料アプリの契約（Paid Apps Agreement）は要りません。** Apple の説明でも「契約がないときは無料でだけ出せる」となっています。
   出典：[Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)
3. 「Agreements（契約）」タブを下へ。「Compliance（コンプライアンス）」の「**Digital Services Act**」で「Complete Compliance Requirements」を押します。これは EU の法律（デジタルサービス法）の申告で、**EU で配らなくても全員が申告します**。
   - 仕事として（会社や屋号の事業として）配るなら「This is a trader account（トレーダー）」。住所・電話・メールの確認があり、その連絡先は EU の App Store のページに**公開されます**。
   - 仕事ではなく、個人として無料で配るだけなら「This is not a trader account（トレーダーではない）」。連絡先は要りません。
   - どちらに当たるかは、自分で決めることです（Apple は「自分で判断してください」と書いています）。SEVENTHWELL を事業として出すなら、トレーダーの可能性があります。迷ったら専門家に聞いてください。
   出典：[Manage EU Digital Services Act trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)

---

## 3. App 情報（App Information）

サイドバーの「General（一般）」→「**App Information（App 情報）**」。URL の目安：`https://appstoreconnect.apple.com/apps/（番号）/distribution/info`

1. **言語**：「Primary Language（主な言語）」は **English (U.S.)** がおすすめです（日本語・英語以外の国では、主な言語の文面が出るため）。日本語のページは、右上の言語のメニューから「日本語（Japanese）」を足します。
2. **名前**と**サブタイトル**：言語ごとに入れます（右上の言語のメニューで切り替え）。
   - 英語：metadata-en.md の 1・2
   - 日本語：metadata-ja.md の 1・2
3. **カテゴリ（Category）**：Primary（メイン）＝ **Music（ミュージック）**、Secondary（サブ）＝ **Utilities（ユーティリティ）**。
4. **コンテンツ配信権（Content Rights）**：「ほかの人の作品（音楽・映像など）を含んだり、見せたり、取ってきたりしますか」という質問には「**いいえ**」。画面に出るのは、その人自身の Live のセットの名前だけです。
5. **年齢制限（Age Ratings）**：「Set Up Age Ratings（設定）」を押し、metadata-ja.md の「10. 年齢制限」のとおりに、全部「なし」「いいえ」で答えます。最後に「Save」。**4+** になる見込みです。
   出典：[Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
6. **App のバンドル ID**（Bundle ID）が `io.github.kajisho5.twinkeys.remote` になっているか見ます（変えられません。見るだけ）。
7. **暗号の書類（App Encryption Documentation）**：何もしません。ビルドに「書類の要る暗号は使っていない」（`ITSAppUsesNonExemptEncryption = false`）と書いてあるので、質問は出ません（[compliance.md](compliance.md) の 2）。
8. 右上の「**Save（保存）**」。

---

## 4. 価格と配信状況（無料にする）

サイドバーの「Monetization」→「**Pricing and Availability（価格および配信状況）**」。URL の目安：`https://appstoreconnect.apple.com/apps/（番号）/distribution/pricing`

1. 「Price Schedule（価格表）」の「**Add Pricing（価格を追加）**」を押します。
2. 基準の国（base country or region）を選びます（日本でかまいません）。
3. 価格で **Free（無料、0円）** を選び、「Next」。
4. ほかの国の価格の画面は、そのまま「Next」。
5. 確かめて「**Confirm（確定）**」。
6. 「App Availability（配信状況）」で、配る国を選びます（ふつうは全部の国）。
   出典：[Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)

---

## 5. App のプライバシー（App Privacy）

サイドバーの「**App Privacy（App のプライバシー）**」。URL の目安：`https://appstoreconnect.apple.com/apps/（番号）/distribution/privacy`

1. 「Privacy Policy（プライバシーポリシー）」の「Edit」を押し、URL を入れて「Save」。言語ごとに入れられます。
   - English (U.S.)：`https://kajisho5.github.io/ableton-twinkeys/privacy/`
   - 日本語：`https://kajisho5.github.io/ableton-twinkeys/ja/privacy/`
   - 「User Privacy Choices URL」は空のままでかまいません。
2. 右の「**Get Started（始める）**」を押します。
3. 「**No, we do not collect data from this app**（いいえ、このアプリからデータを収集していません）」を選び、「Save」。
4. 右上の「**Publish（公開）**」→ 確認でもう一度「Publish」。
5. 下の「Product Page Preview」に「**Data Not Collected（データの収集なし）**」と出れば完了です。
   出典：[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

---

## 6. バージョンのページ（1.2.0）

サイドバーの「iOS App」の下のバージョン（「1.0 Prepare for Submission（提出準備中）」など）を押します。URL の目安：`https://appstoreconnect.apple.com/apps/（番号）/distribution/ios/version/inflight`

### 6-1. バージョン番号

「Version（バージョン）」を **1.2.0** にします。ビルドのバージョン（1.2.0）と同じでないと、ビルドを選べません。

### 6-2. スクリーンショット

「App Previews and Screenshots（App プレビューとスクリーンショット）」で、端末のタブを選び、「Upload（アップロード）」の場所を押して「**ファイルを選択**」→「ファイル」App から選びます。何枚かまとめて選べます。並びはドラッグで直せます（「View All Sizes in Media Manager」でも直せます）。
出典：[Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)

**必要なサイズ**（Apple の [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)、2026年11月12日に確認）：

- iPhone：「**iPhone with Dynamic Island (medium display)**」（6.3インチ。iPhone 17 Pro など）が必須。1枚以上。横 2622×1206 か、縦 1206×2622 など。
- iPad：「**iPad 13-inch display**」が必須（iPad で使えるアプリなので）。1枚以上。縦 2064×2752 か、横 2752×2064 など。
- Apple Watch：「**Required for Apple Watch apps**」（Watch アプリが入っているので必須）。422×514、416×496、396×484 などのどれか1つ。**すべての言語で同じサイズ**にすること。
- 1つのサイズに 1〜10枚。PNG か JPEG。透明な部分（アルファチャンネル）はだめ。
- 大きいサイズから小さいサイズへは、Apple が自動で縮めてくれます。

**用意した画像**（すべてダークモード、文字の書き足しなし。CI のデモ画面を、上のサイズちょうどに直したもの）：

| 端末 | フォルダ | 画像（この順で） | サイズ |
|---|---|---|---|
| iPhone 6.3インチ | `screenshots/iphone/` | 01-session-landscape、02-go-landscape、03-mixer-landscape、04-cues-landscape、05-set-check-landscape（横向き）、06-cues-portrait（縦向き） | 横 2622×1206、縦 1206×2622 |
| iPad 13インチ | `screenshots/ipad/` | 01-overview-portrait、02-go-portrait、03-set-check-portrait | 縦 2064×2752 |
| iPhone 6.9インチ（予備） | `screenshots/iphone-6.9/` | iphone/ と同じ6枚 | 横 2868×1320、縦 1320×2868 |

- iPhone のアプリは横向きが基本なので、横向きを先にしています。
- 06（縦向き）：Apple のページは、横と縦を混ぜてよいかを書いていません。断られたら 06 は外してください。
- iPad の画像は、CI のデモでは横向きの撮影ができていなかったので、縦向きだけです。
- `iphone-6.9/` は、App Store Connect が「iPhone 6.9インチ（Dynamic Island, large display）」も求めてきたときだけ使います（Apple のページで、必須は 6.3インチだけ）。6.3インチの画像を少し（約9%）拡大したものです。
- 画面の文字は英語（シーン名などは日本語）です。日本語のページにも同じ画像を入れてください。右上の言語のメニューで日本語に切り替えて、同じようにアップロードします（入れないときは主な言語の画像が使われます）。
- 画像の中の Mac の名前（Main Stage Mac など）やシーン名は、デモ用の架空のものです。
- Apple Watch の画像は、CI が撮ったもの（`Apple-Watch-go-en.png` など、GO・シーン・全ノートオフ × 英語・日本語）を使います。CI の結果の「ios-screenshots」に入ります。どのサイズで撮れたかは画像で確かめてから、App Store Connect の Apple Watch の欄に入れてください。

### 6-3. 文面（英語と日本語）

右上の言語のメニューで切り替えて、それぞれ入れます。

| 欄 | 英語 | 日本語 |
|---|---|---|
| Promotional Text（プロモーション用テキスト） | metadata-en.md の 3 | metadata-ja.md の 3 |
| Description（概要・説明） | en の 4 | ja の 4 |
| Keywords（キーワード） | en の 5 | ja の 5 |
| Support URL（サポート URL） | en の 6 | ja の 6 |
| Marketing URL（マーケティング URL） | en の 7 | ja の 7 |
| What's New（このバージョンの新機能） | en の 10 | ja の 12 |

- 「What's New」は、App Store で最初に出すバージョンには**欄が出ません**。出なければ飛ばします。
- 「Copyright（著作権）」は言語に関係なく1つ：`2026 Shogo Kajiyama / SEVENTHWELL`

### 6-4. ビルドを選ぶ

1. 下の「**Build（ビルド）**」の「＋」を押します。
2. 一覧から、バージョン **1.2.0** のビルドのうち、TestFlight で試していちばん新しいもの（`iOS/testflight-request.txt` のいちばん下の行）を選んで「Done」。番号は TestFlight の画面で確かめてください。
3. 右上の「Save」。
   - ビルドに「Missing Compliance（コンプライアンス情報がありません）」と出たら、暗号の質問に答えます（[compliance.md](compliance.md) の 2 の推測 5）。ふつうは出ません。
   出典：[Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)

### 6-5. App Review に関する情報（App Review Information）

審査をする Apple の人（審査担当）だけが読む欄です。お客さんには見えません。

1. **Sign-in required（サインインが必要）**：**オフ**（アカウントがないため）。
2. **Contact Information（連絡先）**：自分の名前、メール、電話番号。電話は `+81` から始めます（例：`+81 90 1234 5678` のように、最初の 0 を取る）。数字だけだと受け付けません。
3. **Notes（メモ）**：下の英語の文を、そのまま貼ります（2569バイト。上限は4000バイト）。
4. **Attachment（添付）**：画面の動画があれば、ここに付けます（下の「Mac がないときの選択肢」）。

```text
TwinKeys Remote is a remote control for TwinKeys, a free, open-source Mac app for theatre and concert sound operators (source and downloads: https://github.com/kajisho5/ableton-twinkeys). It controls Ableton Live on a main Mac and a backup Mac at the same time, over the local network only.

IMPORTANT: the app needs a Mac to do anything.
- It works only with a Mac running TwinKeys 2.2 or later and Ableton Live 11 or 12, on the same local network as the iPhone or iPad.
- WITHOUT A MAC: tap "Try with sample data" on the first screen. Every screen then works with fictional sample data, "· Sample" is shown in the top bar, and nothing is sent anywhere. The Apple Watch app shows the same sample data. To leave, open Settings and tap "End the sample and connect to a Mac".
- One Mac is enough to try every screen. The backup Mac is optional.
- There is no account and no sign-in.

Setup (about 10 minutes):
1. On a Mac with Ableton Live 11 or 12, download TwinKeys (notarized) from https://github.com/kajisho5/ableton-twinkeys/releases/latest, open it and allow Local Network access.
2. In TwinKeys Settings > Live, click "Install into Live". Restart Live. In Live's Settings > Link, Tempo & MIDI, choose "TwinKeysBridge" in a free Control Surface slot. TwinKeys Settings then shows "Live: Connected".
3. In TwinKeys Settings > Pairing Code, click "Make New Code" and note the 10-character code.
4. In TwinKeys Settings, turn on "Allow TwinKeys Remote to connect".
5. In TwinKeys Remote, type the same code and tap Save. Allow Local Network access. Tap "Connect" next to the Mac.
6. The iPhone and the Mac show the same 4 digits. Click "Allow" on the Mac.

Screens: Session (clip grid: launch clips and scenes), Mixer (volume, pan, mute, solo, sends), Cues (the Mac's cue keys), GO (launches the scene selected in Live and selects the next one), Settings (show lock and what it stops, 0 dB fader cap, privacy policy and support links).
Apple Watch app: GO, choose scene and All Notes Off. It talks only to the iPhone app (WatchConnectivity), never to the Macs.
Full guide: https://kajisho5.github.io/ableton-twinkeys/guide/#controlling-live-from-an-iphone-or-ipad-twinkeys-remote

Network and privacy: the app connects only to TwinKeys on the user's own Macs (Bonjour service _twinkeys-remote._tcp, then TCP). It does not connect to the internet and collects no data. The connection is encrypted with Apple CryptoKit.

TwinKeys is an unofficial tool, not affiliated with or endorsed by Ableton. "Ableton" and "Live" are named only to say which software it works with.
```

動画を付けたときは、上の文の「Full guide: …」の行のあとに、どちらか1行を足します（本当のことだけを書きます）。

- 本物の Mac につないで撮った動画のとき：
  `A short screen recording of the app connected to TwinKeys on a Mac is attached.`
- 「サンプルで試す」の画面を撮った動画のとき：
  `The attached video shows "Try with sample data" (fictional data). It is not a real connection to a Mac.`

**日本語の意味（メモの中身）：** このアプリは Mac の TwinKeys（無料・オープンソース）のリモコンで、Mac がないと何もできないこと。1台の Mac で全部の画面を試せること。アカウントはないこと。Mac の準備（6手順、約10分）。Mac がないときは、最初の画面の「サンプルで試す」で全部の画面（Apple Watch も）を架空のデータで試せること。画面の説明。通信は自分の Mac とだけで、データは集めないこと。Ableton 社とは関係ないこと。

### 6-6. 出し方（Version Release）

「**Manually release this version（手動でリリース）**」がおすすめです。審査に通ったあと、自分で「リリース」を押した時に App Store に出ます。

最後に右上の「**Save（保存）**」。

---

## 7. 審査に出す

1. バージョンのページの右上の「**Add for Review（審査用に追加）**」を押します。新しい提出（submission）を作る方を選びます。状態が「Ready for Review（審査準備完了）」になります。**まだ Apple には届いていません。**
2. 右下の「Draft Submissions（下書き）」か、サイドバーの「App Review」で、提出の中身を確かめます。
3. 「**Submit for Review（審査へ提出）**」を押します。審査が始まると「In Review（審査中）」になります。
   出典：[Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

足りない欄があると、赤い字で教えてくれます。そこを直してから、もう一度押してください。

---

## 8. 審査のあと

- 通ったら：「Pending Developer Release（デベロッパのリリース待ち）」になります。バージョンのページで「Release This Version（このバージョンをリリース）」を押すと、App Store に出ます。
- 質問や断りが来たら：サイドバーの「App Review」のメッセージに届きます（メールでも知らせが来ます）。英語で返事ができます。断られても、直して出し直せます。
- 「Mac がないので試せない」と言われたら：下の「Mac がないときの選択肢」を見てください。

---

## 9. 審査で問題になりそうなこと（先に知っておくこと）

App Review Guidelines（審査のルール。最終更新 2026年10月16日）と、Apple の審査のページで確かめました。

1. **審査担当が試せない**（いちばん大きい心配）
   - ルール：「審査担当がアプリを全部使えるようにすること。アカウントがあるならデモ用アカウントか、全部の機能が使えるデモの画面を。**審査に要る機材**も用意すること」（Before You Submit）。
   - Apple の審査のページ：「**特別な機材が要る機能は、デモ動画か、その機材を出せるようにしておくこと**」。
   - TwinKeys Remote は、Mac と Live がないと本当の操作はできません。審査担当が Mac を用意してくれるとは限りません。
   - 1.2.0 から、最初の画面の「サンプルで試す」で、Mac なしで全部の画面を試せます（審査用メモにも書いています）。
   - 出典：[Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) / [App Review（Providing information for a complete review）](https://developer.apple.com/distribute/app-review/) / [ガイドライン 2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness)
2. **ほかのアプリがないと動かない**
   - ルール 4.2.3(i)：「アプリは、**ほかのアプリを入れなくても単独で動く**こと」。
   - Mac のアプリと組むリモコンのアプリは App Store にたくさんありますが、このルールを理由に聞かれる可能性はあります。そのときは「Mac のソフトのリモコンで、Mac 側は無料で公開している」と返事します。
   - 出典：[ガイドライン 4.2.3](https://developer.apple.com/app-store/review/guidelines/#4.2.3)
3. **アプリの中にプライバシーポリシーのリンクがない**
   - ルール 5.1.1(i)：「プライバシーポリシーへのリンクを、App Store Connect の欄と、**アプリの中の分かりやすい場所**の両方に入れること」。
   - 1.2.0 で「設定」の「このアプリについて」に、プライバシーポリシーとサポートへのリンクを足しました（解決済み）。
   - 出典：[ガイドライン 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
4. **「Ableton」「Live」の名前**
   - ルール 2.3.7：メタデータに商標を詰め込まない。サブタイトルでほかのアプリにふれない。キーワードにほかの会社・アプリの名前は入れない。ルール 5.2.1：ほかの人の商標を許可なく使わない。
   - 名前・サブタイトル・キーワードには入れず、説明の中で「どのソフトと使えるか」を言うためだけに使い、「非公式・関係ない」と書きました。それでも許可を見せるよう求められる可能性はあります（Apple の審査のページ：「ほかの会社の商標を出すなら、その許可を出すこと」）。
   - 出典：[ガイドライン 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) / [5.2.1](https://developer.apple.com/app-store/review/guidelines/#5.2.1)
5. **プライバシーマニフェスト**：アプリの中に、Apple が求める「API を使う理由の申告ファイル」（PrivacyInfo.xcprivacy）がありません。Apple から「ITMS-91053」のメールが来ていたら、次のビルドで足す必要があります（[compliance.md](compliance.md)）。

### Mac がないときの選択肢

本当のことだけを書いてください。審査担当に「試せるふり」はしないでください。

- **A. Mac を持っている人に、つないだ画面を録画してもらう**（いちばん確実）。iPhone の「画面収録」で、Mac につないで各画面を動かすところを1〜2分撮り、「Attachment（添付）」に付けます。
- **B. シミュレーターのデモ画面を録画する**。今のスクリーンショットと同じく GitHub Actions のシミュレーターで、`-demo` で起動して録画できます（CI に録画の手順を足す必要があります）。メモには「シミュレーターのデモ（架空のデータ）で、本物の接続ではない」と書きます。
- **C. 次のビルドで、アプリの中からデモを開けるようにする**（例：合言葉の画面に「デモを見る」ボタン）。審査担当が自分で全部の画面を試せるので、いちばん通りやすくなります。ただしアプリの変更と新しいビルドが要ります。
- 何も付けずに出すこともできます。そのときは、メモのとおり「審査には Mac と Live が要る」ことを正直に伝え、質問が来たら A〜C で答えます。

---

## 10. 出典（すべて 2026年11月12日に確認）

- 名前・サブタイトルの上限：<https://developer.apple.com/help/app-store-connect/reference/app-information/app-information>
- 説明・キーワード・プロモーション用テキスト・新機能・審査メモの上限：<https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information>
- スクリーンショットのサイズ：<https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>
- スクリーンショットのアップロード：<https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>
- 年齢制限：<https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating>、<https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions>
- App のプライバシー：<https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy>、<https://developer.apple.com/app-store/app-privacy-details/>
- 価格：<https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price>
- ビルドを選ぶ：<https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit>
- 審査に出す：<https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app>
- EU のトレーダー：<https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements>
- カテゴリ：<https://developer.apple.com/app-store/categories/>
- 審査のルール：<https://developer.apple.com/app-store/review/guidelines/>
- 審査に要る情報（機材・デモ動画）：<https://developer.apple.com/distribute/app-review/>
- 暗号：[compliance.md](compliance.md) の出典
