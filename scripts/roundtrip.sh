#!/usr/bin/env bash
# roundtrip.sh — build → Google Drive push → Windows で PDF 変換待ち → pull
#
# 目的: LibreOffice ではテキストボックスを正しく描画できないため、PDF 化は
#   Windows 上の Microsoft Word (Word COM) でしか忠実に行えない。本スクリプトは
#   Google Drive を中継して、その Word 変換を Linux から一括実行する。
#
#   [Linux] make build で docx 生成
#     → [Linux] docx を gdrive: の roundtrip フォルダへ push (rclone)
#       → [Windows] 同期フォルダで watch-and-convert.ps1 が docx を検知し
#                   Word COM で同名 PDF に変換 (docx は processed/ へ移動)
#         → [Linux] gdrive: に現れた PDF を検知して pull (dist/ へ)
#
# 事前準備 (Windows 側・1 回):
#   1. Google Drive デスクトップを入れ、マイドライブ配下に
#        <マイドライブ>/tmp/<repo名>/roundtrip/   を同期させる
#   2. scripts/watch-and-convert.ps1 をその roundtrip/ フォルダに置いて起動
#      （PowerShell で .\watch-and-convert.ps1。Word インストール要）
#
# ⚠ これは BUILD + GDRIVE 中継ツール (private)。**公開同期 sync-public.sh とは別物**。
#   gdrive:/rclone を使うため公開リポジトリには含めない (backup.sh と同様)。
#
# Usage:
#   ./scripts/roundtrip.sh [OPTIONS]
# Options:
#   --skip-build    ビルドをスキップ（既存 dist の docx を push 以降のみ）
#   --timeout MIN   PDF 待ちタイムアウト（既定 5 分）
#   --poll SEC      ポーリング間隔（既定 10 秒）
#   --dry-run       rclone を一切呼ばず予定のみ表示（live アップロードなし）
#   -h, --help      ヘルプ表示

set -euo pipefail

# --- プロジェクトルート ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# --- 設定（env で上書き可）---
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:}"
GDRIVE_BASE_PATH="${GDRIVE_BASE_PATH:-tmp}"
PROJECT_DIRNAME="$(basename "$PROJECT_ROOT")"            # 例: jami-abstract-pandoc
GDRIVE_SUBDIR="${GDRIVE_SUBDIR:-roundtrip}"              # Windows watcher を置くフォルダ
GDRIVE_DEST="${RCLONE_REMOTE}${GDRIVE_BASE_PATH}/${PROJECT_DIRNAME}/${GDRIVE_SUBDIR}"

# 出力ファイル名 stem（config.mk から。backup.sh と同じ流儀）
OUTPUT_NAME="$(grep '^PROJECT_NAME' "$PROJECT_ROOT/config.mk" 2>/dev/null | sed 's/.*:=\s*//' | tr -d ' ')"
OUTPUT_NAME="${OUTPUT_NAME:-jami2026_abstract}"

DOCX_REL="dist/${OUTPUT_NAME}.docx"
PDF_NAME="${OUTPUT_NAME}.pdf"
PRODUCTS_DIR="dist"          # PDF の pull 先

# --- フラグ ---
SKIP_BUILD=false
TIMEOUT_MIN=5
POLL_SEC=10
DRY_RUN=false

# --- ヘルパー ---
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $1"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $1"; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $1" >&2; }
log_ok()    { echo "[OK]    $(date '+%H:%M:%S') $1"; }
separator() { echo "========================================"; }

# rclone を retry 付きで実行（Google Drive の一時的応答遅延に耐える）
RCLONE_MAX_RETRIES="${RCLONE_MAX_RETRIES:-3}"
RCLONE_RETRY_SLEEP="${RCLONE_RETRY_SLEEP:-5}"
rclone_with_retry() {
    local to="$1"; shift
    local attempt=1
    while :; do
        if timeout "$to" "$@"; then
            return 0
        fi
        local rc=$?
        if [[ $attempt -ge $RCLONE_MAX_RETRIES ]]; then
            return $rc
        fi
        log_warn "rclone 実行失敗 (exit $rc, try $attempt/$RCLONE_MAX_RETRIES)。${RCLONE_RETRY_SLEEP}秒後に再試行"
        sleep "$RCLONE_RETRY_SLEEP"
        attempt=$((attempt + 1))
    done
}

# --- 引数解析 ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build) SKIP_BUILD=true; shift ;;
        --timeout)    TIMEOUT_MIN="$2"; shift 2 ;;
        --poll)       POLL_SEC="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        -h|--help)    sed -n '2,33p' "$0"; exit 0 ;;
        *)            log_error "不明なオプション: $1"; exit 1 ;;
    esac
done

# ============================================================
# Phase 1: ビルド
# ============================================================
phase_build() {
    separator; log_info "Phase 1: ビルド (make build)"; separator; echo ""
    if [[ "$SKIP_BUILD" == true ]]; then
        log_info "--skip-build: 既存 ${DOCX_REL} を使用"
    else
        make build
    fi
    if [[ ! -f "$DOCX_REL" ]]; then
        log_error "docx がありません: ${DOCX_REL}（先に make build を）"; exit 1
    fi
    log_ok "docx: ${DOCX_REL} ($(du -h "$DOCX_REL" | cut -f1))"
    echo ""
}

