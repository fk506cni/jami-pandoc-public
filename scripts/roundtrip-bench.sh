#!/usr/bin/env bash
# roundtrip-bench.sh — roundtrip(build -> PDF) の所要時間と成果物ハッシュを N 回実測し JSON 記録
# =============================================================================
# 各試行で **cold ビルド**（make clean -> make build）を行い docx ビルド時間を毎回実測、
# 続いて roundtrip（Windows の Word COM 経由で PDF 化）の所要時間を計測する。
# build/roundtrip_pdf/total の 平均・標本SD・min・max を集計し、全試行の明細とともに
# dist/roundtrip-bench_<UTC>.json に保存する。
#
# 前提: scripts/roundtrip.sh と同じ（rclone 設定済み・Windows 側 watch-and-convert.ps1 稼働・
#       JAMI テンプレートを dist/abstract_template_en.docx に配置済み＝make reference が走れる）。
#
# 使い方:
#   ./scripts/roundtrip-bench.sh [-n N] [--skip-build] [roundtrip.sh のオプション...]
#     -n, --runs N         試行回数（既定 32）
#     --gap SEC            試行間の休止秒（既定 20。Drive 同期の throttle/stall を抑える。0 で無効）
#     --skip-build         cold ビルドを行わず既存 docx で PDF 化のみ N 回計測（build は null）
#     --timeout MIN/--poll SEC 等は roundtrip.sh にそのまま渡す
#   出力: dist/roundtrip-bench_<UTC タイムスタンプ>.json（trials[] + aggregate）
#
# 注意:
#   - N×(cold build + roundtrip) を直列実行する。roundtrip は Drive 同期＋Word 起動に依存し
#     1 回あたり数十秒〜数分かかるため、N=32 では数十分を要する。
#   - 試行単位で耐障害: ある試行の build/roundtrip が失敗・タイムアウトしてもスキップして次へ進み、
#     成功した試行のみで集計する（失敗数も記録）。
#   - docx ファイルの SHA-256 は後処理(wrap-textbox.py)の ZIP タイムスタンプで毎回変わる（中身は決定的）。
#     members_sha256（展開メンバ内容のハッシュ）も併記し、SOURCE_DATE_EPOCH 固定なら毎回一致する。
#   - PDF は変換時刻を含むため SHA-256 は毎回変わる（参考値）。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

OUTPUT_NAME="$(grep '^PROJECT_NAME' config.mk 2>/dev/null | sed 's/.*:=[[:space:]]*//' | tr -d ' ')"
OUTPUT_NAME="${OUTPUT_NAME:-jami2026_abstract}"
DOCX="dist/${OUTPUT_NAME}.docx"
PDF="dist/${OUTPUT_NAME}.pdf"

# --- 引数解析 ---
RUNS=32
GAP=20            # 試行間の休止秒（Drive クライアントに同期キューを捌かせ throttle/stall を抑える）
SKIP_BUILD=false
RT_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--runs)   RUNS="$2"; shift 2 ;;
    --runs=*)    RUNS="${1#*=}"; shift ;;
    --gap)       GAP="$2"; shift 2 ;;
    --gap=*)     GAP="${1#*=}"; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help)   sed -n '2,33p' "$0"; exit 0 ;;
    *)           RT_ARGS+=("$1"); shift ;;
  esac
done
case "$RUNS" in ''|*[!0-9]*) echo "ERROR: --runs は正の整数: $RUNS" >&2; exit 2 ;; esac
[ "$RUNS" -ge 1 ] || { echo "ERROR: --runs は 1 以上: $RUNS" >&2; exit 2; }
case "$GAP" in ''|*[!0-9]*) echo "ERROR: --gap は 0 以上の整数(秒): $GAP" >&2; exit 2 ;; esac

