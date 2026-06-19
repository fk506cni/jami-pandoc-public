#!/bin/bash

# message.md を使ってコミットし、プッシュする

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [ ! -f "message.md" ]; then
    echo "エラー: message.md が存在しません"
    exit 1
fi

git commit -F message.md

# plan §9-5 [GIT-C1/H1/M4]: bare `git push` 禁止。push 先リモート・ブランチを明示する
# （origin は private、paper は push=DISABLED）。--force / --all は使わない。
BRANCH="$(git branch --show-current)"
if [ -z "$BRANCH" ]; then
    echo "エラー: 現在のブランチを特定できません（detached HEAD?）。push を中止します。"
    exit 1
fi
git push origin "$BRANCH"
