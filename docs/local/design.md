# Repo Notes アプリ 設計メモ

ナレッジリポジトリ `hiraaaken/base` を読み書きするための個人用 Android アプリの要件・実装方針。

## 1. アプリの位置づけ

二つの用途を持つ Flutter 製 Android アプリ:

- 既存の Zettelkasten 型ナレッジ (`hiraaaken/base`) をモバイルから読みやすく参照する
- Claude Code の `/schedule` バッチに食わせるメモを書くための入力インターフェース

最終的にメモ入力は `daily.md` への追記に集約する想定 (現状 Notion 併用)。

## 2. 確定した基本仕様

| 項目 | 決定 |
|---|---|
| プラットフォーム | Phase 1: Android のみ |
| 言語・フレームワーク | Flutter |
| 状態管理 | Riverpod |
| ルーティング | go_router |
| 認証 | GitHub fine-grained PAT (Contents: R/W、`hiraaaken/base` 限定) |
| PAT 保管 | flutter_secure_storage |
| メモ送信先 | `daily.md` への append commit |
| 対応プラットフォーム拡張予定 | Phase 3 で Svelte 製 Web 版を別実装 |

## 3. メモ frontmatter フォーマット

`daily.md` には複数メモを追記する。各メモは以下の形式 (YAML frontmatter + 本文):

```markdown
---
genre: idea
tags: [flutter, mobile]
created: 2026-04-26T14:30:00Z
---

flutter の maxAlignment を使うと、子ウィジェットを親ウィジェットの最大のスペースに合わせて配置することができる
```

### フィールド定義

| フィールド | 型 | 必須 | 値 | 役割 |
|---|---|---|---|---|
| `genre` | string | 必須 | `idea` / `reading` / `investigate` の 3 値 enum | `/schedule` バッチへの種別ヒント |
| `tags` | array of string | 任意 | 自由入力、無制限。空配列 `[]` 許容 | トピック (既存 `index.md` のタグ系統と統一) |
| `created` | datetime (ISO 8601 UTC) | 必須 | `YYYY-MM-DDTHH:MM:SSZ` (UTC 固定) | メモ作成時刻 |

### パーサ前提

- **行頭 `---` (前後に空白なしの単独行) は本文中に書けない** (メモ境界のパースを単純化するため)。インラインの `---` (例: `これは---ダッシュ`) は許容。
- 各メモは「行頭 `---` で開始する frontmatter ブロック → 行頭 `---` で閉じる → 本文 → 次メモの行頭 `---` または EOF まで」。
- 最終メモは EOF で終端 (明示の閉じ `---` 不要)。
- 本文末尾の連続する空行は trim する。frontmatter の閉じ `---` 直後の空行は任意 (1 行も可、複数行も可)。
- frontmatter ブロック内は YAML として解釈する。

#### パーサ疑似コード (state machine)

```
state = START
memos = []
current = null

for line in daily.md.lines():
  if state == START:
    if line == "---":
      current = newMemo(); state = IN_FRONTMATTER
    elif line.isBlank():
      continue              # ファイル先頭の空行は無視
    else:
      error("expected '---' or blank at top")

  elif state == IN_FRONTMATTER:
    if line == "---":
      state = IN_BODY
    else:
      current.frontmatterLines.append(line)

  elif state == IN_BODY:
    if line == "---":       # 次メモの開始
      finalize(current); memos.append(current)
      current = newMemo(); state = IN_FRONTMATTER
    else:
      current.bodyLines.append(line)

# EOF 処理
if state == IN_BODY:
  finalize(current); memos.append(current)
elif state == IN_FRONTMATTER:
  error("unterminated frontmatter at EOF")
# state == START のまま EOF なら memos == [] (空ファイル許容)
```

`finalize()` は本文末尾の連続空行を trim し、frontmatter を YAML パースして `Memo` 構造体を確定させる。

### genre と /schedule バッチの対応

| genre | 想定処理 |
|---|---|
| `idea` | fleeting note 候補 (実装・ビジネスアイデア) |
| `reading` | literature note 候補 (書籍・記事の引用と学び) |
| `investigate` | 「Claude にあとで調べてもらう」マーカー。`要調査` タグ付き fleeting に変換 → `/research` 自動発火、または直接 `/research` 起動 |

バッチ実装はユーザー側の管轄。アプリは `genre: investigate` で吐くだけ。

### ナレッジ `kind` とメモ `genre` の関係

両者は別軸として独立している。混同しないこと。

