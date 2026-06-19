#!/bin/bash

# SVG to PDF conversion script using Docker
# Usage: ./docker/mermaid-svg/convert-svg.sh <svg_file>

set -e

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_NAME="latex-template-mermaid"
DOCKERFILE_DIR="$SCRIPT_DIR"

# Exit codes
EXIT_SUCCESS=0
EXIT_ARGS_ERROR=1
EXIT_FILE_NOT_FOUND=2
EXIT_TOOL_ERROR=3

# Color output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

info() {
    echo -e "${GREEN}$1${NC}"
}

usage() {
    cat << EOF
Usage: $(basename "$0") <svg_file>

Convert SVG file to PDF using Inkscape.
Output PDF is generated in the same directory as the input file.

Arguments:
  svg_file    Path to the SVG file to convert

Exit codes:
  0    Success
  1    Argument error
  2    File not found
  3    Conversion tool error

Examples:
  $(basename "$0") src/figs/diagram.svg
  $(basename "$0") figures/flowchart.svg
EOF
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    error "No input file specified"
    usage
    exit $EXIT_ARGS_ERROR
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit $EXIT_SUCCESS
fi

SVG_FILE="$1"

# Remove leading ./ if present
SVG_FILE="${SVG_FILE#./}"

# Validate file extension
if [[ "${SVG_FILE,,}" != *.svg ]]; then
    error "Input file must have .svg extension: $SVG_FILE"
    exit $EXIT_ARGS_ERROR
fi

# Check if SVG file exists (try both absolute and relative to project root)
if [[ -f "$SVG_FILE" ]]; then
    # Absolute or current directory relative path
    ABS_SVG_FILE="$(cd "$(dirname "$SVG_FILE")" && pwd)/$(basename "$SVG_FILE")"
elif [[ -f "$PROJECT_ROOT/$SVG_FILE" ]]; then
    # Relative to project root
    ABS_SVG_FILE="$PROJECT_ROOT/$SVG_FILE"
else
    error "File not found: $SVG_FILE"
    exit $EXIT_FILE_NOT_FOUND
fi

# Extract file information
SVG_DIR=$(dirname "$ABS_SVG_FILE")
SVG_FILENAME=$(basename "$ABS_SVG_FILE")
BASE_NAME=$(basename "$SVG_FILENAME" .svg)
BASE_NAME=$(basename "$BASE_NAME" .SVG)  # Handle uppercase extension
PDF_FILE="${SVG_DIR}/${BASE_NAME}.pdf"

# Compute relative path from project root for display
REL_SVG_FILE="${ABS_SVG_FILE#$PROJECT_ROOT/}"
REL_PDF_FILE="${PDF_FILE#$PROJECT_ROOT/}"

echo "========================================"
echo "SVG to PDF Conversion"
echo "========================================"
echo "Input file:  $REL_SVG_FILE"
echo "Output file: $REL_PDF_FILE"
echo "========================================"

# Build Docker image if it doesn't exist
if [[ "$(docker images -q "$IMAGE_NAME" 2>/dev/null)" == "" ]]; then
    echo "Building Docker image: $IMAGE_NAME..."
    if ! docker build -t "$IMAGE_NAME" "$DOCKERFILE_DIR"; then
        error "Failed to build Docker image"
        exit $EXIT_TOOL_ERROR
    fi
fi

# Check if Docker is available
if ! command -v docker &>/dev/null; then
    error "Docker is not installed or not in PATH"
    exit $EXIT_TOOL_ERROR
fi

# Run conversion in Docker container
echo "Starting conversion..."

DOCKER_EXIT_CODE=0
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$SVG_DIR:/workspace" \
    "$IMAGE_NAME" \
    bash -c "
        set -e
        cd /workspace

        # Convert SVG to PDF using Inkscape
        # --export-type=pdf: Output format
        # --export-filename: Output file path
        # Font embedding is automatic with Inkscape
        inkscape '$SVG_FILENAME' \
            --export-type=pdf \
            --export-filename='$BASE_NAME.pdf'

        # Verify output
        if [[ ! -f '$BASE_NAME.pdf' ]]; then
            echo 'Error: PDF file was not generated' >&2
            exit 1
        fi

        echo ''
        echo 'Conversion successful!'
    " || DOCKER_EXIT_CODE=$?

# Handle exit codes
if [[ $DOCKER_EXIT_CODE -ne 0 ]]; then
    if [[ $DOCKER_EXIT_CODE -eq 125 || $DOCKER_EXIT_CODE -eq 126 || $DOCKER_EXIT_CODE -eq 127 ]]; then
        error "Docker execution failed (exit code: $DOCKER_EXIT_CODE)"
    else
        error "Inkscape conversion failed (exit code: $DOCKER_EXIT_CODE)"
    fi
    exit $EXIT_TOOL_ERROR
fi

echo ""
info "========================================"
info "Conversion completed successfully!"
info "Output: $REL_PDF_FILE"
info "========================================"

exit $EXIT_SUCCESS
