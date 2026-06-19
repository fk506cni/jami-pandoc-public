# **CLAUDE.md**

## **Project Overview**

* **Goal**: Generate a template-compliant Microsoft Word (.docx) conference abstract from Markdown source using Pandoc.
* **Context**: The workflow favors a LaTeX-like content/style separation while producing a strict Word-template output.
* **Output**: `dist/$(PROJECT_NAME).docx` (configured via `config.mk`, default: `jami2026_abstract`)

> **Unofficial / Not endorsed**: This is a community-made tool, not an official or
> endorsed product of any association. The bundled `src/paper.md` is a clearly
> fictional (parody) sample. The official abstract template is **not bundled**;
> download it yourself (see README).

## **Build Commands**

All builds run inside a Docker container via `docker compose`.

| Command | Description |
|:--------|:------------|
| `make build` | Build the abstract docx (default target) |
| `make diff` | Generate color-highlighted diff docx (blue=add, red=del) |
| `make diff-tracked` | Generate diff docx with tracked changes (legacy) |
| `make reference` | Copy the template `.docx` → templates/reference.docx + fix styles |
| `make clean` | Remove generated docx, PDF, SVG PNG files |
| `make docker-build` | Build the Docker image |
| `make help` | Show all targets |

### Shell Scripts

| Script | Description |
|:-------|:------------|
| `./scripts/build.sh` | Build with auto Docker image/reference.docx check |
| `./scripts/diff.sh [REV]` | Color diff vs git revision (default HEAD~1) |
| `./scripts/diff.sh old.md new.md` | Color diff between two markdown files (査読対応) |
| `./scripts/commit-push.sh` | Commit and push (`git push origin <branch>`) |
| `scripts/word-to-pdf.bat` | Windows: ドラッグ&ドロップ or ダブルクリックで docx → PDF 変換（自己完結型） |

## **Project Structure**

```
.
├── config.mk                   # プロジェクト設定（出力ファイル名 PROJECT_NAME）
├── docker/pandoc/Dockerfile    # Pandoc ビルド環境
├── docker/mermaid-svg/         # Mermaid/SVG 変換環境（別用途）
├── docker-compose.yml
├── Makefile                    # ビルド自動化（Docker 経由、config.mk 参照）
├── CITATION.cff                # 引用情報
├── LICENSE                     # MIT License
├── templates/
│   ├── reference.docx          # スタイル参照テンプレート（生成物、git 管理外）
│   └── jami.csl                # 引用スタイル（非公式 community 版、numeric [1] 形式）
├── dist/
│   └── .gitkeep                # 出力先（テンプレート原本は各自取得・同梱せず）
├── filters/
│   ├── jami-style.lua          # Multi-pass: SVG→PNG パス書換 + 本文 Para → 本文スタイル + .textbox マーカー
│   └── color-diff.lua          # 差分カラーハイライト（青/赤 OOXML）
├── src/
│   ├── paper.md                # 原稿本文（同梱はサンプル＝パロディ）
│   ├── refs.bib                # 参考文献（同梱はサンプル）
│   └── figs/                   # 画像（PNG, JPG, SVG 対応／同梱はサンプル図のみ）
└── scripts/
    ├── build.sh                # ビルド（Docker/reference 自動チェック付き）
    ├── diff.sh                 # 差分ハイライト（カラー/変更履歴 切替対応、9ステップパイプライン）
    ├── fix-reference-cols.py   # reference.docx 後処理（2段組+スタイル追加+numPr削除）
    ├── fix-svg-clips.py        # SVG text クリッピング修正（make fix-svg / ビルド経路で呼出、冪等）
    ├── fix-svg-foreignobject.py # Mermaid SVG foreignObject→ネイティブtext変換（make fix-svg、独立・ビルド非結線、冪等）
    ├── pdf-to-pptx-vector.sh   # PDF図→EMFベクター（make fig-pptx、host gs+inkscape必須・持込PDF・build非結線・欠如時skip）
    ├── wrap-textbox.py         # docx 後処理（booktabs + SVG 埋め込み + テキストボックス変換）
    ├── restore-textboxes.py    # diff 用: pandiff 出力に .textbox Div を復元
    ├── word-to-pdf.bat         # Windows: docx → PDF 変換（自己完結型、ドラッグ&ドロップ / ダブルクリック）
    └── commit-push.sh          # コミット & プッシュ
```

## **Docker Container**

* **Base**: Ubuntu 24.04
* **Pandoc**: 3.6.4 (GitHub release .deb)
* **pandoc-crossref**: 0.3.19 (Pandoc 3.6.4 対応)
* **pandiff**: 0.8.0 (npm)
* **rsvg-convert**: librsvg2-bin (SVG→PNG 変換)
* **Fonts**: Noto CJK, IPA Mincho, IPA Gothic

## **テンプレートスタイル**

reference.docx に定義された主要スタイル:

| スタイル名 | 用途 | フォント/サイズ |
|:-----------|:-----|:----------------|
| JSEK本文 | 本文段落 | Times New Roman 10pt |
| 標題（日本語） | 日本語タイトル | Arial/MS Gothic 14pt center |
| 著者（日本語） | 日本語著者 | Times New Roman 10pt center |
| 所属機関（日本語） | 日本語所属 | Times New Roman 10pt center |
| 標題（英語） | 英語タイトル | Times New Roman 14pt center |
| 著者（英語） | 英語著者 | Times New Roman 10pt center |
| 所属機関（英語） | 英語所属 | Times New Roman 10pt center |
| Heading 2 | セクション見出し | Arial 9pt |

