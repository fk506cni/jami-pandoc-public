#!/bin/bash

# diff.sh - Generate diff-highlighted Word file
#
# Default mode: Color highlight (blue=add, red+strikethrough=delete)
# --tracked-changes: Legacy mode using pandiff tracked changes
#
# Usage:
#   ./scripts/diff.sh                              # Color diff vs HEAD~1
#   ./scripts/diff.sh REVISION                     # Color diff vs git revision
#   ./scripts/diff.sh old.md new.md                # Color diff between two files
#   ./scripts/diff.sh --tracked-changes            # Tracked changes vs HEAD~1
#   ./scripts/diff.sh --tracked-changes REVISION   # Tracked changes vs revision
#   ./scripts/diff.sh --tracked-changes old.md new.md
#
# Examples:
#   ./scripts/diff.sh                       # 前回コミットとの差分（カラー）
#   ./scripts/diff.sh HEAD~3               # 3つ前のコミットとの差分
#   ./scripts/diff.sh submitted.md src/paper.md  # 査読前 vs 修正後

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Read PROJECT_NAME from config.mk (fallback to default)
PROJECT_NAME=$(grep '^PROJECT_NAME' config.mk 2>/dev/null | sed 's/.*:=\s*//' | tr -d ' ')
PROJECT_NAME="${PROJECT_NAME:-jami2026_abstract}"

# Ensure Docker image exists
if ! docker compose images pandoc --quiet 2>/dev/null | grep -q .; then
    echo "Docker image not found. Building..."
    docker compose build
fi

# Ensure reference.docx exists
if [ ! -f "templates/reference.docx" ]; then
    echo "templates/reference.docx not found. Copying from dist/abstract_template_en.docx..."
    make reference
fi

RUN="docker compose run --rm -u $(id -u):$(id -g) pandoc"
REF_DOC="templates/reference.docx"
BIB="src/refs.bib"
CSL="templates/jami.csl"
LUA_STYLE="filters/jami-style.lua"
LUA_DIFF="filters/color-diff.lua"
DIFF_OUT="dist/${PROJECT_NAME}_diff.docx"

# Parse --tracked-changes flag
TRACKED=false
if [[ "$1" == "--tracked-changes" ]]; then
    TRACKED=true
    shift
fi