# --- ヘルパー ---
now() { date +%s.%N; }
secdiff() { awk "BEGIN{printf \"%.3f\", $2-$1}"; }
sha256_file()   { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
sha256_stream() { if command -v sha256sum >/dev/null 2>&1; then sha256sum;     else shasum -a 256;     fi | awk '{print $1}'; }
docx_members_sha256() {
  local f="$1" d; d="$(mktemp -d)"
  unzip -o -q "$f" -d "$d"
  ( cd "$d" && find . -type f | LC_ALL=C sort | while IFS= read -r m; do cat "$m"; done ) | sha256_stream
  rm -rf "$d"
}
# 数値列(stdin, 1行1値) → "mean sd min max"（標本SD, n-1）
agg() {
  awk '
    NR==1{min=max=$1}
    {x[NR]=$1; s+=$1; if($1<min)min=$1; if($1>max)max=$1}
    END{ if(NR==0){print "0 0 0 0"; exit}
         m=s/NR; for(i=1;i<=NR;i++){d=x[i]-m; v+=d*d}
         sd=(NR>1)?sqrt(v/(NR-1)):0; printf "%.3f %.3f %.3f %.3f", m, sd, min, max }'
}

START_TS="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_LOG="$(mktemp)"; trap 'rm -f "$BUILD_LOG"' EXIT

# --- 事前点検: cold ビルドには参照テンプレが必要（公開 repo は JAMI 公式テンプレ非同梱）---
if [ "$SKIP_BUILD" != true ] && [ ! -f "templates/reference.docx" ] && [ ! -f "dist/abstract_template_en.docx" ]; then
  echo "ERROR: 参照テンプレートがありません（templates/reference.docx も dist/abstract_template_en.docx も無し）。" >&2
  echo "  公開リポジトリは JAMI 公式テンプレートを同梱していません。README の手順で準備してください:" >&2
  echo "    1) JAMI テンプレートを取得し dist/abstract_template_en.docx に保存（README のDL手順参照）" >&2
  echo "    2) make reference        # templates/reference.docx を生成（make build でも自動生成）" >&2
  echo "    3) bash scripts/roundtrip-bench.sh" >&2
  echo "  ※ 既にビルド済みの docx で PDF 化のみ計測するなら --skip-build を使ってください。" >&2
  exit 1
fi

# --- 多重起動ガード（flock）。子の roundtrip.sh は ROUNDTRIP_LOCK_HELD=1 を継承しロックを再取得しない ---
if command -v flock >/dev/null 2>&1; then
  mkdir -p dist
  exec 9>"dist/.roundtrip.lock"
  if ! flock -n 9; then
    echo "ERROR: 別の roundtrip/bench が実行中です（多重起動防止のため中止）。確認: pgrep -af roundtrip" >&2
    exit 1
  fi
  export ROUNDTRIP_LOCK_HELD=1
else
  echo "WARN: flock 不在のため多重起動ガード無効。二重起動しないこと。" >&2
fi

echo "=== roundtrip-bench: start $START_TS  runs=$RUNS  cold_build=$([ "$SKIP_BUILD" = true ] && echo false || echo true)  project=$OUTPUT_NAME ==="

declare -a B_ARR R_ARR T_ARR
TRIALS=""
OK=0; FAIL=0

for i in $(seq 1 "$RUNS"); do
  # 試行間ギャップ（2回目以降）: Drive クライアントに同期キューを捌かせ throttle/stall を抑える
  if [ "$i" -gt 1 ] && [ "$GAP" -gt 0 ]; then echo "[gap] ${GAP}s 休止"; sleep "$GAP"; fi
  build_sec="null"; ok=true

  # --- cold ビルド（毎回 make clean で強制再ビルド）---
  if [ "$SKIP_BUILD" != true ]; then
    make clean >/dev/null 2>&1 || true
    t0="$(now)"
    if make build >"$BUILD_LOG" 2>&1; then
      t1="$(now)"; build_sec="$(secdiff "$t0" "$t1")"
    else
      echo "[run $i/$RUNS] build 失敗 → スキップ"; tail -2 "$BUILD_LOG" | sed 's/^/    /' >&2; ok=false
    fi
  fi
  [ "$ok" = true ] && [ ! -f "$DOCX" ] && { echo "[run $i/$RUNS] docx 不在 → スキップ"; ok=false; }

  # --- roundtrip（push -> Word COM -> pull）---
  rt_sec="null"
  if [ "$ok" = true ]; then
    r0="$(now)"
    if ./scripts/roundtrip.sh --skip-build ${RT_ARGS[@]+"${RT_ARGS[@]}"} >/dev/null 2>&1; then
      r1="$(now)"; rt_sec="$(secdiff "$r0" "$r1")"
    else
      echo "[run $i/$RUNS] roundtrip 失敗/タイムアウト → スキップ"; ok=false
    fi
  fi
  [ "$ok" = true ] && [ ! -f "$PDF" ] && { echo "[run $i/$RUNS] pdf 不在 → スキップ"; ok=false; }

  if [ "$ok" != true ]; then FAIL=$((FAIL+1)); continue; fi

  # --- 成果物メタ ---
  docx_sha="$(sha256_file "$DOCX")"; docx_msha="$(docx_members_sha256 "$DOCX")"; docx_size="$(wc -c < "$DOCX" | tr -d ' ')"
  pdf_sha="$(sha256_file "$PDF")"; pdf_size="$(wc -c < "$PDF" | tr -d ' ')"
  pdf_pages="null"
  if command -v pdfinfo >/dev/null 2>&1; then
    p="$(pdfinfo "$PDF" 2>/dev/null | awk -F: '/^Pages/{gsub(/ /,"",$2);print $2}')"; [ -n "$p" ] && pdf_pages="$p"
  fi
  total_sec="$(awk "BEGIN{b=(\"$build_sec\"==\"null\")?0:$build_sec; printf \"%.3f\", b+$rt_sec}")"

  [ "$build_sec" != "null" ] && B_ARR+=("$build_sec")
  R_ARR+=("$rt_sec"); T_ARR+=("$total_sec"); OK=$((OK+1))

  obj="    {\"run\": $i, \"build\": $build_sec, \"roundtrip_pdf\": $rt_sec, \"total\": $total_sec, \"docx\": {\"size_bytes\": $docx_size, \"sha256\": \"$docx_sha\", \"members_sha256\": \"$docx_msha\"}, \"pdf\": {\"size_bytes\": $pdf_size, \"sha256\": \"$pdf_sha\", \"pages\": $pdf_pages}}"
  if [ -n "$TRIALS" ]; then TRIALS="$TRIALS,
$obj"; else TRIALS="$obj"; fi

  printf "[run %d/%d] build=%ss roundtrip_pdf=%ss total=%ss\n" "$i" "$RUNS" "$build_sec" "$rt_sec" "$total_sec"
done

# --- 集計 ---
json_agg() { # stdin: 値列 → JSON object か、空なら null
  local m sd mn mx
  if [ "$#" -eq 0 ]; then printf 'null'; return; fi
  read -r m sd mn mx <<<"$(printf '%s\n' "$@" | agg)"
  printf '{"n": %d, "mean": %s, "sd": %s, "min": %s, "max": %s}' "$#" "$m" "$sd" "$mn" "$mx"
}
BUILD_AGG="$([ "${#B_ARR[@]}" -gt 0 ] && json_agg "${B_ARR[@]}" || printf 'null')"
RT_AGG="$([ "${#R_ARR[@]}" -gt 0 ] && json_agg "${R_ARR[@]}" || printf 'null')"
TOTAL_AGG="$([ "${#T_ARR[@]}" -gt 0 ] && json_agg "${T_ARR[@]}" || printf 'null')"

mkdir -p dist
OUT="dist/roundtrip-bench_${START_TS}.json"
cat > "$OUT" <<JSON
{
  "started_utc": "$START_TS",
  "project_name": "$OUTPUT_NAME",
  "os": "$(uname -s)",
  "arch": "$(uname -m)",
  "source_date_epoch": "${SOURCE_DATE_EPOCH:-}",
  "runs_requested": $RUNS,
  "gap_seconds": $GAP,
  "runs_ok": $OK,
  "runs_failed": $FAIL,
  "cold_build": $([ "$SKIP_BUILD" = true ] && echo false || echo true),
  "aggregate_seconds": {
    "build": $BUILD_AGG,
    "roundtrip_pdf": $RT_AGG,
    "total": $TOTAL_AGG
  },
  "trials": [
$TRIALS
  ]
}
JSON

echo "=== done: ok=$OK failed=$FAIL → $OUT ==="
if [ "$FAIL" -gt 0 ]; then
  echo "⚠ $FAIL/$RUNS 試行が失敗(timeout 等)。集計はその分を除外しており平均が下振れ（バイアス）の可能性。" >&2
  echo "  脱落なく測るには --timeout を上げて再計測してください（例: --timeout 15）。" >&2
fi
echo "aggregate_seconds:"; printf '  build        : %s\n  roundtrip_pdf: %s\n  total        : %s\n' "$BUILD_AGG" "$RT_AGG" "$TOTAL_AGG"