- `notes.kind` ∈ `{fleeting, literature, permanent, research}` — リポジトリ内のノート種別 (path から推定 or frontmatter `type`)
- メモ frontmatter `genre` ∈ `{idea, reading, investigate}` — メモを書いた時点の意図ヒント (`/schedule` バッチへの hint)

| memo `genre` | 想定される最終 `kind` |
|---|---|
| `idea` | fleeting → 必要に応じ permanent へ昇格 |
| `reading` | literature |
| `investigate` | 一旦 fleeting (要調査タグ) → `/research` 実行後に research kind のノートが生成される |

メモ frontmatter で `research` ではなく `investigate` を採用したのは、notes.kind の `research` (調査結果ノート) と意味が違う (こちらは「これから調べてほしい」マーカー) ため。語彙衝突を避ける。

### 設計の経緯メモ

- 当初は「ジャンル → そのジャンルのタグ」の階層型を検討したが、シナリオ分析でジャンル切り替えの煩雑さが見えて却下
- 種別 (genre) とトピック (tags) を別軸として分離する現方式に落ち着いた
- 既存ノート (`literature/*.md` 等) の標準 YAML frontmatter と書式統一できる

## 4. 入力 UI

```
[Quick Memo]
+--------------------------------+
| 本文 (TextField, 自動 focus)   |
|                                |
+--------------------------------+
| ジャンル (必須・1 つ選択):     |
|   (idea) ( reading ) ( investigate )
|                                |
| タグ (任意・複数可):           |
|   #flutter  #ai  #要調査       |  頻度順 chips
|   #気づき  #podcast  #business |
|   + [_____]                    |  自由入力 + オートコンプリート
+--------------------------------+
|            [保存]              |
+--------------------------------+
```

### よく使うタグの初期シード

```
#flutter  #ai  #要調査  #気づき  #podcast  #business  #harness
```

`index.md` のパース結果が貯まったら頻度上位 8-10 件で上書き。

### 入力 → コミットの流れ

1. ユーザーが本文 + genre + tags を選択
2. アプリが整形 (Section 3 のフォーマットを生成)
3. GitHub Contents API で `daily.md` の SHA を取得
4. 末尾追記してコミット (sha 付き PUT で楽観ロック)

### 設計判断

- タグなしメモも許容 (`tags: []` でコミット)
- タグ無制限
- 直前タグの引き継ぎは実装しない

## 5. 自動 fetch 戦略

朝イチに WiFi 環境で自動取得、日中の更新は手動 Pull-to-Refresh で取得する想定。

### 採用方式: B + D 併用

- **B (WorkManager 日次)**: 24h 周期 + 朝 7 時 InitialDelay + WiFi (UNMETERED) 制約
  - OS 都合で 7-10 時頃に発火
  - これが主
- **D (アプリ起動時)**: 「最終 fetch から 6 時間以上経過」なら起動時に発火
  - アプリを開かない日は fetch されないが許容
- 両方走っても害なし (`tree.sha` 比較で短絡判定)

### Fetch ロジック (tarball delete + insert)

外部 DB を使わずスマホで完結させるため、差分同期ではなく **tarball で全件取得 → ローカル DB を delete + insert** する方式を採用。コードが単純で整合性も高い。

1. `GET /repos/hiraaaken/base/branches/main` で最新コミット SHA を取得 (~1KB)
2. ローカルの `sync_state.last_commit_sha` と比較 → 一致すれば何もせず終了 (短絡)
3. 不一致の場合のみ `GET /repos/hiraaaken/base/tarball/main` で tar.gz を 1 req で取得 (~100-200KB)
4. `archive` パッケージで Dart 側で展開
5. `notes` / `note_tags` / `tags` を全削除 → 再 INSERT (frontmatter パース)
6. `sync_state.last_commit_sha` を更新

100 ファイル規模なら tar.gz でも数百 KB に収まるため WiFi 前提で無問題。
**`memo_queue` は delete + insert の対象外** (未送信メモを失うリスクがあるため絶対に分離)。

### 同時実行制御

- B (WorkManager) / D (起動時 fetch) / 手動 Pull-to-Refresh は **単一 mutex で直列化** (`synchronized` パッケージ等)。後発は try-lock で no-op skip。
- delete + insert は Drift の単一トランザクション内で実行。トランザクション中は古いスナップショットを読めるため UI が一瞬空っぽになる問題は発生しない。
- メモ append commit (`memo_queue` flush) と fetch も同じ mutex を共有する (両者が同時に `daily.md` を触らないように)。

