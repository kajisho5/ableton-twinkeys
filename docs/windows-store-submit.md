# TwinKeys for Windows を Microsoft Store に出す手順（iPhone だけでできます）

Windows の PC がなくても、iPhone の Safari だけで進められるように書いています。アプリの本体（MSIX）は GitHub Actions が作ります。

印の意味：**【事実】** Microsoft の公式の説明や、このリポジトリで確かめたこと。**【推測】** 確かめていないが、たぶんそうなること。**【不明】** 分からないこと。

> **大事なこと**：Windows 版は、まだ**本物の Windows PC で試していない試験版**です【事実】（CI の Windows でビルド・起動・インストールを確かめただけ）。審査に出すときは、下の 7 で「自分で『今すぐ公開』を押すまで公開しない」を選んでおくと、合格しても勝手に公開されません【事実】。

---

## 0. 先にあるとよいもの

| もの | どこで | 印 |
|---|---|---|
| Microsoft の開発者アカウント（個人は無料。身分証と自撮りで本人確認） | https://storedeveloper.microsoft.com （ここが今の唯一の登録の入口） | 【事実】https://learn.microsoft.com/windows/apps/publish/prepare-developer-account |
| 本人確認にかかる時間 | 自動なら数分。人の確認に回ると 2〜5 営業日 | 【事実】同上 |
| iPhone で GitHub にログインしていること | 成果物（アーティファクト）のダウンロードに必要 | 【事実】GitHub の成果物はログインした人だけが落とせる |

- 個人のアカウントは、あとで会社のアカウントに変えられません【事実】（同上）。SEVENTHWELL の名前で出したいときは、どちらで登録するか先に決めてください。

---

## 1. 名前「TwinKeys」を予約する

1. iPhone の Safari で https://aka.ms/submitwindowsapp を開きます（Partner Center の「アプリとゲーム」）【事実】。
2. **New product**（新しい製品）→ **MSIX or PWA app** を押します【事実】。
3. 名前に `TwinKeys` と入れて **Check availability**（利用可能か確認）→ 緑のチェックが出たら **Reserve product name**（製品名の予約）を押します【事実】。
   - 予約は 3 か月で消えます。3 か月以内に提出してください【事実】。
   - 「TwinKeys」が取れなかったときは、別の名前（例：`TwinKeys for Windows`）を予約し、Claude に伝えてください。アプリの中の表示名（`Package.appxmanifest` の DisplayName）も合わせる必要があります【事実】。

出典：https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/reserve-your-apps-name

---

## 2. 「製品 ID」の3つの値を写す

1. 予約したアプリの画面で、左のメニューの **Product management**（製品管理）を開き、**Product identity**（製品 ID）を押します【事実】。日本語の画面では「製品管理」→「製品 ID」のような名前です【推測】。
2. 次の 3 つの値を、**一文字も変えずに**写します（大文字・小文字・点・空白も同じに）【事実】。

| Partner Center の欄 | 例の形 | 入れる場所（`windows/StoreIdentity.props`） |
|---|---|---|
| **Package/Identity/Name** | `12345SEVENTHWELL.TwinKeys` のような形 | `StoreIdentityName` |
| **Package/Identity/Publisher** | `CN=` で始まる長い文字（英数字とハイフン） | `StoreIdentityPublisher` |
| **Package/Properties/PublisherDisplayName** | アカウントの表示名 | `StorePublisherDisplayName` |

- 例の形は【推測】です。実際の値は画面に出たものを使ってください。
- 出典：https://learn.microsoft.com/windows/apps/publish/view-app-identity-details

### 値の入れ方（どちらか）

- **いちばん簡単**：3 つの値をそのまま Claude に送ってください（「TwinKeys の製品 ID：Name は…、Publisher は…、PublisherDisplayName は…」）。Claude が `windows/StoreIdentity.props` を書き換えます。これらは秘密の値ではありません（Store に出たアプリの中にも入る値です）【事実】。
- **自分で入れる**：GitHub のアプリか Safari で `windows/StoreIdentity.props` を開き、鉛筆のボタン（編集）で `REPLACE-ME` の 3 か所を置き換えて保存（Commit）します。ほかの場所は変えなくて大丈夫です。

値を入れて push すると、GitHub Actions の「Windows」が自動で動き、新しい MSIX を作ります【事実】（`windows/**` が変わると動く設定）。`REPLACE-ME` のままだと、CI は黄色い注意を出し、Partner Center はその MSIX を受け付けません【事実】（製品 ID と一致しないため）。

---

## 3. iPhone で .msixupload をダウンロードする