# ============================================================
# Phase 2: 旧 PDF を __archives/ へ退避（古い PDF の誤検知防止）
# ============================================================
archive_old_pdf() {
    local ts; ts="$(date '+%Y%m%d_%H%M%S')"
    local archive="${GDRIVE_DEST}/__archives"
    local pdf_list
    pdf_list="$(rclone_with_retry 60 rclone lsf "${GDRIVE_DEST}" \
        --include "*.pdf" --max-depth 1 --files-only 2>/dev/null || true)"
    [[ -z "$pdf_list" ]] && return 0
    log_info "旧 PDF を __archives/ へ退避..."
    rclone mkdir "$archive" 2>/dev/null || true
    local name base
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        base="${name%.pdf}"
        timeout 30 rclone moveto "${GDRIVE_DEST}/${name}" \
            "${archive}/${base}_${ts}.pdf" 2>&1 | tail -1 || true
        log_info "  旧 ${name} → __archives/${base}_${ts}.pdf"
    done <<< "$pdf_list"
    echo ""
}

# ============================================================
# Phase 3: docx を Google Drive へ push
# ============================================================
phase_push() {
    separator; log_info "Phase 3: push → ${GDRIVE_DEST}"; separator; echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "(dry-run) push 予定: ${DOCX_REL} → ${GDRIVE_DEST}/${OUTPUT_NAME}.docx"
        echo ""; return 0
    fi
    if ! command -v rclone &>/dev/null; then
        log_error "rclone がインストールされていません"; exit 1
    fi
    if ! rclone_with_retry 60 rclone lsf "${GDRIVE_DEST}/" --max-depth 1 &>/dev/null; then
        # フォルダ未作成の可能性 → 作成を試す
        rclone mkdir "${GDRIVE_DEST}" 2>/dev/null || {
            log_error "rclone リモート '${GDRIVE_DEST}' に接続できません"
            log_error "  rclone config reconnect ${RCLONE_REMOTE} を試してください"; exit 1
        }
    fi
    archive_old_pdf
    rclone copyto "$DOCX_REL" "${GDRIVE_DEST}/${OUTPUT_NAME}.docx" --stats-one-line -v
    log_ok "push 完了: ${OUTPUT_NAME}.docx"
    echo ""
}

# ============================================================
# Phase 4: PDF 変換待ち → pull
# ============================================================
phase_wait_and_pull() {
    separator
    log_info "Phase 4: PDF 待ち（最大 ${TIMEOUT_MIN}分・${POLL_SEC}秒間隔）→ ${PRODUCTS_DIR}/"
    separator; echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "(dry-run) ${GDRIVE_DEST}/${PDF_NAME} を待って ${PRODUCTS_DIR}/${PDF_NAME} へ pull する予定"
        echo ""; return 0
    fi

    local deadline=$((SECONDS + TIMEOUT_MIN * 60))
    local found=false
    log_info "Windows 側 watch-and-convert.ps1 による ${PDF_NAME} を待機中..."
    while [[ $SECONDS -lt $deadline ]]; do
        if rclone_with_retry 60 rclone lsf "${GDRIVE_DEST}" \
                --include "${PDF_NAME}" --max-depth 1 --files-only 2>/dev/null \
                | grep -q .; then
            found=true; break
        fi
        local remaining=$(( (deadline - SECONDS) / 60 ))
        printf "\r  待機中... (残り約 %d分)  " "$remaining"
        sleep "$POLL_SEC"
    done
    echo ""

    if [[ "$found" != true ]]; then
        log_error "タイムアウト: ${PDF_NAME} が現れませんでした"
        log_error "  Windows 側 watch-and-convert.ps1 が roundtrip/ フォルダで起動しているか確認してください"
        exit 1
    fi
    log_ok "PDF 検出: ${PDF_NAME}"

    log_info "pull → ${PRODUCTS_DIR}/${PDF_NAME}"
    mkdir -p "$PRODUCTS_DIR"
    rclone copyto "${GDRIVE_DEST}/${PDF_NAME}" "${PRODUCTS_DIR}/${PDF_NAME}" --stats-one-line -v
    log_ok "pull 完了: ${PRODUCTS_DIR}/${PDF_NAME} ($(du -h "${PRODUCTS_DIR}/${PDF_NAME}" | cut -f1))"
    echo ""
    log_info "Google Drive 側の ${PDF_NAME} は保持（Windows での閲覧用）。次回 push 冒頭で __archives/ へ自動退避。"
    echo ""
}

# ============================================================
# メイン
# ============================================================
echo ""
separator
log_info "roundtrip: build → push → PDF 待ち → pull"
[[ "$DRY_RUN" == true ]] && log_info "(dry-run モード: rclone 呼び出しなし)"
log_info "dest = ${GDRIVE_DEST}  /  PDF = ${PDF_NAME}"
separator; echo ""

phase_build
phase_push
phase_wait_and_pull

separator; log_ok "roundtrip 完了"; separator
echo ""
echo "docx: ${DOCX_REL}"
echo "PDF : ${PRODUCTS_DIR}/${PDF_NAME}"
echo ""