### 通知方針 (Phase 1)

- 同期完了通知: なし
- 「N 件更新あります」バッジ: なし
- プッシュ通知でのエラー通知: なし
- ただし設定画面に「最終 sync 時刻」と「最終 sync 結果 (success / failure + エラー文)」を **必ず表示する** (サイレント失敗を防ぐため Phase 1 から)

## 6. 画面構成

### タブ構成 (3 タブ)

```
+--------------------------------------+
| [メモ]      [ノート]      [設定]     |
+--------------------------------------+
```

| タブ | 役割 |
|---|---|
| メモ | 「今日のメモ」カードリスト (daily.md パース) + FAB で新規入力 |
| ノート | ナレッジ閲覧 (literature / permanent / fleeting / research) |
| 設定 | PAT 設定、同期、デバッグ |

### メモタブ (Google Keep 風カードリスト)

- daily.md は Markdown としてレンダリングしない
- 各メモをカードで表示 (時刻 + tags chips + 本文)
- `daily.md` のリモート最新と `memo_queue` の pending をマージ表示
- pending メモは「同期中」「失敗」のバッジ付き
- FAB で入力モーダル (Section 4)

### ノートタブ

```
+-------------------------------+
| (検索)                        |
| [all] [fleeting] [literature] |  横スクロール chip セグメント
| [permanent] [research]        |
+-------------------------------+
| #ai #flutter #harness ...     |  タグ chip フィルタ
+-------------------------------+
| ハーネスエンジニアリングの... |
|   #ai #architecture           |
|   2026-04-17                  |
+-------------------------------+
| Flutter StatefulWidgetの ...  |
|   #flutter #mobile            |
|   2026-04-18                  |
+-------------------------------+
```

- 5 セグメント: `all` / `fleeting` / `literature` / `permanent` / `research`
- meta ファイル (`index.md`, `CLAUDE.md`, `README.md`, `profile.md`, `docs/`, `.claude/skills/`, `templates/`) はアプリから完全除外
- デフォルト並び: 新しい順 (frontmatter `created` desc)
- 検索はタイトル + タグ全件横断 (セグメント無視)

### ノート詳細画面

```
+--------------------------+
| (戻る)                ⋮  |
+--------------------------+
| (title)                  |
| #flutter #mobile         |
| 2026-04-18               |
| type: literature         |
+--------------------------+
| ## 要約                  |
| (本文 - flutter_markdown)|
+--------------------------+
| 関連ノート:              |
|  → permanent/...         |
+--------------------------+
```

- frontmatter を `gray_matter` で剥がし、本文を `flutter_markdown` でレンダリング
- frontmatter は chips/ヘッダ UI に変換表示
- `related` フィールドはタップで他ノートへ遷移 (Phase 2)

## 7. データモデル (drift)

### テーブル構成

```
notes        リポジトリのノート本体 (キャッシュ)
note_tags    notes <-> tags の中間テーブル
tags         タグマスタ (出現回数キャッシュ付き)
sync_state   同期メタ情報 (singleton)
memo_queue   オフライン送信待ちメモ
```

### スキーマ (叩き台)

```
notes
  path           TEXT PRIMARY KEY    "literature/20260418230800-....md"
  kind           TEXT NOT NULL       fleeting | literature | permanent | research
  title          TEXT
  source         TEXT NULL
  source_type    TEXT NULL
  created        DATETIME
  raw            TEXT                全文 (frontmatter 含む)
  related        TEXT                JSON 配列
  updated_at     DATETIME            ローカルキャッシュ更新時刻

note_tags  (M:N)
  note_path      TEXT
  tag            TEXT
  PRIMARY KEY (note_path, tag)
  INDEX on (tag)

tags
  name           TEXT PRIMARY KEY
  count          INTEGER             出現回数 (chips 表示順)
  last_used_at   DATETIME

sync_state  (1 行のみ)
  id                INTEGER PK
  last_commit_sha   TEXT             短絡判定用 (main ブランチの最新コミット SHA)
  last_fetch_at     DATETIME

memo_queue
  id             INTEGER PK AUTO
  body           TEXT
  genre          TEXT                idea | reading | investigate
  tags_json      TEXT
  created_at     DATETIME
  dedup_key      TEXT                SHA-256(created_at_iso + "\n" + body) — append 重複防止
  status         TEXT                pending | syncing | failed
  error_msg      TEXT NULL
  retry_count    INTEGER DEFAULT 0
```

### 設計方針

