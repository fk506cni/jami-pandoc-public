#!/bin/bash

# message.mdをタイムスタンプ付きでjankフォルダに移動するスクリプト

# プロジェクトルートを取得（スクリプトの親ディレクトリ）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SOURCE_FILE="$PROJECT_ROOT/message.md"
DEST_DIR="$PROJECT_ROOT/jank"

# 対象ファイルの存在確認
if [ ! -f "$SOURCE_FILE" ]; then
    echo "対象ファイルがありません: message.md"
    exit 0
fi

# jankフォルダがなければ作成
mkdir -p "$DEST_DIR"

# タイムスタンプを生成（YYYYMMDD_HHMMSS形式）
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 新しいファイル名を作成（拡張子の前にタイムスタンプ）
DEST_FILE="$DEST_DIR/message_${TIMESTAMP}.md"

# ファイルを移動
mv "$SOURCE_FILE" "$DEST_FILE"

echo "移動しました: message.md -> jank/message_${TIMESTAMP}.md"