1. Safari で https://github.com/kajisho5/ableton-twinkeys/actions/workflows/windows.yml を開きます。
2. 一番上の、緑のチェックの付いた実行（値を入れたあとのもの）を開きます。
3. 下の **Artifacts**（成果物）に並ぶ中から、**`TwinKeys-1.0.<番号>.0.msixupload`** を押します。zip ではなく、そのままのファイルが落ちてきます【事実】（CI で `archive: false` にしています）。
   - スマホ向けの画面で Artifacts が見えないときは、Safari の「ぁあ」→「デスクトップ用Webサイトを表示」にします【推測】。
   - 保存先は「ファイル」アプリの「ダウンロード」です【推測】。
4. 成果物は、GitHub の設定で決まった日数（ふつう 90 日）が過ぎると消えます【事実】。消えていたら、もう一度 CI を動かしてください（Claude に頼めます）。

ほかの成果物（参考）：

| 名前 | 中身 |
|---|---|
| `TwinKeys-1.0.<番号>.0.msixupload` | **Store に出すのはこれ**。x64 と ARM64 を1つにした束（バンドル）が入っている |
| `TwinKeys-1.0.<番号>.0.msixbundle` | 同じ束そのもの。Partner Center はこれも受け付けます【事実】 |
| `TwinKeys-MSIX-x64` / `TwinKeys-MSIX-arm64` | アーキテクチャごとの .msix（zip に入っている） |
| `TwinKeys-WACK-x64` / `-arm64` | Windows App Certification Kit（WACK）の結果 |
| `TwinKeys-Screenshot-x64` / `-arm64` | CI の画面の写真（Store のスクリーンショットの材料。下の 5） |
| `TwinKeys-Windows-x64` / `-arm64` | 今までどおりの ZIP 版（Store には使わない） |

- **パッケージの版**は `1.0.<CI の実行番号>.0` です【事実】。Store は「4つの数字、最初は 0 以外、最後は 0、更新のたびに大きく」と決めているためです【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-package-requirements）。アプリの中の版（0.2.0）とは別です。
- 署名はしていません。Store が自分の証明書で署名し直すので、署名は要りません【事実】（同上）。

---

## 4. 提出を始めて、パッケージを上げる

1. Partner Center でアプリを開き、**Start submission**（提出の開始）を押します【事実】。
2. **Packages**（パッケージ）を開き、3 の `.msixupload` を「ファイル」から選んで上げます【事実】。.msixupload を上げるのがおすすめと書かれています【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/upload-app-packages）。
   - iPhone の Safari から数十〜百数十 MB のファイルを上げられるかは【不明】。途中で止まるときは、Wi-Fi で、画面を消さずに待ってください。
   - 「名前が予約した名前と違う」「ID が違う」と出たら、2 の値の写し間違いです【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/resolve-submission-errors）。
3. 「Windows 10/11 Desktop」に x64 と ARM64 が並べば OK です【推測】。

---

## 5. ストアの掲載情報（Store listings）

日本語と英語の両方を作るのがおすすめです（アプリが両方に対応しているため）【事実】。必須は **説明** と **スクリーンショット 1 枚以上**です【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/create-app-submission）。

| 欄 | 入れるもの | 印 |
|---|---|---|
| Description（説明）【必須】 | 下の文案 | — |
| Screenshots（スクリーンショット）【必須】 | PNG、**1366×768 以上**（3840×2160 まで）。最初の1枚は必須、4枚以上がおすすめ | 【事実】https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/screenshots-and-images |
| Store logos | 1:1 の 300×300：リポジトリの `windows/store/StoreListing-Logo-300.png`（GitHub で開いて長押し→「"写真"に保存」） | 【推測】Partner Center の欄の名前 |
| What's new / Features / Keywords | なくてもよい | 【事実】 |
| Copyright | `© 2026 Shogo Kajiyama / SEVENTHWELL` | — |

**スクリーンショット**：CI が画面を撮って `TwinKeys-Screenshot-…` に入れます。CI の画面の大きさが 1366×768 より小さいときは、そのままでは使えません（ファイル名に大きさが入っています）。そのときは、本物の Windows PC で撮るか、Claude に「Store 用に 1920×1080 の画像を作って」と頼んでください。**画面が実際のアプリと違うものは出さないでください**（Store の方針）【事実】。

**説明の文案（日本語）**：

> TwinKeys は、ライブやショーで、メインとバックアップの 2 台のコンピューターに同じキューを同時に送るアプリです。メインでキー（矢印、Space、Return など。好きなキーを足せます）を押すと、2 台の Ableton Live に同じ MIDI ノートが届き、同じクリップが同時に始まります。メインが止まっても、バックアップがそのまま続けられます。
> - Mac 版の TwinKeys とつながります（Mac＋PC、PC 2 台のどちらも）。
> - 通信は同じネットワークの中だけ。合言葉から作った鍵で暗号化します。
> - iPhone の TwinKeys Remote から Live を操作できます。
> TwinKeys は Ableton の公式のアプリではありません。「Ableton」「Live」は Ableton AG の商標です。

