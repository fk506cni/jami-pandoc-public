# demo — pre-built sample outputs / ビルド済みサンプル成果物

`../src/paper.md`（明確にフィクションのサンプル詳細抄録）を本ツールでビルドした成果物です。
ツールを動かさなくても、生成される docx / PDF の実物を確認できます。

Pre-built outputs of `../src/paper.md` (a clearly fictional sample detailed abstract),
so you can see exactly what this tool produces without running it yourself.

| file | how it was produced |
|:-----|:--------------------|
| `jami2026_abstract.docx` | `make build`（Pandoc + Docker）で生成した JAMI テンプレート準拠の docx |
| `jami2026_abstract.pdf`  | 上記 docx を Microsoft Word（Word COM）で PDF 化したもの（A4・4 頁） |

- 再現手順は [`../README.md`](../README.md) / [`../SPEC.md`](../SPEC.md) を参照。
- JAMI 公式テンプレートは同梱しません。`make reference` には別途テンプレートの取得が必要です（`../README.md` 参照）。
- これらはすべてサンプル（フィクション）であり、実在の研究・人物・機関・データとは一切関係ありません。
- PDF は変換時刻を含むため毎回バイト一致はしません（docx の決定性とは別。詳細は `../SPEC.md`）。
