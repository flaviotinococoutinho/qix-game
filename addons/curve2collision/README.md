# Curve2Collision

Godot 4.x 用エディタプラグイン。Path2D の曲線から、太さを持った CollisionPolygon2D を自動生成・自動更新します。

坂道・チューブ・レール・洞窟の壁など、「線で描いて、当たり判定を持たせたい」形状を作るのに向いています。

## 導入方法

1. `addons/curve2collision` フォルダを、あなたのGodotプロジェクトの `addons/` フォルダにコピーする
   (プロジェクト直下に `addons` フォルダが無ければ作成してください)
2. Godotエディタを開き、上部メニュー「プロジェクト」→「プロジェクト設定」→「プラグイン」タブを開く
3. 「Curve2Collision」を見つけて Enable(有効化)にチェックを入れる

## 使い方

1. シーンに `StaticBody2D`(動く床や壁を作るときは `AnimatableBody2D`、判定だけなら `Area2D` でも可)を追加する
2. その `StaticBody2D` の**子として** `CurveCollision2D` を追加する
   (`CollisionPolygon2D` は `CollisionObject2D` 系ノードの直接の子でないと機能しないため、
   この親子関係が必要です。`CurveCollision2D` を単独でシーンに置くと警告が出ます)
3. いつも通り、曲線編集ツールでカーブポイントを打って曲線を描く
4. インスペクタでプロパティを調整する(下表)
5. 曲線を編集するたびに、`GeneratedCollision`(CollisionPolygon2D)が自動生成・自動更新されます

```
StaticBody2D
├── CurveCollision2D      ← 曲線を描くノード
└── GeneratedCollision    ← 自動生成される CollisionPolygon2D
```

## プロパティ

| プロパティ | 型 | 既定値 | 説明 |
|---|---|---|---|
| `thickness` | `float` | `32.0` | 太さ(道や壁の幅)。曲線のどこでも一定に保たれる |
| `closed_loop` | `bool` | `false` | ON にすると始点と終点を繋いで閉じた枠(ドーナツ状)にする |
| `tolerance_degrees` | `float` | `4.0` | 曲線を直線に分解する精度。小さいほど滑らかだが頂点数が増える |
| `max_vertices` | `int` | `120` | 芯線(オフセット前の曲線)の頂点数の上限。超える分は自動で間引かれる(パフォーマンス対策) |
| `join_type` | enum | `Round` | 角の処理。Round=丸め / Square=面取り / Miter=尖らせる |
| `end_type` | enum | `Round` | 端の処理。Round=丸め / Square=はみ出して四角 / Butt=切り落とし(`closed_loop` 時は無視) |
| `auto_update` | `bool` | `true` | 曲線を編集するたびに自動でコリジョンを更新するか |
| `regenerate_now` | `bool` | `false` | チェックを入れると強制的に再生成する(手動更新トリガー) |

## 自己交差について

形状の生成には Godot 内蔵の `Geometry2D.offset_polyline()` / `offset_polygon()`(Clipper ライブラリ)を使用しています。急カーブに対して Thickness が大きい場合でも、内側で発生する自己交差はライブラリ側が正しく解消するため、**太さが痩せたり形が歪んだりすることはありません**。

`closed_loop` が ON のときは、外周と内周をそれぞれオフセットし、継ぎ目でつないだリング状のポリゴンを生成します。Thickness が図形より大きく内周が消える場合は、塗りつぶしの塊になります。

## 既知の制限・今後の改善候補

- `join_type` を `Round` にすると角が滑らかになる代わりに頂点数が増えます。軽くしたい場合は `Miter` か `Square`、または `tolerance_degrees` / `max_vertices` を調整してください
- 現状は矩形/円形などの「枠形状」はサポートしていません(曲線ベースの枠のみ)
- 重いシーンで多数のカーブを常時自動更新すると、エディタが重くなる可能性があります。その場合は Auto Update を OFF にして、Regenerate Now を手動でチェックしてください

## 動作確認について

Godot 4.7.1 で動作確認しています(曲線編集・自動追従)。ただし配布前には、様々な形状(急カーブ、閉じたループ、極端に長い/短い曲線)でのテストを追加で行うことをおすすめします。

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。

Copyright (c) 2026 seina369