**説明の文案（English）**：

> TwinKeys sends the same cues to a main and a backup computer at once for live shows. Press a cue key on the main computer (arrows, Space, Return, or any key you add) and both copies of Ableton Live get the same MIDI note, so the same clip starts on both. If the main computer fails, the backup keeps going.
> - Works with TwinKeys for Mac (Mac + PC, or two PCs).
> - Talks only on your local network, encrypted with keys made from a shared pairing code.
> - Control Live from the TwinKeys Remote app on iPhone.
> TwinKeys is an unofficial tool, not made or endorsed by Ableton. "Ableton" and "Live" are trademarks of Ableton AG.

---

## 6. プロパティ・年齢区分・価格

### 6-1. Properties（プロパティ）

| 欄 | 入れるもの | 印 |
|---|---|---|
| Category（カテゴリ）【必須】 | Music（音楽）【推測：一番近い】。なければ Utilities & tools | 【推測】 |
| **Privacy policy URL**（プライバシーポリシー）【必須】 | 英語：https://kajisho5.github.io/ableton-twinkeys/privacy/ （日本語：https://kajisho5.github.io/ableton-twinkeys/ja/privacy/ ） | 【事実】どちらも開けることを確かめた（HTTP 200）。WinUI 3 のような「デスクトップのアプリ」は、個人情報を集めなくても必須【事実】https://learn.microsoft.com/windows/apps/publish/store-readiness-checklist |
| Website | https://kajisho5.github.io/ableton-twinkeys/ | — |
| Support contact info | https://github.com/kajisho5/ableton-twinkeys/issues | — |

> **注意**：今のプライバシーポリシーは、iPhone 版と Mac 版のことだけを書いていて、**Windows 版のことはまだ書いていません**【事実】（`docs/privacy/ja.md`、`en.md`）。審査に出す前に、Windows 版の項目（設定とログは PC の中だけ、合言葉は Windows の暗号化で保存、通信は同じネットワークの中だけ）を足すのがよいです【推測：審査で聞かれる可能性がある】。Claude に「プライバシーポリシーに Windows 版を足して」と頼めます。

### 6-2. Age ratings（年齢区分）

- IARC（国際年齢評価連合）のアンケートに答えます。全部の質問が必須です【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/age-ratings）。
- 最初の質問「アプリの種類」は、ゲームではない「アプリ」を選びます【推測：選択肢の名前】。
- TwinKeys には、暴力・性的な表現・ことば・ギャンブル・アプリ内課金・知らない人どうしのやりとり・位置情報の共有はありません【事実：アプリの中身】。なので、それぞれ「いいえ」です。
- ネットワークは同じ LAN の自分の機械（もう1台のコンピューターと自分の iPhone）とだけ話します。「ユーザーどうしがやりとりする」には当たりません【推測】。
- 最後に **Save and generate**（保存して作成）を押します【事実】。

### 6-3. Pricing and availability（価格と配布）

- Base price（基本の値段）【必須】：Mac 版と同じ**無料**がおすすめです【推測：決めるのはあなた】。
- Markets（国）・Audience・Discoverability・Schedule は、最初の値（全部の国、公開、すぐ）のままでよいです【事実：最初の値】。公開の時期は下の 7 で止められます。

---

## 7. 提出のオプション（Submission options）と、審査の人へのメモ

### 7-1. Publishing hold options（公開を止めておく）

**Don't publish this submission until I select Publish now**（「今すぐ公開」を押すまで公開しない）を選びます【事実：この選択肢がある】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/manage-submission-options）。本物の PC で試せるまで、合格しても公開されません。

### 7-2. Restricted capabilities（制限された機能）【必須】

TwinKeys は `runFullTrust` を使うので、理由を書く欄が出ます【事実】。次の英文をそのまま貼ります。

