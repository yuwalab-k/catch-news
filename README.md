# catch-news

RSS・YouTube RSS・各種 API から記事を集めて、タブ切り替えの静的ページを生成する情報収集ツールです。GitHub Actions で定期実行し、GitHub Pages で公開します。

取得した記事はエディションごとの JSON として `data/items/{slug}.json` に保存します。表示用 HTML はこの JSON から生成するため、あとからレイアウトを変えたい場合も、取得データを残しておけば再生成できます。

## ページ構成

```
docs/
  index.html              最新エディション（articles/ と同内容）
  archive.html            エディション一覧
  style.css               スタイルシート
  articles/
    {slug}.html           エディション本体（Knowledge / Official / Security タブ）
```

エディションは1ページにまとまっており、タブで Knowledge・Official・Security を切り替えます。

## カテゴリ

| カテゴリ | 内容 |
|---|---|
| `knowledge` | 技術ブログ・企業テックブログ・エンジニア向けニュース |
| `official` | 主要サービス・企業の公式情報 |
| `security` | セキュリティ情報・脆弱性・アドバイザリ |

## ソース設定

取得元は環境変数で管理します。ローカルでは `.env` を `source` して使用し、GitHub Actions では GitHub Secrets に設定します。

### RSS_SOURCES

`;;` 区切りで複数指定。1件の書式は `id|name|url|color|icon_url|category` です。`color`・`icon_url`・`category` は省略可。YouTube も RSS として登録できます。

```sh
export RSS_SOURCES='zenn|Zenn|https://zenn.dev/feed|#3ea8ff||knowledge;;github-blog|GitHub Blog|https://github.blog/feed/|#24292f||official;;jpcert|JPCERT/CC|https://www.jpcert.or.jp/rss/jpcert-all.rdf|#005bac||security'
```

### API_SOURCES

`;;` 区切りで複数指定。1件の書式は `id|name|kind|url_or_endpoint|color|icon_url|category` です。

対応している `kind`:

- `hackernews` — `topstories` / `beststories` / `newstories`
- `devto` — DEV Community articles API URL
- `qiita` — Qiita items API URL

```sh
export API_SOURCES='hn-top|Hacker News Top|hackernews|topstories|#ff6600||knowledge'
```

`icon_url` を省略した場合はソース URL の favicon を自動取得します。

### その他の環境変数

| 変数 | デフォルト | 説明 |
|---|---|---|
| `VIEW_PASSWORD` | (なし) | 設定するとパスワードゲートを有効化 |
| `MAX_ITEMS` | `500` | 1エディションに出力する記事の最大件数 |
| `FETCH_OG_IMAGES` | `0` | `1` にすると OG 画像を取得（低速） |
| `SINCE_DATETIME` | (なし) | `YYYYMMDDHHММ` (JST) 以降の記事を既読でも再取得 |

## ローカル実行

```sh
# .env を用意して source する
source .env
perl bin/generate.pl
```

生成されるファイル:

```
data/items/{slug}.json  エディションごとの取得記事データ
data/editions.json      エディション一覧
state/seen.json         既読判定・取得状況の管理
docs/index.html         最新エディション
docs/archive.html       エディション一覧
docs/articles/{slug}.html
docs/style.css
docs/.nojekyll
```

## ファイル構成

```
bin/
  generate.pl           メインスクリプト（オーケストレーションのみ）
lib/
  Util.pm               汎用ユーティリティ（HTML エスケープ・日付・JSON IO など）
  Fetcher.pm            HTTP フェッチ・RSS / API パース
  Source.pm             ソース設定のパース・メタデータ管理
  Catalog.pm            カテゴリ定義・カテゴリ別グルーピング
  Renderer.pm           HTML 生成・CSS
data/                   記事・エディションデータ（自動生成）
state/                  取得済み管理（自動生成）
docs/                   公開ファイル（自動生成）
```

## GitHub Actions

`.github/workflows/generate.yml` が手動実行と1日2回の定期実行に対応しています。

- `0 22 * * *` UTC = 07:00 JST
- `0 8 * * *` UTC = 17:00 JST

以下を GitHub Secrets に設定してください:

- `RSS_SOURCES`
- `API_SOURCES`
- `VIEW_PASSWORD` (optional)

workflow は生成後に `data`・`state`・`docs` をコミットし、`docs/` を Pages artifact としてデプロイします。

## パスワード保護

`VIEW_PASSWORD` を設定すると全ページにパスワードゲートが付きます。クライアントサイドの簡易ガードです（Basic 認証ではなく、生成ファイル自体を隠すものではありません）。
