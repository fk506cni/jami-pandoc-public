#!/usr/bin/env bash
# pdf-to-pptx-vector.sh — Convert a PDF figure to a PowerPoint-ready vector (EMF).
#
# WHY THIS EXISTS
#   Mermaid-generated SVG (src/figs/fig1.svg) stores fills in an embedded
#   <style> block (CSS classes). PowerPoint's SVG importer ignores that block,
#   so boxes fall back to black. The PDF (src/figs/fig1.pdf) has colors baked
#   in and keeps the desired layout — but its Japanese text is embedded as
#   Type3 fonts (NotoSansCJKjp), which Inkscape/poppler silently DROP on
#   conversion. So we first OUTLINE all text to paths (Ghostscript
#   -dNoOutputFonts), then export EMF — PowerPoint's native vector metafile.
#   Result: every box and glyph survives, renders identically on any machine,
#   and the EMF can be ungrouped into editable shapes inside PowerPoint.
#   Trade-off: text becomes paths, so it is no longer editable as text.
#
# OUTPUT
#   dist/figs/<name>.emf   (kept OUTSIDE src/figs/ on purpose — see below)
#
# NON-DESTRUCTIVE BY DESIGN
#   The docx build globs src/figs/*.svg (Makefile SVG_SRCS), runs
#   fix-svg-clips.py on each IN PLACE, and emits *.svg.png. Writing PowerPoint
#   artifacts into src/figs/ would get them swept into that build. This script
#   therefore writes only to dist/figs/ and never touches src/figs/ or the
#   docx pipeline.
#
# USAGE
#   scripts/pdf-to-pptx-vector.sh [input.pdf]      # default: src/figs/fig1.pdf
#
# REQUIREMENTS (host tools — NOT the pandoc Docker image)
#   - ghostscript (gs)
#   - inkscape (>= 1.0)
#
# SKIP-BY-DESIGN (ported to jami-abstract-pandoc)
#   This is an INDEPENDENT slide-prep helper (Makefile target `fig-pptx`), not
#   wired into `make build`/`all`. The default input src/figs/fig1.pdf is NOT
#   shipped here — bring your own PDF. When the input PDF is missing, or the
#   host tools gs/inkscape are absent, the script prints `skip` and exits 0
#   (NOT 1) so it never breaks an unrelated build/CI invocation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IN_PDF="${1:-$ROOT_DIR/src/figs/fig1.pdf}"
if [[ ! -f "$IN_PDF" ]]; then
  echo "skip: input PDF not found: $IN_PDF" >&2
  echo "      (bring-your-own; default src/figs/fig1.pdf is not shipped)" >&2
  exit 0
fi

BASE="$(basename "$IN_PDF" .pdf)"
OUT_DIR="$ROOT_DIR/dist/figs"
OUT_EMF="$OUT_DIR/${BASE}.emf"

# Required host tools (this runs on the host, not inside the pandoc container).
for tool in gs inkscape; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "skip: required host tool '$tool' not found in PATH." >&2
    echo "      This script runs on the host, not the pandoc Docker image." >&2
    exit 0
  fi
done

mkdir -p "$OUT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
OUTLINED_PDF="$TMP_DIR/${BASE}_outlined.pdf"
CROP_SVG="$TMP_DIR/${BASE}_crop.svg"

echo "[1/3] Outlining all text to paths (Ghostscript) ..."
gs -q -sDEVICE=pdfwrite -dNoOutputFonts -o "$OUTLINED_PDF" "$IN_PDF"

# Crop to the drawing bbox here (Inkscape's --export-area-drawing works for SVG
# but is ignored for direct EMF export, so we crop via the SVG intermediate).
echo "[2/3] Outlined PDF -> cropped plain SVG (Inkscape) ..."
inkscape "$OUTLINED_PDF" \
  --export-area-drawing \
  --export-type=svg --export-plain-svg \
  -o "$CROP_SVG" >/dev/null 2>&1

echo "[3/3] Cropped SVG -> EMF (Inkscape) ..."
inkscape "$CROP_SVG" --export-type=emf -o "$OUT_EMF" >/dev/null 2>&1

echo "Done: ${OUT_EMF#"$ROOT_DIR"/}"
echo "Insert in PowerPoint: 挿入 > 画像 > このデバイス  (right-click > グループ解除 to edit shapes)"