> TwinKeys is a WinUI 3 desktop app (Windows App SDK) and needs runFullTrust to run as a normal desktop process. It uses standard Win32 APIs that are only available to full-trust desktop apps: a low-level keyboard hook (to detect the user's chosen cue keys), WinMM MIDI output (to send notes to a loopback MIDI port that Ableton Live reads), a notification-area (tray) icon, and UDP/TCP sockets on the local network (to link with the user's second computer and the user's own iPhone). It does not install drivers or services and does not need administrator rights.

### 7-3. Notes for certification（審査の人へのメモ）

次の英文をそのまま貼ります（日付は貼る日に直してください）。

> Date: 2026-__-__
>
> What the app does: TwinKeys keeps two computers running Ableton Live in step during a show. When the user presses one of their "cue keys" on the main computer, TwinKeys sends the same MIDI note to Live on that computer and, over the local network, to a backup computer.
>
> Keyboard hook (please read): TwinKeys installs a low-level keyboard hook (WH_KEYBOARD_LL) only to recognise the cue keys the user has chosen (by default the arrow keys, Space, Return and Esc). For every key press it only checks whether that key is a cue key. It never records, stores, logs or sends what the user types. Only a cue key becomes a MIDI note; the log file (kept on the PC only) contains key names of cue keys, never typed text. Keys sent by other software (injected input) are ignored. Whether cue keys are also kept from other apps is the user's choice ("Key capture", in the main window, the tray menu or Ctrl+Alt+K).
>
> Network: TwinKeys talks only on the local network: UDP 47801 to the other TwinKeys computer (the firewall rule in the manifest is for private and domain networks only) and TCP 47803 for the user's own iPhone (TwinKeys Remote), each allowed once by the user after checking a 4-digit code. Traffic is encrypted with a key derived from a pairing code that the user types on both computers. There are no accounts, no analytics, no ads and no server of ours.
>
> How to test without a second computer or Live: start TwinKeys. A setup window ("TwinKeys Setup: Choose how cues reach Live") opens on first start; close it or choose an option. The main window shows the link status ("Not connected" is expected without a second computer). Open Settings from the window or from the tray icon to see every page. Pressing a cue key (for example the Right arrow) shows the cue in the main window even without a connection ("Not connected: Only this PC got the cue."). Full use needs Ableton Live and a second computer running TwinKeys (Windows or Mac) on the same network, or two PCs.
>
> Start at sign-in uses the package's startup task (off by default; the user turns it on in Settings > General).

- 書いてあることは、アプリの今の作りに合わせてあります【事実：`windows/src` のコードと `docs/design-windows.md` 7.1・14.2 の 9】。ただし「接続なしでキューのキーを押すとウインドウに出る（Only this PC got the cue.）」は、文言がアプリにあることだけを確かめ、実際の動きは確かめていません【推測】。

最後に、アプリの画面の **Submit for certification**（審査に提出）を押します【事実】。

---

## 8. 審査のあと

- 審査はふつう数時間、長いと 3 営業日【事実】（https://learn.microsoft.com/windows/apps/publish/publish-your-app/add-on/app-certification-process）。
- 落ちたときは、報告にどのテストか・どの方針かが書かれます【事実】。その文面を Claude に送ってください。
- 合格したら、本物の Windows PC で試してから **Publish now**（今すぐ公開）を押します。
- 更新のときは、新しい CI の `.msixupload`（版の 3 つ目の数字が大きいもの）を上げます【事実：版は毎回大きくする必要がある】。

---

## 9. CI が確かめていること・いないこと

| 項目 | 状態 |
|---|---|
| x64 と ARM64 の MSIX を作る | CI で確認（`.github/workflows/windows.yml` の build） |
| テスト用の証明書で署名した MSIX を、CI の Windows にインストールする | CI で確認 |
| インストールした MSIX から起動し、全部のウインドウと設定のページを開く（`--smoke-windows`） | CI で確認 |
| WACK（Store の技術テストとほぼ同じもの） | ランナーに WACK があるときだけ動く。結果は `TwinKeys-WACK-…`。ないときは「WACK did not run」と黄色で出る |
| 2 つをまとめた .msixbundle と .msixupload | CI で作る（store-package）。Partner Center が受け付けるかは【不明】（上げてみるまで分からない） |
| Store に出したアプリが本物の PC で動くか（キーボードフック、MIDI、ファイアウォールの例外、サインイン時の起動、Mac とつながるか） | **未確認**（本物の PC が要る。`docs/design-windows.md` 9.3） |
| Store の更新が本番中に起きないか | **未確認**（`docs/design-windows.md` 7.3 の【不明】のまま） |

関係するファイル：

- `windows/StoreIdentity.props` …… Store の製品 ID（ここだけ書き換える）
- `windows/src/TwinKeys.App/Package.appxmanifest` …… MSIX のマニフェストのひな形（ID は上のファイルから入る）
- `windows/assets-src/TwinKeys-windows.svg` と `windows/scripts/make-msix-assets.py` …… ロゴの元の絵と、各サイズの PNG を作るスクリプト
- `windows/store/StoreListing-Logo-300.png` …… Partner Center に上げる 300×300 のロゴ