# -----------------------------------------------
# Tracked changes mode (legacy)
# -----------------------------------------------
run_tracked_changes() {
    if [[ $# -eq 2 && -f "$1" && -f "$2" ]]; then
        OLD_FILE="$1"; NEW_FILE="$2"
        echo "[tracked-changes] Comparing: $OLD_FILE → $NEW_FILE"
        $RUN pandiff --reference-doc="$REF_DOC" --output="$DIFF_OUT" "$OLD_FILE" "$NEW_FILE"
    else
        REVISION="${1:-HEAD~1}"
        if ! git rev-parse --verify "$REVISION" >/dev/null 2>&1; then
            echo "Error: revision '$REVISION' not found" >&2
            exit 1
        fi
        echo "[tracked-changes] Comparing: src/paper.md vs $REVISION"
        $RUN pandiff --reference-doc="$REF_DOC" --output="$DIFF_OUT" "$REVISION" -- src/paper.md
    fi
    echo "Diff complete: $DIFF_OUT"
}

# -----------------------------------------------
# Color highlight mode (default)
# -----------------------------------------------
run_color_highlight() {
    local OLD_MD NEW_MD

    if [[ $# -eq 2 && -f "$1" && -f "$2" ]]; then
        OLD_MD="$1"; NEW_MD="$2"
        echo "[color-highlight] Comparing: $OLD_MD → $NEW_MD"
    else
        REVISION="${1:-HEAD~1}"
        if ! git rev-parse --verify "$REVISION" >/dev/null 2>&1; then
            echo "Error: revision '$REVISION' not found" >&2
            exit 1
        fi
        echo "[color-highlight] Comparing: src/paper.md vs $REVISION"
        # Extract old version from git
        OLD_MD=$(mktemp /tmp/diff_old_XXXXXX.md)
        git show "${REVISION}:src/paper.md" > "$OLD_MD"
        NEW_MD="src/paper.md"
        trap "rm -f '$OLD_MD'" EXIT
    fi

    # Step 1: pandiff → CriticMarkup markdown
    CRITIC_MD=$($RUN pandiff -t markdown "$OLD_MD" "$NEW_MD" 2>/dev/null || true)

    if [ -z "$CRITIC_MD" ]; then
        echo "No differences found."
        # Copy the normal build output as the diff output
        if [ -f "dist/${PROJECT_NAME}.docx" ]; then
            cp "dist/${PROJECT_NAME}.docx" "$DIFF_OUT"
        fi
        echo "Diff complete: $DIFF_OUT"
        return 0
    fi

    # Step 2: Unescape pandiff's backslash escapes on CriticMarkup chars
    #   pandiff escapes ~, >, @, [, ] which breaks CriticMarkup parsing
    CRITIC_MD=$(printf '%s' "$CRITIC_MD" | perl -pe 's/\\~/~/g; s/\\>/>/g; s/\\\@/@/g; s/\\\[/[/g; s/\\\]/]/g')

    # Step 3: Fix broken CriticMarkup from pandiff
    #   pandiff sometimes generates split substitutions where closing/opening
    #   ~~ delimiters are missing: {~~A~>B}shared{C~>D~~}
    #   Fix: {~~A~>B~~}shared{~~C~>D~~}
    for _i in 1 2 3; do
        CRITIC_MD=$(printf '%s' "$CRITIC_MD" | perl -pe 's/~>([^~}]*)\}(.*?)\{([^~{]*~>)/~>${1}~~\}${2}\{~~${3}/g')
    done

    # Step 4: Restore structural elements from the new file
    #   pandiff strips custom-style Divs, raw OOXML blocks, and .textbox Divs
    #   Strategy: keep the header section from the NEW file (with custom-style Divs
    #   and section break), and use pandiff's body (from ## 1. onward) for diff marks.

    # Extract header section from NEW file (YAML through section break, before ## 1.)
    NEW_HEADER=$(awk '/^## 1\./ { exit } { print }' "$NEW_MD")

    # Extract body from pandiff output (from ## 1. onward, with diff annotations)
    DIFF_BODY=$(printf '%s' "$CRITIC_MD" | awk '/^## 1\./ { found=1 } found { print }')

    if [ -n "$NEW_HEADER" ] && [ -n "$DIFF_BODY" ]; then
        CRITIC_MD="${NEW_HEADER}"$'\n\n'"${DIFF_BODY}"
    fi

    # Step 5: Restore .textbox Div blocks from the NEW file
    #   pandiff converts tables to HTML <table> and strips figure textbox wrappers.
    #   Replace those with the original .textbox Divs from the NEW file.
    CRITIC_MD=$(printf '%s' "$CRITIC_MD" | python3 scripts/restore-textboxes.py "$NEW_MD")

    # Step 6: Convert CriticMarkup to bracketed spans via perl
    #   {++text++}       → [text]{.diff-add}
    #   {--text--}       → [text]{.diff-del}
    #   {~~old~>new~~}   → [old]{.diff-del}[new]{.diff-add}
    SPAN_MD=$(echo "$CRITIC_MD" | perl -0777 -pe '
        s/\{\~\~(.*?)\~>(.*?)\~\~\}/[$1]{.diff-del}[$2]{.diff-add}/gs;
        s/\{\+\+(.*?)\+\+\}/[$1]{.diff-add}/gs;
        s/\{\-\-(.*?)\-\-\}/[$1]{.diff-del}/gs;
    ')

    # Step 7: Build pandoc args for color diff
    PANDOC_DIFF_ARGS=(
        --from "markdown+east_asian_line_breaks+bracketed_spans+native_divs"
        --to docx
        --reference-doc="$REF_DOC"
        --filter pandoc-crossref
        --lua-filter="$LUA_STYLE"
        --lua-filter="$LUA_DIFF"
        --citeproc
        --bibliography="$BIB"
    )

    # Add CSL if exists
    if [ -f "$CSL" ]; then
        PANDOC_DIFF_ARGS+=(--csl="$CSL")
    fi

    PANDOC_DIFF_ARGS+=(--output="$DIFF_OUT")

    # Step 8: Pipe through pandoc
    mkdir -p dist
    echo "$SPAN_MD" | $RUN pandoc "${PANDOC_DIFF_ARGS[@]}"

    # Step 9: Post-process textbox markers
    $RUN python3 scripts/wrap-textbox.py --source "$NEW_MD" --no-relocate "$DIFF_OUT"

    echo "Diff complete: $DIFF_OUT"
}

# -----------------------------------------------
# Main
# -----------------------------------------------
if $TRACKED; then
    run_tracked_changes "$@"
else
    run_color_highlight "$@"
fi