- スマホ単独で完結 (外部 DB サービスなし)。GitHub repo がソース・オブ・トゥルース、ローカル DB はキャッシュ + 送信キューのみ
- ナレッジ系テーブル (`notes` / `note_tags` / `tags`) は **delete + insert** で同期。差分管理しないので per-file `sha` 列は不要
- `memo_queue` は delete + insert の対象外 (未送信メモ消失防止のため厳密に分離)
- 本文は `raw` 1 列でフル保存 (~500KB 程度なので問題なし)
- 表示時に `gray_matter` で frontmatter を剥がす
- タグは正規化 (中間テーブル `note_tags` + キャッシュ列 `tags.count`)
- 「タグごとのノート一覧」「タグ頻度ランキング」を高速にクエリ
- FTS5 全文検索は Phase 2

### memo_queue でオフラインファースト

- 「保存」押下時に `memo_queue` に INSERT (`dedup_key` も同時に計算して保存) → 即座にメモタブに反映
- バックグラウンドで `daily.md` への commit を試行
- 成功 → queue から削除
- 失敗 → status=failed + retry_count++ → 次回ネットワーク復帰時に再試行
- 「メモしたのに画面に出ない」を防ぐ

### Crash recovery と冪等性

`status=syncing` のままアプリが kill されると永久 syncing 状態になる。また「commit 成功直後に kill」のケースではリモートには既に append 済みなのにローカル queue に残る。両方対処する:

1. アプリ起動時に `status=syncing` のレコードを `pending` に戻す
2. flush 時、append commit を発行する **前に** `daily.md` の直近 N 件 (例 N=50) を fetch し、各メモから `dedup_key` を再計算
3. queue の `dedup_key` がリモートに既に存在 → そのレコードは「commit 成功済みだったケース」として queue から削除 (重複 append しない)
4. 存在しない → 通常通り append commit
5. dedup_key の計算は `SHA-256(created_at の ISO 8601 文字列 + "\n" + body)`。frontmatter の `tags` や `genre` は含めない (タグ修正後再送等のケースは Phase 2 で考える)

## 8. パッケージ選定

| 用途 | パッケージ |
|---|---|
| 状態管理 | riverpod |
| ルーティング | go_router |
| HTTP クライアント | dio (interceptor で PAT 自動付与) |
| ローカル DB | drift (SQLite + 型安全 + FTS5 対応) |
| 機密ストレージ | flutter_secure_storage (PAT 保管) |
| Markdown レンダリング | markdown_widget (`flutter_markdown` は 2024 に discontinued。後継候補として `markdown_widget` / `gpt_markdown` があり、wikilink 拡張のしやすさで前者を採用) |
| シンタックスハイライト | flutter_highlight (Phase 2) |
| frontmatter パース | `yaml` パッケージ + 自前ラッパー (~30 行)。`gray_matter` は Dart 公式の決定版が無いため自前で書く方が確実 |
| バックグラウンド処理 | workmanager |
| ネットワーク種別検知 | connectivity_plus |
| tar.gz 展開 | archive |

## 9. Phase 切り

- **Phase 1 (MVP)**
  - PAT 設定 / Settings
  - `daily.md` への追記コミット (memo_queue + オフラインファースト + dedup_key)
  - ノート閲覧 (5 セグメント、タグフィルタ、新しい順)
  - 手動 Pull-to-Refresh
  - 自動 fetch (B+D 方式 + 単一 mutex)
  - 設定画面に「最終 sync 時刻 / 最終 sync 結果 / エラー文」を表示 (サイレント失敗防止)
- **Phase 2**
  - FTS5 全文検索
  - シンタックスハイライト
  - related フィールドのリンク遷移、wikilink/相対パスリンクのタップ遷移
  - プッシュ通知でのエラー通知 (PAT 期限切れ等)
- **Phase 3**
  - Svelte 製 Web 版 (PWA)

## 10. 競合・エラー処理

### `daily.md` は append-only stream として扱う

アプリは末尾追記しか行わない。編集や削除はリポジトリ側 (人間 or バッチ) が行う。これにより SHA 衝突は「直列化された 2 つの append」に縮約され、マージは発生しない。

```pseudo
fn appendMemoWithRetry(memo, maxRetries=3):
  for i in 0..maxRetries:
    {sha, body} = GET /repos/.../contents/daily.md
    if memo.dedup_key in lastNDedupKeys(body, N=50):
      delete from memo_queue where id=memo.id; return SUCCESS  # 既に append 済み
    newBody = body + "\n\n" + memo.serialize()
    res = PUT /repos/.../contents/daily.md (sha=sha, content=newBody, message=...)
    if res.status == 200: 
      delete from memo_queue where id=memo.id; return SUCCESS
    if res.status == 409: continue                              # SHA 衝突 → re-fetch して retry
    return FAIL_WITH(res.status, res.body)
  return FAIL_RETRY_EXHAUSTED
```