fix-reference-cols.py が追加するスタイル: Compact, Heading3, TableCaption, ImageCaption, Bibliography, FigureTable, Table, CaptionedFigure, TextBoxMarker

> `filters/jami-style.lua` が本文 Para → JSEK本文 を自動適用。標題・著者・所属は `custom-style` Div で指定。`.textbox` Div は Lua フィルタがマーカーを出力し、wrap-textbox.py が OOXML テキストボックスに変換。

## **Coding Style & Guidelines**

* **Markdown**: Use Pandoc's extended Markdown.
* **Citations**: Use @key format. Manage via BibTeX (refs.bib).
* **Figures/Tables**: Use pandoc-crossref syntax (e.g., `![Caption](src/figs/image.png){#fig:id}`). SVG 画像は `.svg` 拡張子で参照（ビルド時に PNG フォールバック自動生成 + ネイティブ SVG 埋め込み）。
* **Cross-refs**: Use bracketed form `[@fig:id]`, `[@tbl:id]` (CJK テキスト内で必須).
* **Template Styles**: Use `custom-style` Div for 固有スタイル（標題, 著者, 所属等）。本文段落は `filters/jami-style.lua` が自動で JSEK本文 にマッピング。
* **Template**: **NEVER** modify visual layout in Markdown. Rely on templates/reference.docx styles.
* **Math**: Use standard LaTeX math syntax (`$..$` for inline, `$$..$$` for block).
* **Section breaks**: Use raw OOXML `{=openxml}` blocks for layout transitions (e.g., 1 段→2 段組).
* **Textboxes**: Use `.textbox` Div with attributes (`width`, `height`, `pos-x`, `pos-y`, `valign`, `page` etc.) to position tables/figures. `valign="bottom"` for figures, default `"top"` for tables. `page="N"` で配置先ページを指定。
* **Tables**: デフォルトで三線表（booktabs）スタイル。全罫線が必要な場合は `.grid` Div で囲む。

## **Critical Instructions for AI**

* **config.mk**: `PROJECT_NAME` で出力ファイル名を設定。Makefile（`-include`）、diff.sh が参照。デフォルト `jami2026_abstract`。
* When the user asks to "build" or "generate", run `make build`.
* If styling looks wrong, suggest modifying templates/reference.docx styles, not Markdown.
* All build commands execute inside Docker — do NOT assume tools are on the host.
* Run `make docker-build` first if the Docker image does not exist.
* Run `make reference` to generate templates/reference.docx before the first build (the template `.docx` must be downloaded first; see README).
* **Lua Filters**: `filters/jami-style.lua` (multi-pass: Pass 1 で SVG→PNG パス書換、Pass 2 で body Para → JSEK本文 + .textbox/.grid マーカー) and `filters/color-diff.lua` (diff color highlight) are applied automatically. Filter order: pandoc-crossref → jami-style.lua → citeproc.
* **Post-processing**: `scripts/wrap-textbox.py --source src/paper.md output.docx` — booktabs 罫線適用 → SVG ネイティブ埋め込み → TextBoxMarker → OOXML テキストボックス変換 → ページ別アンカー再配置。Called automatically by `make build` and `scripts/diff.sh`。`--source` なしでも後方互換（SVG 埋め込みスキップ）。
* **SVG fix (manual)**: `make fix-svg` が `scripts/fix-svg-foreignobject.py`（Mermaid `<foreignObject>`→ネイティブ `<text>`）→ `scripts/fix-svg-clips.py`（text クリッピング修正）を `src/figs/*.svg` に in-place 適用（いずれも冪等）。**独立ターゲットで build 経路には未結線**。foreignObject を含む SVG（Mermaid 由来）を追加した場合のみ `make fix-svg` を実行してから build する。
* **Slide vector (manual)**: `make fig-pptx`（`scripts/pdf-to-pptx-vector.sh`）が PDF 図を `dist/figs/<name>.emf`（PowerPoint 用ベクター）へ変換。**host の gs+inkscape が必須（Docker 外）・入力 PDF は持込**。**build/all には未結線の独立ターゲット**で、入力 PDF または host ツール欠如時は `skip` して **exit 0**。出力先 `dist/figs/` は `.gitignore` 済み。
* **Diff post-processing**: `scripts/restore-textboxes.py` — pandiff が破壊した .textbox Div を NEW ファイルから復元。`scripts/diff.sh` の Step 5 で呼び出される。
* **Diff pipeline**: `scripts/diff.sh` は9ステップで処理: pandiff → unescape → CriticMarkup修復 → ヘッダ復元 → テキストボックス復元 → spans変換 → pandoc → wrap-textbox。テーブルセル値の差分ハイライトは非対応。
* **PDF conversion**: Use `scripts/word-to-pdf.bat` on Windows (Word COM). LibreOffice はテキストボックスを正しくレンダリングできないため不採用。
* **Reproducibility**: ビルド時に `SOURCE_DATE_EPOCH` を固定値で渡すと、出力 docx を unzip した全メンバ内容が決定的（同一 Docker イメージ前提）。`docker-compose.yml` の `environment` に `SOURCE_DATE_EPOCH` を透過し、`SOURCE_DATE_EPOCH=<固定値> make build` で起動する。docx ファイル自体の SHA は後処理の ZIP タイムスタンプで変わる（unzip 後のメンバ内容は一致）。
