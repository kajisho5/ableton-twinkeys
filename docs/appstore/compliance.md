# App のプライバシーと、暗号の輸出規制 — TwinKeys Remote 1.2.0

App Store Connect で答える「App のプライバシー」と「暗号（輸出コンプライアンス）」について、調べた結果です。2026年11月12日に Apple などの公式ページで確かめました。

それぞれ、次の3つに分けて書いています。

- **事実**：公式ページかコードで確かめたこと（出典つき）
- **推測**：事実から考えた答え。たぶん正しいが、公式に「この場合はこう」とは書かれていないこと
- **分からないこと**：確かめられなかったこと

※ これは法律の助言ではありません。

---

## 1. App のプライバシー（App Privacy）の答え

### 答え

1. 「App のプライバシー（App Privacy）」で「始める（Get Started）」を押す。
2. 「**いいえ、このアプリからデータを収集していません**（No, we do not collect data from this app）」を選んで「保存（Save）」。ほかの質問はありません。
3. 右上の「公開（Publish）」を押す。

App Store のページには「**データの収集なし**（Data Not Collected）」と出ます。トラッキングもしないので、「トラッキングの許可」の画面（App Tracking Transparency）も要りません。

### 事実

- Apple の「収集（collect）」の意味：「データを端末の外へ送り、**あなた（開発者）や提携先**が、その場の処理に必要な時間より長く見られるようにすること」。端末の中だけで使うデータは「収集」に入らない。
  出典：[App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- 答え方（Get Started →「No, we do not collect data from this app」→ Save → Publish）。
  出典：[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- コードで確かめたこと：
  - iPhone の中に保存するのは、合言葉と端末の鍵（キーチェーン、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）、ランダムな端末 ID・前回の Mac の名前・設定（UserDefaults）だけ（`iOS/Sources/RemoteModel.swift`）。
  - 通信は、Bonjour（`_twinkeys-remote._tcp`）で見つけた Mac への TCP だけ。iOS アプリの中にインターネットの URL や URLSession はない（`iOS/Sources/` を検索して確認）。
  - Mac へ送るのは、端末 ID、端末の名前（`UIDevice.current.name`。iOS 16 以降はふつう「iPhone」などの機種名だけ）、公開用の鍵、操作の内容。
  - ほかの会社の SDK（分析・広告など）は入っていない。使っている外部の部品は Apple の swift-crypto だけ（`Package.swift`）。

### 推測

- 送り先は、利用者が自分で用意した Mac だけで、制作者や第三者には届きません。制作者は何も見られないので、Apple の定義の「収集」には当たらない、と考えます。
- ただし、Apple のページは「利用者自身の別の端末へ送る場合」をはっきりとは書いていません（下の「分からないこと」）。

### 分からないこと

- 「利用者自身の Mac に送るデータ」を Apple が「収集」と見るかどうかの、公式の説明は見つかりませんでした。定義の文（開発者や提携先が見られるか）に照らすと「収集ではない」になります。

### あわせて気をつけること（審査で問題になりうる）

1. **アプリの中にプライバシーポリシーへのリンクが要る**（事実）。審査ガイドライン 5.1.1(i)：「すべてのアプリは、App Store Connect の欄と、**アプリの中の分かりやすい場所**に、プライバシーポリシーへのリンクを入れること」。**1.2.0 で解決済み**：「設定」の「このアプリについて」に、プライバシーポリシー（日本語のときは `/ja/privacy/`）とサポートへのリンクを足しました（`iOS/Sources/Panes.swift` の `SettingsPane`）。
   出典：[App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
2. **プライバシーマニフェスト（PrivacyInfo.xcprivacy）がない**（事実）。アプリは UserDefaults を使っていて、これは Apple が「理由の申告が必要な API」に入れているものです（理由コード `CA92.1`：アプリ自身だけが読み書きする情報）。Apple は「2024年5月1日から、申告のないアプリは App Store Connect で受け付けない」と書いています。TestFlight へのアップロードは通っているので、今すぐ止まるかは分かりません（分からないこと）。**1.2.0 で解決済み**：`iOS/Sources/PrivacyInfo.xcprivacy`（追跡なし・集めるデータなし・UserDefaults の理由 CA92.1）を入れ、CI でアプリの中に入っていることを確かめています。Apple Watch アプリは理由の申告が要る API を使っていません。
   出典：[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) / [NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

---

## 2. 暗号の輸出規制（輸出コンプライアンス）

アメリカの法律（EAR。輸出管理規則）では、暗号を使うソフトを国の外へ配ることは「輸出」になります。App Store は世界に配るので、Apple は全アプリに「暗号を使っていますか」と確認します。

### 結論（先に）

- `iOS/project.yml` の `ITSAppUsesNonExemptEncryption: false`（「書類の要る暗号は使っていない」という意味）は、**Apple の説明に合っていて、このままでよい**と考えます（推測、根拠は下）。`project.yml` は変えていません。
- App Store Connect に出す書類（アメリカの CCATS、フランスの申告）は**要らない**（Apple の表による。下の事実 4）。
- 年末の自己分類レポート（アメリカ政府への毎年の報告）は、**たぶん要らない**（推測。下の推測 3）。

### 事実

1. **アプリが使っている暗号**：X25519（鍵の交換）、HKDF-SHA256（鍵を作る）、ChaCha20-Poly1305（暗号化）、HMAC-SHA256・SHA-256（なりすまし防止）、PBKDF2-HMAC-SHA256（合言葉から鍵を作る。CryptoKit の HMAC を使ってアプリの中で回している）。どれも公開された標準のやり方です（RFC 7748、5869、8439、2104、8018）。
   コード：`Sources/TwinKeysCore/RemoteChannel.swift`、`Sources/TwinKeysCore/Pairing.swift`
2. **暗号の中身は iOS の CryptoKit**：コードは `import Crypto`（Apple の swift-crypto 5.1.1）。swift-crypto の説明書には「CryptoKit がすでにある Apple の OS では、Swift Crypto は自分の中身を何も作らず、CryptoKit をそのまま使う」とあります。BoringSSL を同梱する `CryptoExtras` は使っていません（`Package.swift`）。
   出典：[swift-crypto README（5.1.1）](https://github.com/apple/swift-crypto/blob/5.1.1/README.md)（手元の `.build/checkouts/swift-crypto/README.md` 29行目でも確認）
3. **`ITSAppUsesNonExemptEncryption` の意味**：「暗号を使っていない、または**輸出の書類が要らない種類の暗号だけ**を使うなら NO（false）。それ以外は YES」。「ふつう、OS に入っている暗号を使うこと（例：URLSession の HTTPS）は書類のアップロードが要らない。独自の暗号は要る」。
   出典：[Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) / [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
4. **Apple の表**（App Store Connect に出す書類）：
   - 「Apple の OS の中の暗号だけを使う」→ **書類は要らない**
   - 「標準の暗号を、Apple の OS の外で（自分で）使う」→ フランスで配るならフランスの申告書
   - 「標準団体（IEEE、IETF、ITU など）が認めていない独自の暗号」→ CCATS とフランスの申告書
   出典：[Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
5. Apple は「EAR を読んで判断するのは開発者の責任。間違えたときの責任も開発者」と書いています。判断が要る例に「標準の暗号」「Apple の OS の中の暗号機能」「独自の暗号」をあげています。
   出典：[Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
6. Apple の注意書き：「書類の要らない暗号を使う場合でも、**年末の自己分類レポート**を政府に出す必要があるかもしれない」。この注意書きのリンク先（BIS の旧サイト）は、2026年11月12日に開くと BIS のトップページに飛ばされ、説明が見られませんでした。
   出典：[Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
7. **今の EAR の条文**（15 CFR 740.17）：
   - (b)(1)：自己分類した品目のうち「一部」に、(e)(3) のレポートが要る。マスマーケット（一般向けに売られ、利用者が暗号を変えられない製品）の条件を満たすものは 5A992 / 5D992 という分類になる。
   - (e)(3)：レポートが要るのは、「マスマーケットの**部品（components）**と、ハードウェアの部品から取り出した『**実行用ソフト（executable software）**』」、そして「マスマーケットではない 5A002・5B002・5D002 の品目」。期限は翌年2月1日。
   出典：[eCFR 15 CFR 740.17](https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17)
   参考（法律事務所の解説）：2021年3月29日の改正で、マスマーケットの製品のほとんどはレポートが要らなくなった。[Thompson Hine](https://www.thompsonhine.com/publications/bis-eliminates-most-mass-market-encryption-reporting-obligations) / [Venable](https://www.venable.com/insights/publications/2021/03/export-administration-rules-are-revised-to-elim)

### 推測

1. **OS の暗号だけ**：通信を守る暗号（ChaCha20-Poly1305、X25519、HKDF）は、すべて iOS の CryptoKit が行っています（事実 2）。なので Apple の表の「Apple の OS の中の暗号だけ」に当たり、`ITSAppUsesNonExemptEncryption = false` で合っている、と考えます。
2. **PBKDF2 について**：アプリの中で回しているのは PBKDF2 の繰り返し部分だけで、中身の計算は CryptoKit の HMAC です。しかも、作った鍵は「合言葉を知っているかの確認（認証）」に使うだけで、データを隠す（暗号化する）ためではありません。EAR では、認証だけの暗号は「データを秘密にする暗号」と分けて扱う考え方があります（今回、その条文の原文までは確かめていません）。答えを変える理由にはならない、と考えます。
3. **年末のレポートはたぶん要らない**：TwinKeys Remote は、誰でも無料で入れられ、利用者が暗号を変えられない一般向けアプリなので、マスマーケット（5D992.c）に当たると考えます。部品でも、ハードウェアから取り出したソフトでもないので、今の条文（事実 7）ではレポートの対象外です。Apple の注意書き（事実 6）は、2021年の改正より前の考え方が残っているものと見ています。
4. **独自の暗号ではない**：つなぎ方（あいさつのやりとり）は TwinKeys 独自の組み立てですが、使っている部品はすべて標準のやり方で、仕組みもソースコードと `docs/design-pairing.md` で公開しています。アメリカ政府の「独自の暗号」の定義は「独自のもの、または公開されていない、標準団体が認めていない暗号」なので、当たらないと考えます。
5. App Store Connect は、`ITSAppUsesNonExemptEncryption` が入っているビルドには暗号の質問をしません。もしビルドに「Missing Compliance（コンプライアンス情報がありません）」と出たら、「Apple の OS の中の暗号だけ」を表す答え（独自の暗号も、OS の外の標準の暗号も使っていない、という選択肢）を選びます。

### 分からないこと

- App Store Connect の暗号の質問の、今の正確な文と選択肢（ログインしないと見られないため）。
- BIS（アメリカ商務省 産業安全保障局）が、「標準の部品を独自に組み合わせたつなぎ方」をどう見るか。公式の判断は見つかりませんでした。
- Apple の「年末レポートが要るかもしれない」という注意書きが、今もどんな場合を指しているのか（リンク先が消えているため）。
- フランスの申告：Apple の表では「OS の暗号だけ」なら要りません。フランス側の今のルールの原文は確かめていません。

### これからのために

- 今のまま（`false`）で出してよいと考えます。
- 次のどれかをしたら、答えを見直してください：CryptoExtras や BoringSSL など OS の外の暗号ライブラリを入れる／暗号のやり方を自分で作る／インターネットのサーバーとの通信を足す。
- 心配なときは、BIS に英語で問い合わせるか、輸出管理にくわしい専門家に聞いてください。

※ Mac 版 TwinKeys（App Store の外で配っているもの）は、この文書の対象外です。