### `/schedule` バッチ (02:00 JST) との競合

- バッチ側も append-only / 既存 frontmatter ブロックの移動のみ ならば SHA 衝突は上記リトライで吸収される
- バッチがメモを消費して別ファイル (例 `permanent/...md`) に移動する場合、`daily.md` から該当メモが消える → アプリ側で次回 fetch 時に消費済みメモが消えるだけ。queue 側との整合は dedup_key チェックで「リモートに無いから新規 append OK」とならないよう、queue 側は **commit 試行直後に成功した時点で queue から削除** する原則で問題ない
- バッチ実行時刻 (02:00 JST 想定) はアプリの自動 fetch 時刻 (07:00) と被らないので実運用上は安全

### SHA 衝突時のリトライ戦略

- HTTP 409 (sha mismatch) は無条件で 3 回までリトライ (上記疑似コード参照)
- それ以外の 4xx/5xx は status=failed にして queue に残し、次回ネットワーク復帰 or 手動リトライまで待つ

### PAT 期限切れ・無効時のフォールバック

- `memo_queue` には積み続ける (ローカルではメモは絶対に失われない)
- 401/403 を検出したら設定画面の「最終 sync 結果」に「PAT 認証失敗 (要更新)」と表示
- ユーザーが PAT を更新したら手動 sync ボタンで queue を flush
- Phase 2 でプッシュ通知化を検討

### オフラインからの復帰時の queue flush 順序

- `created_at` 昇順で **1 件ずつ** 直列に append (並列化しない、API rate limit と commit history の順序保証のため)
- 1 件失敗してもそこで止めず次のメモに進む (永久失敗の 1 件で全体が止まらないように)
- 失敗メモは `status=failed` のまま残し、ユーザーが設定画面から手動でリトライ or 削除

## 11. データ正規化と表示規約

### Timezone

- 保存: `created` は UTC ISO 8601 固定 (`YYYY-MM-DDTHH:MM:SSZ`)
- 表示: 端末ローカル timezone (日本想定なら JST)
- 「今日のメモ」境界: 端末ローカル timezone の 0:00 を境界とする
- カードリストの並び基準: `created` の比較 (UTC のまま比較すれば順序は同一)

### タグ正規化

- 大文字小文字: **保持** (`Flutter` と `flutter` は別タグ。書いた人の意図を尊重)
- 前後の空白: trim
- 内部の空白: 禁止 (UI 入力時に半角/全角空白で分割してタグ化)
- Unicode 正規化: NFC で保存
- 絵文字: 許容
- マッチ・dedupe は正規化後の文字列の完全一致

### 既存 `literature/*.md` 等の frontmatter マッピング

| 既存 frontmatter | notes 列 | 補足 |
|---|---|---|
| `type` | `kind` | 値 `fleeting/literature/permanent/research` をそのまま入れる。欠如時は path から推定 (`literature/...md` → `literature` 等) |
| `created` | `created` | UTC で保存 |
| `tags` | `note_tags` (M:N) | 上記の正規化ルール適用 |
| `source` | `source` | literature 用 |
| `source_type` | `source_type` | literature 用 |
| `related` | `related` (JSON 配列) | path 配列 |
| (タイトル) | `title` | frontmatter に title が無ければ Markdown の最初の H1、それも無ければ path basename |

### Wikilink / 相対パスリンクの Phase 1 挙動

- `[[link]]` 形式: Phase 1 は **素通し表示** (markdown としてレンダリングされず、文字列としてそのまま見える)
- 相対パスリンク (`./permanent/xxx.md` 等): Phase 1 は **リンクとして表示するがタップしても遷移しない** (markdown_widget の onTap を無効化)
- Phase 2 で `related` フィールドのリンク遷移と一括対応 (アプリ内ルーティング `/notes/:path` へ resolve)

### tarball サイズの growth path

- 想定上限: 1000 ファイル / 2MB (tar.gz 後)
- 超過時の方針: per-file `GET /contents` または GraphQL API による差分取得に切替 (Phase 2/3 の検討事項)
- ローカル DB 容量も併せて監視 (`raw` 列の合計サイズ ~50MB を超えるなら本文の lazy load を検討)
