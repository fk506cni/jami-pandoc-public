# Reproducible Pandoc + Docker Authoring Environment for Conference Abstracts (.docx)

A tool for writing conference detailed abstracts in a Markdown / LaTeX-like environment
(content/style separation) and converting them **reproducibly** into the submission-ready
Microsoft Word file (.docx). Pandoc runs inside a Docker container, and Lua filters plus
Python post-processing (three-line tables, native SVG embedding, OOXML text boxes, per-page
placement) produce a template-compliant docx. A pandiff-based color diff for peer-review
revisions is also included.

学会の詳細抄録を、Markdown / LaTeX ライクな環境（content/style 分離）で執筆し、
提出用 Microsoft Word ファイル（.docx）へ **再現可能に** 変換するためのツールです。
Pandoc を Docker コンテナ内で実行し、Lua フィルタと Python 後処理（三線表・
ネイティブ SVG 埋め込み・OOXML テキストボックス・ページ配置）でテンプレート準拠の
docx を生成します。査読対応のためのカラー差分（pandiff ベース）も備えます。

> **Unofficial / Not endorsed**
> This is a personally developed, community-made tool. It is not an official or endorsed tool
> of any academic society or organization. The citation style `templates/jami.csl` is likewise
> an unofficial community version. The official abstract template is **not bundled** in this
> repository (obtain it yourself in Setup below).
>
> **非公式・非承認**
> 本ツールは個人が作成したコミュニティ製であり、いかなる学会・団体の公式ツールでも
> 承認物でもありません。引用スタイル `templates/jami.csl` も非公式の community 版です。
> 公式の抄録テンプレートは本リポジトリには **同梱していません**（下記 Setup で各自取得）。

> **The bundled manuscript is a sample (parody)**
> `src/paper.md` is a clearly fictional document for demonstrating all features of this tool.
> It has no relation to any real research, person, organization, or data.
>
> **同梱の原稿はサンプル（パロディ）です**
> `src/paper.md` は本ツールの全機能をデモするための **明確なフィクション** です。
> 実在の研究・人物・機関・データとは一切関係ありません。

## Prerequisites / 前提条件

* **Docker** and **Docker Compose** (v2)
* **Make**
* **Git**

No Pandoc installation on the host is required; all builds run inside the Docker container.

ホストマシンへの Pandoc インストールは不要です。すべてのビルドは Docker コンテナ内で実行されます。

## Setup / セットアップ

### 1. Obtain the original abstract template / 抄録テンプレート原本の取得

Download the official abstract template from the distributor yourself (this repository does
not redistribute it).

- **Distributor**: <https://jami2026symp.org/abstracts-guide.html>
- Open the downloaded `.doc` in Microsoft Word and save it as `.docx`.
- Save to: `dist/abstract_template_en.docx`

公式の抄録テンプレートを配布元から各自ダウンロードしてください（本リポジトリでは再配布しません）。

- **配布元**: <https://jami2026symp.org/abstracts-guide.html>
- ダウンロードした `.doc` を Microsoft Word で開き、`.docx` 形式で保存
- 保存先: `dist/abstract_template_en.docx`

> This template is intended for submissions to the symposium of JAMI (the Japan Association for
> Medical Informatics) and to the society's English journal. This tool is an unofficial helper
> that reproducibly generates a compliant submission `.docx` from Markdown.
>
> このテンプレートは、**JAMI（日本医療情報学会）のシンポジウム**、および**同学会の英文誌
> （English journal）**への投稿を想定した公式テンプレートです。本ツールは、それに準拠した
> 提出用 `.docx` を Markdown から再現可能に生成するための非公式な補助ツールです。

### 2. Build the Docker image / Docker イメージのビルド

```bash
make docker-build
```

### 3. Prepare the template (copy + two-column + styles) / テンプレート準備（コピー + 2段組設定 + スタイル追加）

```bash
make reference
```

## Usage / 使い方

### Build (generate the Word file) / ビルド（Word ファイル生成）

```bash
make build              # or ./scripts/build.sh
```

Generates `dist/$(PROJECT_NAME).docx` (default: `jami2026_abstract`, configurable in `config.mk`).

`dist/$(PROJECT_NAME).docx` が生成されます（デフォルト: `jami2026_abstract`、`config.mk` で変更可能）。

### Diff review (color highlight) / 差分確認（カラーハイライト）

```bash
# Diff vs the previous commit (blue = added, red + strikethrough = deleted)
make diff               # or ./scripts/diff.sh

# Diff vs a specific revision
./scripts/diff.sh HEAD~3

# Direct comparison of two files (for peer review)
./scripts/diff.sh old.md src/paper.md

# Legacy tracked-changes mode
make diff-tracked       # or ./scripts/diff.sh --tracked-changes
```

Generates `dist/$(PROJECT_NAME)_diff.docx`.

`dist/$(PROJECT_NAME)_diff.docx` が生成されます。

### PDF conversion (Windows) / PDF 変換（Windows）

```
Drag and drop a docx file onto scripts/word-to-pdf.bat
  or
double-click scripts/word-to-pdf.bat (auto-selects the latest docx in the folder)
```

