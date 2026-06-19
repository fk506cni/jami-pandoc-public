# **SPEC.md**

> **非公式・非承認**: 本ツールはコミュニティ製であり、いかなる学会・団体の公式物・
> 承認物でもありません。引用スタイル `templates/jami.csl` も非公式 community 版です。
> 公式の抄録テンプレートは同梱せず、利用者が各自取得します（README 参照）。

## **System Architecture**

### **Docker Container (pandoc service)**

```
Host (make build / make diff / ./scripts/*.sh)
  |
  v
docker compose run --rm pandoc
  |
  v
Container (Ubuntu 24.04)
  +-- pandoc 3.6.4 (GitHub release .deb)
  +-- pandoc-crossref 0.3.19 (GitHub release, Pandoc 3.6.4 対応)
  +-- pandiff 0.8.0 (npm)
  +-- rsvg-convert (librsvg2-bin, SVG→PNG 変換)
  +-- Japanese fonts (Noto CJK, IPA Mincho, IPA Gothic)
  +-- git, nodejs, perl, python3
  |
  v
src/paper.md
  --> SVG→PNG 変換 (rsvg-convert 300 DPI, *.svg → *.svg.png)
  --> pandoc (crossref → jami-style.lua [.svg→.svg.png 書換] → citeproc)
  --> wrap-textbox.py --source src/paper.md output.docx
      1. booktabs 罫線適用
      2. SVG ネイティブ埋め込み (a:blip に asvg:svgBlob 拡張)
      3. TextBoxMarker → OOXML テキストボックス変換
      4. ページ別アンカー再配置
  --> dist/$(PROJECT_NAME).docx
       (styled by templates/reference.docx)
       PROJECT_NAME は config.mk で設定（default: jami2026_abstract）

Host (Windows のみ)
  --> scripts/word-to-pdf.bat (Word COM, 自己完結型)
  --> dist/$(PROJECT_NAME).pdf
```

### **Dockerfile ARGs**

| ARG | Value | Purpose |
|:----|:------|:--------|
| `PANDOC_VERSION` | 3.6.4 | Pandoc .deb バージョン |
| `CROSSREF_VERSION` | 0.3.19 | pandoc-crossref バージョン (Pandoc と一致必須) |

### **Input**

* **Format**: Pandoc Markdown (with `east_asian_line_breaks` extension)
* **Encoding**: UTF-8
* **Bibliography**: BibTeX (.bib)
* **Images**: PNG, JPG, SVG (placed in src/figs/)
  - SVG: ビルド時に rsvg-convert で 300 DPI PNG フォールバック自動生成 + OOXML ネイティブ SVG 埋め込み
  - Word 2016+ は SVG をベクター表示、古い Word は PNG フォールバック表示

### **Transformation Engine**

* **Core**: Pandoc 3.6.4
* **Filters** (applied in this order):
  1. pandoc-crossref 0.3.19: Figure/Table numbering and cross-referencing
  2. filters/jami-style.lua: Multi-pass filter — Pass 1: SVG→PNG パス書換 (Image)、Pass 2: 本文スタイルラップ + textbox マーカー (Pandoc)
  3. citeproc (built-in): Bibliography formatting via CSL
* **Diff filter**: filters/color-diff.lua: Convert .diff-add/.diff-del spans to colored OOXML
* **Post-processing**:
  - scripts/fix-reference-cols.py: reference.docx の 2 段組設定 + 不足スタイル追加 + numPr 削除
  - scripts/wrap-textbox.py: Pandoc 出力 docx の booktabs 罫線適用 → SVG ネイティブ埋め込み → TextBoxMarker → OOXML テキストボックス変換 → ページ別アンカー再配置
* **Diff 後処理**: scripts/restore-textboxes.py: pandiff 出力の HTML テーブル/図 diff を除去し、NEW ファイルの .textbox Div ブロックを復元
* **PDF 変換**: scripts/word-to-pdf.bat (Windows Word COM, 自己完結型、OpenAndRepair + PDF 出力)

### **Output**

* **Format**: Microsoft Word (.docx)
* **SVG Support**: Word 2016+ ではネイティブ SVG（ベクター品質）、それ以前は PNG フォールバック表示
* **Styling Source**: templates/reference.docx (公式テンプレートを .docx 化したもの。利用者が各自取得)

### **Reproducibility (決定的ビルド)**

