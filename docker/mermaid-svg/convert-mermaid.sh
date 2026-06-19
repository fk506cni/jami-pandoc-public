#!/bin/bash

# Mermaid to PDF conversion script using Docker
# Usage: ./docker/mermaid-svg/convert-mermaid.sh <mermaid_file>
#
# Converts Mermaid diagram to PDF directly via puppeteer:
# .mmd -> mmdc -> .pdf

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
Usage: $(basename "$0") <mermaid_file>

Convert Mermaid diagram to PDF.
Conversion flow: .mmd -> (mmdc/puppeteer) -> .pdf
Output PDF is generated in the same directory as the input file.

Arguments:
  mermaid_file    Path to the Mermaid file (.mmd) to convert

Exit codes:
  0    Success
  1    Argument error
  2    File not found
  3    Conversion tool error

Examples:
  $(basename "$0") src/figs/flowchart.mmd
  $(basename "$0") figures/sequence.mmd
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

MMD_FILE="$1"

# Remove leading ./ if present
MMD_FILE="${MMD_FILE#./}"

# Validate file extension
if [[ "${MMD_FILE,,}" != *.mmd ]]; then
    error "Input file must have .mmd extension: $MMD_FILE"
    exit $EXIT_ARGS_ERROR
fi

# Check if Mermaid file exists (try both absolute and relative to project root)
if [[ -f "$MMD_FILE" ]]; then
    # Absolute or current directory relative path
    ABS_MMD_FILE="$(cd "$(dirname "$MMD_FILE")" && pwd)/$(basename "$MMD_FILE")"
elif [[ -f "$PROJECT_ROOT/$MMD_FILE" ]]; then
    # Relative to project root
    ABS_MMD_FILE="$PROJECT_ROOT/$MMD_FILE"
else
    error "File not found: $MMD_FILE"
    exit $EXIT_FILE_NOT_FOUND
fi

# Extract file information
MMD_DIR=$(dirname "$ABS_MMD_FILE")
MMD_FILENAME=$(basename "$ABS_MMD_FILE")
BASE_NAME=$(basename "$MMD_FILENAME" .mmd)
BASE_NAME=$(basename "$BASE_NAME" .MMD)  # Handle uppercase extension
PDF_FILE="${MMD_DIR}/${BASE_NAME}.pdf"

# Compute relative path from project root for display
REL_MMD_FILE="${ABS_MMD_FILE#$PROJECT_ROOT/}"
REL_PDF_FILE="${PDF_FILE#$PROJECT_ROOT/}"

echo "========================================"
echo "Mermaid to PDF Conversion"
echo "========================================"
echo "Input file:  $REL_MMD_FILE"
echo "Output file: $REL_PDF_FILE"
echo "Workflow:    .mmd -> .pdf (direct)"
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
    -v "$MMD_DIR:/workspace" \
    -e "PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true" \
    -e "PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium" \
    "$IMAGE_NAME" \
    bash -c "
        set -e
        cd /workspace

        echo 'Converting Mermaid to PDF...'

        # Convert Mermaid directly to PDF using mmdc (mermaid-cli)
        # -p provides puppeteer config for sandbox-free execution in Docker
        # -f (pdfFit) scales the PDF to fit the chart
        mmdc -i '$MMD_FILENAME' -o '$BASE_NAME.pdf' -p /etc/puppeteer-config.json -f

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
        error "Mermaid conversion failed (exit code: $DOCKER_EXIT_CODE)"
    fi
    exit $EXIT_TOOL_ERROR
fi

echo ""
info "========================================"
info "Conversion completed successfully!"
info "Output: $REL_PDF_FILE"
info "========================================"

exit $EXIT_SUCCESS