LibreOffice cannot render text boxes correctly, so PDF conversion uses Microsoft Word on Windows.

LibreOffice はテキストボックスを正しくレンダリングできないため、PDF 変換には
Windows 上の Microsoft Word を使用します。

### PDF conversion (from Linux, batch: roundtrip) / PDF 変換（Linux から一括: roundtrip）

A relay script to obtain Word-faithful PDFs while working on Linux. It invokes Word COM
conversion on Windows via Google Drive.

```bash
./scripts/roundtrip.sh                 # build → gdrive push → wait for PDF on Windows → pull to dist/
./scripts/roundtrip.sh --skip-build    # convert the existing dist docx as-is
./scripts/roundtrip.sh --dry-run       # show the plan only, without calling rclone
./scripts/roundtrip.sh --timeout 10    # PDF-wait timeout (minutes)
```

Linux 上で作業しつつ Word 忠実の PDF を得るための中継スクリプトです。
Google Drive を介して Windows の Word COM 変換を呼び出します。

> Flow: `[Linux] make build` → `push docx to gdrive:tmp/<repo>/` → `[Windows] watch-and-convert.ps1
> converts it to a same-named PDF via Word COM` → `[Linux] pull that PDF into dist/`.
>
> - **One-time Windows setup**: sync `tmp/<repo>/` with Google Drive desktop, place
>   `scripts/watch-and-convert.ps1` in that folder, and run it (Word required).
> - **Dependency**: `rclone` on the host (with a configured `gdrive:` remote). `--dry-run` does not call rclone.
> - Output is `dist/$(PROJECT_NAME).pdf`. No credentials are stored in the script; it relies on the rclone configuration.
>
> 流れ: `[Linux] make build` → `docx を gdrive:tmp/<repo>/ へ push` → `[Windows] watch-and-convert.ps1
> が Word COM で同名 PDF に変換` → `[Linux] その PDF を dist/ へ pull`。
>
> - **事前準備（Windows・1 回）**: Google Drive デスクトップで `tmp/<repo>/` を同期し、
>   そのフォルダに `scripts/watch-and-convert.ps1` を置いて起動（Word 必須）。
> - **依存**: host に `rclone`（`gdrive:` リモート設定済み）。`--dry-run` は rclone を呼びません。
> - 出力は `dist/$(PROJECT_NAME).pdf`。認証情報はスクリプトに含めず、rclone 設定に委ねます。

### Vector figures for slides (optional, host tools) / 発表スライド用ベクター図（任意・host ツール）

```bash
make fig-pptx                              # default src/figs/fig1.pdf (bring your own) → dist/figs/fig1.emf
./scripts/pdf-to-pptx-vector.sh my.pdf     # specify any PDF
```

Converts a PDF figure into an EMF vector for PowerPoint (text is converted to paths).
**Independent of the docx build** (not wired into `make build`/`all`).

> - **Host tools required (outside Docker)**: `ghostscript` (gs) and `inkscape` (>= 1.0).
> - **Bring your own PDF**: the default input `src/figs/fig1.pdf` is not bundled; provide your own.
> - If the input PDF or host tools are absent, it skips and exits (exit 0), so it never blocks the build or CI.
> - The output directory `dist/figs/` is gitignored.

PDF 図を PowerPoint 用 EMF ベクターへ変換します（テキストはパス化）。
**docx ビルドとは独立**（`make build`/`all` には結線されていません）。

> - **host ツール必須（Docker 外）**: `ghostscript`（gs）と `inkscape`（>= 1.0）。
> - **持込 PDF**: 既定入力 `src/figs/fig1.pdf` は同梱していません。自分の PDF を用意してください。
> - 入力 PDF または host ツールが無い場合は `skip` して終了（exit 0）するため、ビルドや CI を止めません。
> - 出力先 `dist/figs/` は `.gitignore` 済みです。

### Misc / その他

```bash
make clean              # remove dist/$(PROJECT_NAME)*.docx + *.pdf + src/figs/*.svg.png
make help               # list targets
```

## Directory structure / ディレクトリ構成

Key files and directories (the bundled manuscript, figures, and bibliography are samples).

主なファイルとディレクトリ（同梱の原稿・図・参考文献はサンプルです）。

