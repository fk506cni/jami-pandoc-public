# Reproducible Pandoc + Docker Authoring Environment for Conference Abstracts (.docx)

学会の詳細抄録を、Markdown / LaTeX ライクな環境（content/style 分離）で執筆し、
提出用 Microsoft Word ファイル（.docx）へ **再現可能に** 変換するためのツールです。
Pandoc を Docker コンテナ内で実行し、Lua フィルタと Python 後処理（三線表・
ネイティブ SVG 埋め込み・OOXML テキストボックス・ページ配置）でテンプレート準拠の
docx を生成します。査読対応のためのカラー差分（pandiff ベース）も備えます。

> **非公式・非承認 (Unofficial / Not endorsed)**
> 本ツールは個人が作成したコミュニティ製であり、いかなる学会・団体の公式ツールでも
> 承認物でもありません。引用スタイル `templates/jami.csl` も非公式の community 版です。
> 公式の抄録テンプレートは本リポジトリには **同梱していません**（下記 Setup で各自取得）。

> **同梱の原稿はサンプル（パロディ）です**
> `src/paper.md` は本ツールの全機能をデモするための **明確なフィクション** です。
> 実在の研究・人物・機関・データとは一切関係ありません。

## 前提条件 (Prerequisites)

* **Docker** および **Docker Compose** (v2)
* **Make**
* **Git**

ホストマシンへの Pandoc インストールは不要です。すべてのビルドは Docker コンテナ内で実行されます。

## セットアップ (Setup)

### 1. 抄録テンプレート原本の取得

公式の抄録テンプレートを配布元から各自ダウンロードしてください（本リポジトリでは再配布しません）。

- **配布元**: <https://jami2026symp.org/abstracts-guide.html>
- ダウンロードした `.doc` を Microsoft Word で開き、`.docx` 形式で保存
- 保存先: `dist/abstract_template_en.docx`

> このテンプレートは、**JAMI（日本医療情報学会）のシンポジウム**、および**同学会の英文誌（English journal）**への投稿を想定した公式テンプレートです。本ツールは、それに準拠した提出用 `.docx` を Markdown から再現可能に生成するための非公式な補助ツールです。

### 2. Docker イメージのビルド

```bash
make docker-build
```

### 3. テンプレート準備（コピー + 2段組設定 + スタイル追加）

```bash
make reference
```

## 使い方 (Usage)

### ビルド（Word ファイル生成）

```bash
make build              # または ./scripts/build.sh
```

> `dist/$(PROJECT_NAME).docx` が生成されます（デフォルト: `jami2026_abstract`、`config.mk` で変更可能）。

### 差分確認（カラーハイライト）

```bash
# 前回コミットとの差分（青=追加、赤+取消線=削除）
make diff               # または ./scripts/diff.sh

# 特定リビジョンとの差分
./scripts/diff.sh HEAD~3

# 2ファイル直接比較（査読対応）
./scripts/diff.sh old.md src/paper.md

# 従来の変更履歴モード
make diff-tracked       # または ./scripts/diff.sh --tracked-changes
```

> `dist/$(PROJECT_NAME)_diff.docx` が生成されます。

### PDF 変換（Windows）

```
scripts/word-to-pdf.bat に docx ファイルをドラッグ&ドロップ
  または
scripts/word-to-pdf.bat をダブルクリック（同フォルダ内の最新 docx を自動選択）
```

> LibreOffice はテキストボックスを正しくレンダリングできないため、PDF 変換には
> Windows 上の Microsoft Word を使用します。

### PDF 変換（Linux から一括: roundtrip）

Linux 上で作業しつつ Word 忠実の PDF を得るための中継スクリプトです。Google Drive を介して Windows の Word COM 変換を呼び出します。

```bash
./scripts/roundtrip.sh                 # build → gdrive push → Windows で PDF 化待ち → dist/ へ pull
./scripts/roundtrip.sh --skip-build    # 既存 dist の docx をそのまま PDF 化
./scripts/roundtrip.sh --dry-run       # rclone を呼ばず予定のみ表示
./scripts/roundtrip.sh --timeout 10    # PDF 待ちタイムアウト（分）
```

> 流れ: `[Linux] make build` → `docx を gdrive:tmp/<repo>/roundtrip/ へ push` → `[Windows] watch-and-convert.ps1 が Word COM で同名 PDF に変換` → `[Linux] その PDF を dist/ へ pull`。
>
> - **事前準備（Windows・1 回）**: Google Drive デスクトップで `tmp/<repo>/roundtrip/` を同期し、そのフォルダに `scripts/watch-and-convert.ps1` を置いて起動（Word 必須）。
> - **依存**: host に `rclone`（`gdrive:` リモート設定済み）。`--dry-run` は rclone を呼びません。
> - 出力は `dist/$(PROJECT_NAME).pdf`。認証情報はスクリプトに含めず、rclone 設定に委ねます。

### 発表スライド用ベクター図（任意・host ツール）

```bash
make fig-pptx                              # 既定 src/figs/fig1.pdf（持込）→ dist/figs/fig1.emf
./scripts/pdf-to-pptx-vector.sh my.pdf     # 任意の PDF を指定
```

> PDF 図を PowerPoint 用 EMF ベクターへ変換します（テキストはパス化）。**docx ビルドとは独立**（`make build`/`all` には結線されていません）。
>
> - **host ツール必須（Docker 外）**: `ghostscript`（gs）と `inkscape`（>= 1.0）。
> - **持込 PDF**: 既定入力 `src/figs/fig1.pdf` は同梱していません。自分の PDF を用意してください。
> - 入力 PDF または host ツールが無い場合は `skip` して終了（exit 0）するため、ビルドや CI を止めません。
> - 出力先 `dist/figs/` は `.gitignore` 済みです。