* ビルド時に `SOURCE_DATE_EPOCH` を固定値で渡すと、出力 docx を unzip した **全メンバの内容が決定的**（同一入力・同一 Docker イメージで `diff -r` 差分ゼロ）になる。
* 配線: `docker-compose.yml` の `environment` に `SOURCE_DATE_EPOCH` を透過し、`SOURCE_DATE_EPOCH=<固定値> make build` で起動する。
* 範囲: 決定性は **同一 Docker イメージ・同一フォント** を前提とする（別イメージはライブラリ/フォント差で一致保証なし）。
* docx ファイル自体の SHA-256 は後処理 `wrap-textbox.py` の ZIP タイムスタンプにより毎回変わる（unzip 後のメンバ内容は一致）。

## **Pandoc Options Specification**

| Flag | Purpose |
|:-----|:--------|
| `--from markdown+east_asian_line_breaks` | Japanese line breaking (prevents extra spaces) |
| `--to docx` | Output format |
| `--reference-doc=templates/reference.docx` | Style mapping from template |
| `--filter pandoc-crossref` | Cross-referencing (Fig 1., Table 1.) |
| `--lua-filter=filters/jami-style.lua` | Map body Para to 本文 style |
| `--citeproc` | Process citations |
| `--bibliography=src/refs.bib` | Reference source |
| `--csl=templates/jami.csl` | Citation style (numeric, [1] format, conditional) |
| `--output=dist/$(PROJECT_NAME).docx` | Output path (PROJECT_NAME from config.mk) |

## **テンプレートスタイル仕様**

templates/reference.docx（公式テンプレート .docx を cp + fix-reference-cols.py で後処理）に定義されたスタイル:

### テンプレート由来のスタイル

| スタイル名 | Style ID | フォント | サイズ | 配置 | 用途 |
|:-----------|:---------|:---------|:-------|:-----|:-----|
| JSEK本文 | JSEK | Times New Roman (eastAsia: MS P明朝) | 10pt | 両端揃え, 字下げ100 | 本文段落 |
| 標題（日本語） | a4 | Arial / MS Gothic | 14pt | 中央 | 日本語タイトル |
| 著者（日本語） | a6 | Times New Roman | 10pt | 中央 | 日本語著者 |
| 所属機関（日本語） | ab | Times New Roman | 10pt | 中央 | 日本語所属 |
| 標題（英語） | a7 | Times New Roman | 14pt | 中央 | 英語タイトル |
| 著者（英語） | a9 | Times New Roman | 10pt | 中央 | 英語著者 |
| 所属機関（英語） | aa | Times New Roman | 10pt | 中央 | 英語所属 |
| Heading 2 | 2 | Arial | 9pt | — | セクション見出し |

### fix-reference-cols.py が追加するスタイル

| スタイル名 | Style ID | ベース | 用途 |
|:-----------|:---------|:-------|:-----|
| Compact | Compact | JSEK | 表セル（9pt, インデントなし, 行間詰め） |
| Heading 3 | Heading3 | 2 | サブセクション見出し |
| Table Caption | TableCaption | JSEK | 表キャプション（9pt, インデントなし） |
| Image Caption | ImageCaption | JSEK | 図キャプション（9pt, 中央寄せ） |
| Bibliography | Bibliography | JSEK | 参考文献（9pt, インデントなし） |
| Figure Table | FigureTable | af0 | Pandoc テーブルスタイル |
| Table | Table | af0 | Pandoc テーブルスタイル |
| CaptionedFigure | CaptionedFigure | ImageCaption | Pandoc 図キャプション段落（破損警告防止） |
| TextBoxMarker | TextBoxMarker | — | テキストボックスマーカー（vanish, 1pt, Lua→wrap-textbox.py 連携用） |

### fix-reference-cols.py が行うスタイル修正

- Heading 2 の `numPr` 削除（Word 自動番号を無効化）
- Heading 3 に `numId=0` 設定（Heading 2 からの numPr 継承防止）
- body-level `sectPr` を 2 段組 continuous に設定
- 中間 `sectPr`（段落内）を削除

> **実装済み**: `filters/jami-style.lua` が本文 Para を `JSEK本文` スタイルでラップ。標題・著者・所属は `src/paper.md` の `custom-style` Div で直接指定。

## **pandiff (Diff Highlighting)**

pandiff は2つの Markdown ソースの差分を Word ファイルとして出力する。

### カラーハイライトモード（デフォルト）

パイプライン（9ステップ）:

```
Step 1: pandiff -t markdown OLD NEW → CriticMarkup markdown
Step 2: perl でバックスラッシュエスケープ解除 (\~ → ~, \> → >, \@ → @, \[ → [, \] → ])
Step 3: perl で壊れた CriticMarkup 修復 ({~~A~>B}shared{C~>D~~} → {~~A~>B~~}shared{~~C~>D~~})
Step 4: NEW ファイルのヘッダ（YAML + custom-style Div + sectPr）+ pandiff のボディ（## 1. 以降）をマージ
Step 5: restore-textboxes.py — pandiff の HTML <table> / 図 diff を除去し、NEW ファイルの .textbox Div を復元
Step 6: perl で CriticMarkup → bracketed spans 変換 ({++text++} → [text]{.diff-add} 等)
Step 7: pandoc (crossref → jami-style.lua → color-diff.lua → citeproc) → docx
Step 8: wrap-textbox.py --source "$NEW_MD" — booktabs + SVG 埋め込み + テキストボックス + ページ再配置
Step 9: 完了
```

* **追加テキスト**: 青色 (#2E74B5)
* **削除テキスト**: 赤色 (#C00000) + 取消線
* **Command**: `./scripts/diff.sh [REV]` (default HEAD~1)
* **Command (2-file)**: `./scripts/diff.sh old.md new.md`
* **Output**: `dist/$(PROJECT_NAME)_diff.docx`

### カラーハイライトモードの既知の制限

* テキストボックス内のテーブルセル値には差分ハイライトが適用されない（NEW ファイルの値を表示）
* ヘッダ部分（Abstract, Keywords, 抄録, キーワード）の差分注釈は失われる（NEW ファイルの内容をそのまま使用）
* pandiff が生成する CriticMarkup の一部は修復しきれない場合がある

### 変更履歴モード（--tracked-changes）

* **Command**: `./scripts/diff.sh --tracked-changes [REV]`
* **Output**: `dist/$(PROJECT_NAME)_diff.docx`（Word 変更履歴形式）

## **Makefile Targets**

| Target | Description |
|:-------|:------------|
| `build` (default) | Build `dist/$(PROJECT_NAME).docx` from `src/paper.md`（SVG→PNG + pandoc + wrap-textbox.py） |
| `pdf` | PDF 変換手順を表示（Windows Word COM 経由） |
| `diff` | Generate color-highlighted diff docx (via scripts/diff.sh) |
| `diff-tracked` | Generate diff docx with tracked changes (legacy mode) |
| `fix-svg` | `src/figs/*.svg` に foreignObject 変換 + クリッピング修正を in-place 適用（独立・冪等、build 非結線） |
| `fig-pptx` | `src/figs/<name>.pdf` → `dist/figs/<name>.emf`（PowerPoint 用ベクター。**host の gs+inkscape 必須**・持込 PDF・build 非結線、入力/ツール欠如時は skip exit 0） |
| `reference` | Copy template `.docx` → `templates/reference.docx` + fix-reference-cols.py |
| `clean` | Remove `dist/$(PROJECT_NAME)*.docx`, `*.pdf`, and `src/figs/*.svg.png` |
| `docker-build` | Build the Docker image |
| `help` | Show all available targets |

## **Scripts**

| Script | Usage | Description |
|:-------|:------|:------------|
| `build.sh` | `./scripts/build.sh` | Docker image/reference.docx を自動チェックしてビルド |
| `diff.sh` | `./scripts/diff.sh [REV]` | カラーハイライト差分 (デフォルト HEAD~1) |
| `diff.sh` | `./scripts/diff.sh old.md new.md` | 2ファイル直接比較（査読対応） |
| `diff.sh` | `./scripts/diff.sh --tracked-changes [REV]` | 変更履歴モード（従来方式） |
| `fix-reference-cols.py` | `python3 scripts/fix-reference-cols.py <ref.docx>` | reference.docx の 2 段組化 + スタイル追加 + numPr 削除 |
| `fix-svg-clips.py` | `python3 scripts/fix-svg-clips.py <svg>...` | R/ggplot2 系 SVG の text クリッピング修正（冪等・in-place） |
| `fix-svg-foreignobject.py` | `python3 scripts/fix-svg-foreignobject.py <svg>...` | Mermaid SVG の `<foreignObject>` → ネイティブ `<text>` 変換（冪等・in-place、独立） |
| `pdf-to-pptx-vector.sh` | `./scripts/pdf-to-pptx-vector.sh [input.pdf]` | PDF 図 → EMF ベクター（PowerPoint 用）。**host の gs+inkscape 必須**・持込 PDF。入力/ツール欠如時は skip exit 0 |
| `wrap-textbox.py` | `python3 scripts/wrap-textbox.py [--source paper.md] <output.docx>` | booktabs + SVG 埋め込み + テキストボックス変換（in-place） |
| `restore-textboxes.py` | `diff.sh` から呼び出し | diff マークダウンに NEW ファイルの .textbox Div を復元 |
| `word-to-pdf.bat` | ドラッグ&ドロップ or ダブルクリック | Windows Word COM で docx 修復 + PDF 変換（自己完結型） |
| `commit-push.sh` | `./scripts/commit-push.sh` | コミット & プッシュ（`git push origin <branch>`） |

## **config.mk（プロジェクト設定）**

出力ファイル名のベース名を管理する設定ファイル。Makefile、diff.sh が参照する。

```makefile
# Project configuration — output filename stem
PROJECT_NAME := jami2026_abstract
```

* Makefile: `-include config.mk` + `PROJECT_NAME ?= jami2026_abstract`（フォールバック）
* diff.sh: `grep + sed` でパース、フォールバック付き
* 別論文で再利用する際は `PROJECT_NAME` を変更するだけで出力ファイル名が切り替わる

## **File Specifications**

### **src/paper.md**

* YAML front matter: pandoc-crossref settings only (`figPrefix`, `tblPrefix`, `secPrefix` — トップレベル、`crossref:` ネスト不可)
* Header blocks use `custom-style` Divs for styles:
  - `標題（日本語）`, `著者（日本語）`, `所属機関（日本語）`
  - `標題（英語）`, `著者（英語）`, `所属機関（英語）`
* Abstract / Keywords / 抄録 / キーワードはインラインラベル形式（見出しではない）
* Raw OOXML セクション区切り: キーワード後に `{=openxml}` で 1 段→2 段組切替
* Sections: 1.はじめに ~ 5.結論, 参考文献（手動番号付き見出し）
* Figures: `![Caption](src/figs/image.png){#fig:label}` or `![Caption](src/figs/image.svg){#fig:label}`
  - SVG: markdown では `.svg` 拡張子で参照。Lua フィルタが `.svg.png` に書換、wrap-textbox.py がネイティブ SVG を埋め込む
* Tables: Standard Markdown tables with `{#tbl:label}` caption suffix
* Cross-refs: `[@fig:label]`, `[@tbl:label]`（括弧形式 — CJK テキスト内で必須）
  - `figPrefix: "Figure"` → 本文中 "Figure 1" 形式で出力
  - `tblPrefix: "Table"` → 本文中 "Table 1" 形式で出力
* Citations: `[@key]`, `[@key1; @key2]`
* テキストボックス: `.textbox` クラスの Div で囲み、属性で位置・サイズを指定:
  ```markdown
  ::: {.textbox width="71mm" height="35mm" pos-x="109mm" pos-y="168mm" page="1"}
  (table or figure content)
  :::
  ```
  - 属性: `width`, `height`, `pos-x`, `pos-y`, `anchor-h`, `anchor-v`, `wrap`, `behind`, `valign`, `page`
  - `valign="bottom"`: 図用（キャプションが下端に配置）
  - `valign="top"` (デフォルト): 表用（タイトルが上端に配置）
  - `page="N"`: テキストボックスをページ N に配置（アンカー段落を該当ページ位置に移動）
* テーブルスタイル:
  - デフォルト: 三線表（booktabs）— ヘッダ行上下 + 最終行下に罫線、縦線なし
  - `.grid` Div で囲むと全罫線テーブル（booktabs 適用をスキップ）

### **templates/jami.csl**

* CSL 1.0 numeric citation style（非公式 community 版）
* In-text: `[1]`, `[2, 3]`, `[4-6]` (collapse citation-number)
* Bibliography: `[N] Author. Title. Journal (italic). Vol(Issue): Pages. Year.`

### **templates/reference.docx**

* Generated from the template `.docx` via `make reference` (cp + fix-reference-cols.py)
* fix-reference-cols.py が body sectPr を 2 段組 continuous に設定し、不足スタイルを追加
* Contains Word styles that control all visual formatting (fonts, margins, spacing)
* **NEVER** edit manually — regenerate with `make reference` if needed
* git 管理外 (`.gitignore` に含まれる)

## **解決済みの問題**

| 問題 | 原因 | 対応 |
|:-----|:-----|:-----|
| docx 破損警告 | `CaptionedFigure` スタイル未定義 + `mc:Ignorable` 属性欠落 | fix-reference-cols.py にスタイル追加 + wrap-textbox.py で mc:Ignorable="wps wp14" 付与 |
| セクション番号重複 | Heading 2 の `numPr` + 手動番号 | fix-reference-cols.py で numPr 削除 + Heading3 に numId=0 |
| テーブル/図の配置調整困難 | 通常段落として出力 | テキストボックス化（jami-style.lua マーカー + wrap-textbox.py 後処理） |
| PDF 出力なし | 未実装 | Windows Word COM 変換（word-to-pdf.bat）※ LibreOffice はテキストボックス非対応のため不採用 |