```
.
├── CLAUDE.md                     # Settings for Claude Code
├── CITATION.cff                  # Citation metadata
├── LICENSE                       # MIT License
├── config.mk                     # Project settings (output file name)
├── Makefile                      # Build scripts (via Docker)
├── README.md                     # This file
├── SPEC.md                       # Technical specification
├── docker-compose.yml            # Docker Compose config
├── docker/
│   ├── pandoc/Dockerfile         # Pandoc build environment
│   └── mermaid-svg/Dockerfile    # Mermaid/SVG conversion environment
├── dist/                         # Output (generated artifacts are gitignored)
│   └── .gitkeep
│       # The original template dist/abstract_template_en.docx is obtained by you (not bundled)
├── filters/
│   ├── jami-style.lua            # Multi-pass: SVG→PNG path rewrite + body → body style + .textbox markers
│   └── color-diff.lua            # Diff color highlight (blue = added / red = deleted)
├── src/
│   ├── figs/                     # Images (PNG, JPG, SVG) — only sample figures are bundled
│   ├── paper.md                  # Manuscript body (bundled one is a sample = parody)
│   └── refs.bib                  # Bibliography database (bundled one is a sample)
├── templates/
│   ├── reference.docx            # Style-reference template (generated; gitignored)
│   └── jami.csl                  # Citation style (unofficial community version, numeric [1])
└── scripts/
    ├── build.sh                  # Build (with auto Docker/reference checks)
    ├── diff.sh                   # Diff highlight (color / tracked-changes modes)
    ├── fix-reference-cols.py     # reference.docx post-process (two-column + styles + numPr removal)
    ├── fix-svg-clips.py          # SVG text clipping fix (make fix-svg / build path; idempotent)
    ├── fix-svg-foreignobject.py  # Mermaid foreignObject → SVG text (make fix-svg; standalone; idempotent)
    ├── pdf-to-pptx-vector.sh     # PDF figure → EMF vector (make fig-pptx; host gs+inkscape; BYO PDF; not in build)
    ├── wrap-textbox.py           # docx post-process (booktabs + SVG embed + text-box conversion)
    ├── restore-textboxes.py      # diff: restore .textbox Divs in pandiff output
    ├── word-to-pdf.bat           # Windows: docx → PDF conversion (self-contained)
    ├── watch-and-convert.ps1     # Windows: watch a synced folder and auto-convert docx→PDF (for roundtrip)
    ├── roundtrip.sh              # build → gdrive push → Windows (Word COM) PDF → pull (via rclone)
    └── commit-push.sh            # commit & push
```

## Build pipeline / ビルドパイプライン

The build is a deterministic pipeline from Markdown to a template-compliant docx (and, on
Windows, to PDF).

Markdown からテンプレート準拠 docx（および Windows で PDF）までの決定的なパイプラインです。

```
src/paper.md + src/figs/*.svg
  → SVG→PNG conversion (rsvg-convert 300 DPI, *.svg → *.svg.png)
  → pandoc (crossref → jami-style.lua [.svg→.svg.png rewrite] → citeproc)
  → wrap-textbox.py --source src/paper.md output.docx
      1. apply booktabs rules
      2. native SVG embedding (Word 2016+: vector quality)
      3. TextBoxMarker → OOXML text-box conversion
      4. per-page anchor relocation
  → dist/$(PROJECT_NAME).docx
     (styles applied via templates/reference.docx; name set in config.mk)
  → word-to-pdf.bat (PDF conversion via Windows Word COM)
  → dist/$(PROJECT_NAME).pdf
```

### Reproducibility / 再現性

If you pass a fixed `SOURCE_DATE_EPOCH` at build time, the **content of every member of the
unzipped docx is deterministic** (`diff -r` shows no differences for the same input and the
same Docker image). This reproducibility assumes the same Docker image and the same fonts.
Note that the SHA-256 of the docx file itself changes every time because of ZIP timestamps
written by the `wrap-textbox.py` post-processing step (the unzipped member content stays identical).

ビルド時に環境変数 `SOURCE_DATE_EPOCH` を固定値で渡すと、出力 docx を unzip した
**全メンバの内容が決定的**（同一入力・同一 Docker イメージで `diff -r` 差分ゼロ）に
なります。これは同一 Docker イメージ・同一フォントを前提とした再現性です。
※ docx ファイル自体の SHA-256 は後処理 `wrap-textbox.py` の ZIP タイムスタンプにより
毎回変わります（unzip 後のメンバ内容は一致）。

## Notes / 注意事項

* **Final check**: before submitting, always open the generated Word file in MS Word and verify
  page breaks, figure placement, and character/page limits, adjusting as needed.
* **Figure/table numbering**: uses pandoc-crossref. Tag figures with `{#fig:label}` and tables
  with `{#tbl:label}`, and reference them in the bracketed form `[@fig:label]`.
* **Template**: the styles in `templates/reference.docx` (fonts, margins, etc.) determine the
  output's appearance. Do not control layout from the Markdown side.
* **Color diff**: `make diff` produces a diff with blue (added) / red + strikethrough (deleted).
* **SVG images**: put `.svg` files in `src/figs/` and reference them as `.svg` in Markdown. At build
  time a 300 DPI PNG fallback is generated and a native OOXML SVG is embedded.
* **Text boxes**: wrapping a table or figure in a `.textbox` Div outputs it as an OOXML text box,
  which you can drag to fine-tune its position in Word.

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

## License / ライセンス

The code in this repository is distributed under the **MIT License** (`LICENSE`). The official
abstract template (`dist/abstract_template_en.docx`, etc.) is **not bundled or redistributed**;
obtain it yourself from the official site.

本リポジトリのコードは **MIT License**（`LICENSE`）で配布します。
公式の抄録テンプレート（`dist/abstract_template_en.docx` 等）は **同梱・再配布しません**。
利用者が公式サイトから各自取得してください。