### その他

```bash
make clean              # dist/$(PROJECT_NAME)*.docx + *.pdf + src/figs/*.svg.png を削除
make help               # ターゲット一覧
```

## ディレクトリ構成

```
.
├── CLAUDE.md                     # Claude Code 用設定
├── CITATION.cff                  # 引用情報
├── LICENSE                       # MIT License
├── config.mk                     # プロジェクト設定（出力ファイル名）
├── Makefile                      # ビルドスクリプト（Docker 経由）
├── README.md                     # 本ファイル
├── SPEC.md                       # 技術仕様書
├── docker-compose.yml            # Docker Compose 設定
├── docker/
│   ├── pandoc/Dockerfile         # Pandoc ビルド環境
│   └── mermaid-svg/Dockerfile    # Mermaid/SVG 変換環境
├── dist/                         # 出力（生成物は .gitignore 済み）
│   └── .gitkeep
│       # ↑ 抄録テンプレート原本 dist/abstract_template_en.docx は各自取得（同梱せず）
├── filters/
│   ├── jami-style.lua            # Multi-pass: SVG→PNG パス書換 + 本文 → 本文スタイル + .textbox マーカー
│   └── color-diff.lua            # 差分カラーハイライト（青=追加/赤=削除）
├── src/
│   ├── figs/                     # 画像（PNG, JPG, SVG 対応）— 同梱はサンプル図のみ
│   ├── paper.md                  # 原稿本文（同梱はサンプル＝パロディ）
│   └── refs.bib                  # 参考文献データベース（同梱はサンプル）
├── templates/
│   ├── reference.docx            # スタイル参照用テンプレート（生成物・.gitignore 済み）
│   └── jami.csl                  # 引用スタイル定義（非公式 community 版, numeric [1] 形式）
└── scripts/
    ├── build.sh                  # ビルド（Docker/reference 自動チェック付き）
    ├── diff.sh                   # 差分ハイライト（カラー/変更履歴 切替対応）
    ├── fix-reference-cols.py     # reference.docx 後処理（2段組+スタイル追加+numPr削除）
    ├── fix-svg-clips.py          # SVG text クリッピング修正（make fix-svg / ビルド経路、冪等）
    ├── fix-svg-foreignobject.py  # Mermaid foreignObject→SVG text 変換（make fix-svg、独立・冪等）
    ├── pdf-to-pptx-vector.sh     # PDF図→EMFベクター（make fig-pptx、host gs+inkscape必須・持込PDF・build非結線）
    ├── wrap-textbox.py           # docx 後処理（booktabs + SVG 埋め込み + テキストボックス変換）
    ├── restore-textboxes.py      # diff 用: pandiff 出力に .textbox Div を復元
    ├── word-to-pdf.bat           # Windows: docx → PDF 変換（自己完結型）
    ├── watch-and-convert.ps1     # Windows: 同期フォルダ監視で docx→PDF 自動変換（roundtrip 用）
    ├── roundtrip.sh              # build→gdrive push→Windows(Word COM)でPDF化→pull（rclone 経由）
    └── commit-push.sh            # コミット & プッシュ
```

## ビルドパイプライン

```
src/paper.md + src/figs/*.svg
  → SVG→PNG 変換 (rsvg-convert 300 DPI, *.svg → *.svg.png)
  → pandoc (crossref → jami-style.lua [.svg→.svg.png 書換] → citeproc)
  → wrap-textbox.py --source src/paper.md output.docx
      1. booktabs 罫線適用
      2. SVG ネイティブ埋め込み (Word 2016+: ベクター品質)
      3. TextBoxMarker → OOXML テキストボックス変換
      4. ページ別アンカー再配置
  → dist/$(PROJECT_NAME).docx
     (templates/reference.docx でスタイル適用、config.mk で名前設定)
  → word-to-pdf.bat (Windows Word COM で PDF 変換)
  → dist/$(PROJECT_NAME).pdf
```

### 再現性 (Reproducibility)

ビルド時に環境変数 `SOURCE_DATE_EPOCH` を固定値で渡すと、出力 docx を unzip した
**全メンバの内容が決定的**（同一入力・同一 Docker イメージで `diff -r` 差分ゼロ）に
なります。これは同一 Docker イメージ・同一フォントを前提とした再現性です。
※ docx ファイル自体の SHA-256 は後処理 `wrap-textbox.py` の ZIP タイムスタンプにより
毎回変わります（unzip 後のメンバ内容は一致）。

## 注意事項

* **最終確認**: 生成された Word ファイルは、提出前に必ず MS Word で開き、改ページ位置や
  図の配置、文字数・頁数制限を確認・微調整してください。
* **図表番号**: pandoc-crossref を使用。図には `{#fig:label}`、表には `{#tbl:label}` を付け、
  本文中で `[@fig:label]` のように括弧形式で参照。
* **テンプレート**: `templates/reference.docx` のスタイル（フォント・マージン等）で出力の
  見た目が決まります。Markdown 側でレイアウトを制御しないでください。
* **カラー差分**: `make diff` で青色（追加）/ 赤色+取消線（削除）の差分を生成します。
* **SVG 画像**: `src/figs/` に `.svg` を置き、Markdown で `.svg` のまま参照します。ビルド時に
  300 DPI PNG フォールバック生成 + OOXML ネイティブ SVG 埋め込みが行われます。
* **テキストボックス**: テーブルや図を `.textbox` Div で囲むと OOXML テキストボックスとして
  出力され、Word 上でドラッグして位置を微調整できます。

## ライセンス (License)

本リポジトリのコードは **MIT License**（`LICENSE`）で配布します。
公式の抄録テンプレート（`dist/abstract_template_en.docx` 等）は **同梱・再配布しません**。
利用者が公式サイトから各自取得してください。
