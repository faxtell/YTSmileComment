# YT Nico Chat Overlay (個人検証用)

## 概要
YouTube iOS (`com.google.ios.youtube`) のライブ配信/プレミア公開のチャットを、ニコニコ動画風に動画上へ右から左へ流すTheos Tweakです。

## できること
- 動画上オーバーレイ表示
- レーン分離、速度・透明度・フォントサイズ調整
- View階層監視ベースのチャット検出（壊れやすいのでフォールバック付き）
- WKWebView DOMテキスト候補読み取り（表示済みテキストのみ）
- モック表示モード
- デバッグログ/簡易Viewツリー出力

## できないこと
- 広告ブロック、Premium機能回避、DRM回避、課金回避
- 認証情報/Cookie/トークン抽出
- YouTube内部API不正利用、過剰アクセス

## 法的・倫理的注意
個人端末の検証用です。正当に扱えるYouTubeアプリ/IPAのみを対象とし、規約や法令に従ってください。

## 必要環境
- iOS 16+
- arm64 / arm64e
- Theos
- rootless jailbreak または正当なIPA注入環境

## ビルド方法
```bash
cd YTNicoChatOverlay
make clean
make package
```

## deb生成方法
```bash
cd YTNicoChatOverlay
./build_deb.sh
```
出力: `.theos/packages/yt-nico-chat-overlay_<version>_iphoneos-arm64.deb`

## IPA注入時の注意
- YouTube IPAは同梱しない
- 自分が扱えるIPAのみ
- 広告回避・DRM回避・Premium回避目的に使わない

## 設定項目一覧 (NSUserDefaults domain: `com.example.yt-nico-chat-overlay`)
- enabled (Bool)
- fontSize (Double)
- opacity (Double)
- speed (Double)
- maxLines (Int)
- showAuthorName (Bool)
- enableShadow (Bool)
- enableOutline (Bool)
- blockWords ([String])
- mockMode (Bool)
- debugLogging (Bool)

## トラブルシュート
- 表示されない: `mockMode=YES` で動作確認
- 重い: `maxLines` を下げる、`fontSize` を小さくする
- 誤検出: debugLoggingを有効化しViewツリーを確認

## YouTube更新で壊れた場合の調査
1. debugLoggingをON
2. Viewツリーをログ出力
3. チャット候補ラベル/セル/WKWebViewの変化点を確認
4. `YouTubeChatAdapter` の戦略を追加

## Debug Inspectorの使い方
`debugLogging=YES` のときのみ `[YTNico]` プレフィックスでログ出力。

## 今後の改善案
- 設定パネルのUI化
- レーン衝突回避の高度化
- メンバー/モデレーター色分け強化
- コメントプール再利用の最適化

## GitHub Actions で deb を作る
このリポジトリには `.github/workflows/build-deb.yml` を追加済みです。GitHub の macOS runner 上で以下を実行します。

1. Theos と必要ツールをセットアップ
2. `./build_deb.sh` 実行
3. `.theos/packages/*.deb` を Artifact としてアップロード

手動実行は GitHub の **Actions > Build YTNicoChatOverlay deb > Run workflow** から可能です。
