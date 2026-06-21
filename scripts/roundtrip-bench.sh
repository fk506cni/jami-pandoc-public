#!/usr/bin/env bash
# roundtrip-bench.sh — roundtrip(build -> PDF) の所要時間と成果物ハッシュを実測し JSON 記録
# =============================================================================
# build(docx 生成) と roundtrip(Windows の Word COM 経由で PDF 化)の所要時間、
# 生成された docx / pdf の SHA-256・サイズ・PDF 頁数を計測し、dist/ に JSON で保存する。
#
# 前提: scripts/roundtrip.sh と同じ（rclone 設定済み・Windows 側 watch-and-convert.ps1 稼働・
#       templates/reference.docx を make reference で用意済み）。詳細は README.md / SPEC.md。
#
# 使い方:
#   ./scripts/roundtrip-bench.sh [--skip-build] [roundtrip.sh のオプション...]
#     --skip-build         : docx ビルドを省略し、既存 dist の docx で計測（build 時間は null）
#     --timeout MIN/--poll SEC 等は roundtrip.sh にそのまま渡す
#   出力: dist/roundtrip-bench_<UTC タイムスタンプ>.json
#
# 再現性メモ:
#   docx ファイルの SHA-256 は後処理(wrap-textbox.py)の ZIP タイムスタンプで毎回変わる
#   （中身は決定的）。本スクリプトは「展開メンバ内容の SHA-256(members_sha256)」も併記する。
#   members_sha256 を毎回一致させたい（決定性を確認したい）場合は、実行前に
#   SOURCE_DATE_EPOCH を固定値で export すること（例: SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)）。
#   PDF は変換時刻を含むため SHA-256 は毎回変わる（参考値）。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# 出力ファイル名 stem（config.mk から。roundtrip.sh と同じ流儀）
OUTPUT_NAME="$(grep '^PROJECT_NAME' config.mk 2>/dev/null | sed 's/.*:=[[:space:]]*//' | tr -d ' ')"
OUTPUT_NAME="${OUTPUT_NAME:-jami2026_abstract}"
DOCX="dist/${OUTPUT_NAME}.docx"
PDF="dist/${OUTPUT_NAME}.pdf"

# --- 引数解析（--skip-build は自前で扱い、他は roundtrip.sh へ渡す）---
SKIP_BUILD=false
RT_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) RT_ARGS+=("$1"); shift ;;
  esac
done

