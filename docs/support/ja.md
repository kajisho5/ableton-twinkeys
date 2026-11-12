# TwinKeys Remote サポート

TwinKeys Remote は、音響のオペレーター向けの iPhone・iPad アプリです。無料の Mac アプリ TwinKeys を通して、メインの Mac とバックアップの Mac の Live を同時に操作します。

## 用意するもの

- [TwinKeys](https://github.com/kajisho5/ableton-twinkeys/releases/latest) 2.1 以降を入れた Mac を2台（メインとバックアップ）。TwinKeys は無料です。
- 両方の Mac に Ableton Live 11 か Live 12。「コントロールサーフェス」で TwinKeysBridge を選んでおきます。
- iOS 17 以降の iPhone・iPad。Mac と同じネットワークにつなぎます。

TwinKeys Remote だけでは何もできません。Mac で TwinKeys が動いている必要があります。

## はじめかた

1. 両方の Mac で TwinKeys の「設定」を開き、「Live との連携」で「Live に組み込む」を押します。Live を再起動し、「コントロールサーフェス」の空いている欄で「TwinKeysBridge」を選びます。
2. メインの Mac で「TwinKeys Remote からの接続を受け付ける」をオンにします。
3. iPhone で Mac と同じ合言葉を入れて「保存」を押し、ローカルネットワークの利用を「許可」して、メインの Mac の「接続」を押します。
4. iPhone と Mac に同じ4桁の番号が出ているのを確かめて、Mac で「許可」を押します。

くわしい手順：[iPhone・iPad から Live を操作する](https://kajisho5.github.io/ableton-twinkeys/ja/guide/#iphoneipad-から-live-を操作するtwinkeys-remote)

## よくある困りごと

**iPhone に Mac が出てこない**
- iPhone と Mac が同じネットワークか確かめます。会場やホテルの Wi-Fi は、機器どうしが見えないようになっていることがよくあります。自分のルーターかケーブルを使ってください。
- iPhone の「設定」>「プライバシーとセキュリティ」>「ローカルネットワーク」で TwinKeys Remote をオンにします。
- メインの Mac で「TwinKeys Remote からの接続を受け付ける」がオンか確かめます。

**iPhone に「合言葉が Mac と違います」と出る**
- iPhone の合言葉を、Mac の「設定」>「合言葉」と同じにしてください。

**操作しても Live が動かない**
- Mac の TwinKeys の「設定」に「Live: 接続済み」と出ているか確かめます。出ていなければ、Live の「コントロールサーフェス」で TwinKeysBridge を選びます。
- 本番ロック中は、テンポとミキサーは動きません。解除は鍵のボタンを1秒長押しします。

**上の帯にバックアップの「Live ✗ 応答なし」と出る**
- バックアップの Mac で、Live が開いているか、TwinKeysBridge が選ばれているかを確かめます。

ほかの困りごと：[困ったとき](https://kajisho5.github.io/ableton-twinkeys/ja/guide/#困ったとき)

## 問い合わせ

[github.com/kajisho5/ableton-twinkeys/issues](https://github.com/kajisho5/ableton-twinkeys/issues) で issue（質問や報告の書き込み）を作ってください（無料の GitHub アカウントが必要です）。次のことを書いてもらえると助かります。

- iPhone・iPad の機種と iOS のバージョン
- TwinKeys Remote のバージョンと、2台の Mac の TwinKeys のバージョン
- Live のバージョン
- 何をしたか、どうなるはずだったか、実際にどうなったか

issue は誰でも読めます。**合言葉は書かないでください。** 返事まで数日かかることがあります。

## プライバシー

TwinKeys Remote は、データを一切集めません。通信の相手は、手元のネットワークにあるあなたの Mac の TwinKeys だけです。くわしくは[プライバシーポリシー](https://kajisho5.github.io/ableton-twinkeys/ja/privacy/)を見てください。

## 制作

TwinKeys と TwinKeys Remote は Shogo Kajiyama / SEVENTHWELL が作り、MIT License で公開しています。非公式のツールで、Ableton 社が作ったり、認めたり、サポートしたりしているものではありません。Ableton、Live は Ableton AG の商標です。
