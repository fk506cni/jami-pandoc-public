#!/bin/bash

# build.sh - Build JAMI2026 abstract (Markdown → Word)
#
# Usage: ./scripts/build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

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

# Build
make build