# --- ヘルパー ---
now() { date +%s.%N; }
secdiff() { awk "BEGIN{printf \"%.3f\", $2-$1}"; }
sha256_file()   { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
sha256_stream() { if command -v sha256sum >/dev/null 2>&1; then sha256sum;     else shasum -a 256;     fi | awk '{print $1}'; }
# docx の展開メンバ内容を決定的に連結したハッシュ（メンバ名を昇順ソートして内容連結）
docx_members_sha256() {
  local f="$1" d; d="$(mktemp -d)"
  unzip -o -q "$f" -d "$d"
  ( cd "$d" && find . -type f | LC_ALL=C sort | while IFS= read -r m; do cat "$m"; done ) | sha256_stream
  rm -rf "$d"
}

START_TS="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_LOG="$(mktemp)"; trap 'rm -f "$BUILD_LOG"' EXIT

echo "=== roundtrip-bench: start $START_TS (project=$OUTPUT_NAME) ==="

# --- 事前点検: ビルドには参照テンプレが必要（公開 repo は JAMI 公式テンプレ非同梱）---
if [ "$SKIP_BUILD" != true ] && [ ! -f "templates/reference.docx" ] && [ ! -f "dist/abstract_template_en.docx" ]; then
  echo "ERROR: 参照テンプレートがありません（templates/reference.docx も dist/abstract_template_en.docx も無し）。" >&2
  echo "  公開リポジトリは JAMI 公式テンプレートを同梱していません。README の手順で準備してください:" >&2
  echo "    1) JAMI テンプレートを取得し dist/abstract_template_en.docx に保存（README のDL手順参照）" >&2
  echo "    2) make reference        # templates/reference.docx を生成（make build でも自動生成）" >&2
  echo "    3) bash scripts/roundtrip-bench.sh" >&2
  echo "  ※ 既にビルド済みの docx で PDF 化のみ計測するなら --skip-build を使ってください。" >&2
  exit 1
fi

# --- Phase 1: build (docx) ---
BUILD_SEC="null"
if [ "$SKIP_BUILD" = true ]; then
  echo "[bench] --skip-build: 既存 $DOCX を使用"
else
  echo "[bench] make build ..."
  t0="$(now)"
  if ! make build >"$BUILD_LOG" 2>&1; then cat "$BUILD_LOG" >&2; echo "ERROR: make build failed" >&2; exit 1; fi
  t1="$(now)"
  BUILD_SEC="$(secdiff "$t0" "$t1")"
  echo "[bench] build: ${BUILD_SEC}s"
fi
[ -f "$DOCX" ] || { echo "ERROR: docx not found: $DOCX" >&2; exit 1; }

# --- Phase 2: roundtrip (push -> Word COM -> pull PDF) ---
# docx は Phase 1 で生成済み（または既存）なので roundtrip 側のビルドは常に skip。
echo "[bench] roundtrip (push -> Word COM -> pull) ..."
r0="$(now)"
./scripts/roundtrip.sh --skip-build ${RT_ARGS[@]+"${RT_ARGS[@]}"}
r1="$(now)"
ROUNDTRIP_SEC="$(secdiff "$r0" "$r1")"
echo "[bench] roundtrip_pdf: ${ROUNDTRIP_SEC}s"
[ -f "$PDF" ] || { echo "ERROR: pdf not found: $PDF" >&2; exit 1; }

# --- 成果物メタ ---
DOCX_SHA="$(sha256_file "$DOCX")"
DOCX_MEMBERS_SHA="$(docx_members_sha256 "$DOCX")"
DOCX_SIZE="$(wc -c < "$DOCX" | tr -d ' ')"
PDF_SHA="$(sha256_file "$PDF")"
PDF_SIZE="$(wc -c < "$PDF" | tr -d ' ')"
PDF_PAGES="null"
if command -v pdfinfo >/dev/null 2>&1; then
  p="$(pdfinfo "$PDF" 2>/dev/null | awk -F: '/^Pages/{gsub(/ /,"",$2);print $2}')"
  [ -n "$p" ] && PDF_PAGES="$p"
fi
TOTAL_SEC="$(awk "BEGIN{b=(\"$BUILD_SEC\"==\"null\")?0:$BUILD_SEC; printf \"%.3f\", b+$ROUNDTRIP_SEC}")"

# --- JSON 出力（絶対パス・ホスト名・ユーザ名は記録しない）---
mkdir -p dist
OUT="dist/roundtrip-bench_${START_TS}.json"
cat > "$OUT" <<JSON
{
  "started_utc": "$START_TS",
  "project_name": "$OUTPUT_NAME",
  "os": "$(uname -s)",
  "arch": "$(uname -m)",
  "source_date_epoch": "${SOURCE_DATE_EPOCH:-}",
  "skip_build": $SKIP_BUILD,
  "timings_seconds": {
    "build": $BUILD_SEC,
    "roundtrip_pdf": $ROUNDTRIP_SEC,
    "total": $TOTAL_SEC
  },
  "docx": {
    "name": "${DOCX##*/}",
    "size_bytes": $DOCX_SIZE,
    "sha256": "$DOCX_SHA",
    "members_sha256": "$DOCX_MEMBERS_SHA"
  },
  "pdf": {
    "name": "${PDF##*/}",
    "size_bytes": $PDF_SIZE,
    "sha256": "$PDF_SHA",
    "pages": $PDF_PAGES
  }
}
JSON

echo "=== wrote $OUT ==="
cat "$OUT"
