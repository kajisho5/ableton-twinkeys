# つながりの表示（Mac と iPhone のアプリ）の設計案（承認待ち）

図：`docs/design/app-links-dark`（中身は架空のサンプル）

## ねらい

Mac・iPhone・Apple Watch のどれがつながっているかを、それぞれの画面で一目で分かるようにする。

## Mac（TwinKeys）

- 上の行のすぐ下に「つながり」の行を足す：相手の Mac（Live ✓・遅延）、iPhone（台数）、Apple Watch（iPhone 経由）。
- iPhone がつながっていないときは、灰色で「iPhone なし（受け付けはオン）」。受け付けがオフなら iPhone の欄は出さない。
- 押すと「設定」の「許可した端末」を開く。
- バックアップの Mac では「iPhone はメインの Mac に接続中（1台）」と出す（メインの Mac から、いつもの状態の知らせに台数を載せて送る）。
- Apple Watch は iPhone から知らせを受けて出す（Watch は Mac に直接つながらない）。Watch が届かないときは黄色で「Apple Watch：届きません」。

## iPhone（TwinKeys Remote）

- 上の帯：Mac の名前の横に、Apple Watch の印（つながっている：緑、届かない：黄色、Watch に入っていない：出さない）。押すと「設定」の「接続」を開く。
- 「設定」>「接続」：Mac（メイン）、バックアップ（Live ✓・遅延）、Apple Watch、合言葉、「別の Mac につなぐ」。
- Watch に入っていないとき：「Apple Watch：入っていません（Watch の App で入れられます）」。

## しくみ

- iPhone → Mac：Watch の状態（ペアリング済み・アプリが入っている・届く）を、変わったときに送る新しい知らせを足す。古い Mac は知らない知らせを読み飛ばす（今までの決まりどおり）。
- メインの Mac → バックアップの Mac：いつもの状態の知らせに「iPhone の台数」と「Watch の有無」を足す。古い Mac は読み飛ばす。

## 承認してほしいこと

1. Mac の「つながり」の行（図の左）
2. iPhone の上の帯の Watch の印と、「設定」>「接続」（図の右）
