# catch-news

RSS、YouTube RSS、API から記事を集めて、日別エディションの静的ページを生成する情報収集ツールです。

## ページ構成

- `index.html` / `archive.html` — 全エディション一覧（同一内容）
- `YYMMDD(am|pm)-knowledge.html` — 技術ナレッジ・ブログ記事
- `YYMMDD(am|pm)-official.html` — 公式情報（AWS/GitHub/Vercel/Googleなど）
- `YYMMDD(am|pm)-security.html` — セキュリティ関連情報（JPCERT/CISAなど）

1日2回（朝刊 am / 夕刊 pm）生成し、過去のエディションは `archive.html` にリンクが一覧されます。

## カテゴリ

| カテゴリ | 用途 |
|---|---|
| `knowledge` | 技術ブログ、個人ブログ、エンジニア向けニュース |
| `official` | 主要サービス・企業の公式情報 |
| `security` | セキュリティ情報・脆弱性・アドバイザリ |

## Source settings

取得元は環境変数で管理します。RSS と API は書式を分けています。

ローカルではシェルの環境変数（または `.env` を `source` して使用）、GitHub Actions では GitHub Secrets に設定します。

### RSS_SOURCES

1行につき `id|name|url|color|icon_url|category` です。`color`、`icon_url`、`category` は省略できます。YouTube も RSS として登録できます。

```sh
export RSS_SOURCES='zenn|Zenn|https://zenn.dev/feed|#3ea8ff||knowledge;;github-blog|GitHub Blog|https://github.blog/feed/|#24292f||official;;jpcert|JPCERT/CC|https://www.jpcert.or.jp/rss/jpcert.rdf|#005bac||security'
```

### API_SOURCES

1行につき `id|name|kind|url_or_endpoint|color|icon_url|category` です。`color`、`icon_url`、`category` は省略できます。

対応している `kind`:

- `hackernews`: `topstories`, `beststories`, `newstories`
- `devto`: DEV Community articles API URL
- `qiita`: Qiita items API URL

```sh
export API_SOURCES='hn-top|Hacker News Top|hackernews|topstories|#ff6600||knowledge;;qiita-ai|Qiita AI|qiita|https://qiita.com/api/v2/items?query=AI&per_page=20|#55c500||knowledge'
```

GitHub Actions Secrets に入れる場合は、改行の代わりに `;;` 区切りで書けます。

`icon_url` を省略した場合は、ソースURLから favicon を表示します。

## Generate

```sh
# ローカル実行（.envを用意してsourceする）
source .env
perl bin/generate.pl
```

生成されるファイル:

```txt
data/items.json          全記事の蓄積DB
data/editions.json       エディション一覧
state/seen.json          取得済み記事の管理
dist/index.html          エディション一覧（archive.htmlと同一）
dist/archive.html        エディション一覧
dist/YYMMDD(am|pm)-knowledge.html
dist/YYMMDD(am|pm)-official.html
dist/YYMMDD(am|pm)-security.html
dist/items.json          最新記事JSON
```

## Optional password

`VIEW_PASSWORD` を設定すると、全ページに簡易パスワード画面を付けます。

```sh
export VIEW_PASSWORD='your-password'
```

静的HTML上の簡易ガードです。Basic認証ではなく、JSONや生成物を完全に隠すものではありません。

## GitHub Actions

`.github/workflows/generate.yml` は手動実行と1日2回の定期実行に対応しています。

- `0 22 * * *` UTC = 07:00 JST → am エディション
- `0 6 * * *` UTC = 15:00 JST → pm エディション

以下を GitHub Secrets に設定してください:

- `RSS_SOURCES`
- `API_SOURCES`
- `VIEW_PASSWORD` (optional)

GitHub Pages は `dist/` ディレクトリを公開対象にしてください。
