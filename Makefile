# Pandoc Docker Build — conference abstract (.docx)
# ================================================
# 公開版 Makefile（→ 公開 Makefile）。private 専用のアップロード系ターゲットは
# 公開版には含めていない。

-include config.mk
PROJECT_NAME ?= jami2026_abstract

COMPOSE  := docker compose
SERVICE  := pandoc
RUN      := $(COMPOSE) run --rm -u $$(id -u):$$(id -g) $(SERVICE)

# Directories
SRC_DIR       := src
DIST_DIR      := dist
TEMPLATES_DIR := templates

# Files
SRC       := $(SRC_DIR)/paper.md
BIB       := $(SRC_DIR)/refs.bib
REF_DOC   := $(TEMPLATES_DIR)/reference.docx
CSL       := $(TEMPLATES_DIR)/jami.csl
LUA_STYLE     := filters/jami-style.lua
WRAP_TEXTBOX  := scripts/wrap-textbox.py
FIX_SVG_CLIPS := scripts/fix-svg-clips.py
FIX_SVG_FO    := scripts/fix-svg-foreignobject.py
OUTPUT        := $(DIST_DIR)/$(PROJECT_NAME).docx
OUTPUT_PDF    := $(DIST_DIR)/$(PROJECT_NAME).pdf
DIFF_OUT      := $(DIST_DIR)/$(PROJECT_NAME)_diff.docx
DOCX_TMPL     := $(DIST_DIR)/abstract_template_en.docx

# SVG to PNG pre-conversion (300 DPI fallback for older Word)
SVG_SRCS      := $(wildcard $(SRC_DIR)/figs/*.svg)
SVG_PNGS      := $(SVG_SRCS:=.png)

# Pandoc options (filter order: crossref → jami-style → citeproc)
PANDOC_ARGS := \
	--from markdown+east_asian_line_breaks \
	--to docx \
	--reference-doc=$(REF_DOC) \
	--filter pandoc-crossref \
	--lua-filter=$(LUA_STYLE) \
	--citeproc \
	--bibliography=$(BIB)

# Conditionally add CSL if file exists
ifneq ($(wildcard $(CSL)),)
PANDOC_ARGS += --csl=$(CSL)
endif

# ===========================================
# Targets
# ===========================================

.PHONY: all build pdf diff diff-tracked reference clean docker-build fix-svg fig-pptx help

all: build  ## Default target: build the abstract docx

build: $(OUTPUT)  ## Build the abstract docx

# Fix SVG clip-path text clipping + convert SVG → PNG at 300 DPI
$(SRC_DIR)/figs/%.svg.png: $(SRC_DIR)/figs/%.svg $(FIX_SVG_CLIPS)
	@python3 $(FIX_SVG_CLIPS) $<
	$(RUN) rsvg-convert -d 300 -p 300 -o $@ $<

fix-svg: $(SVG_SRCS)  ## Fix Mermaid foreignObject + text clipping in SVG files (idempotent)
	python3 $(FIX_SVG_FO) $^
	python3 $(FIX_SVG_CLIPS) $^

$(OUTPUT): $(SRC) $(REF_DOC) $(LUA_STYLE) $(WRAP_TEXTBOX) $(SVG_PNGS)
	@mkdir -p $(DIST_DIR)
	$(RUN) pandoc $(SRC) $(PANDOC_ARGS) --output=$(OUTPUT)
	$(RUN) python3 $(WRAP_TEXTBOX) --source $(SRC) --no-relocate $(OUTPUT)
	@echo "Build complete: $(OUTPUT)"
	@echo "PDF conversion: drag $(OUTPUT) onto scripts/word-to-pdf.bat (Windows)"

pdf:  ## Show PDF conversion instructions
	@echo "PDF conversion requires Word on Windows."
	@echo "Drag dist/$(PROJECT_NAME).docx onto scripts/word-to-pdf.bat"

diff: $(SVG_PNGS)  ## Generate color-highlighted diff docx (via scripts/diff.sh)
	./scripts/diff.sh
	@echo "Diff complete: $(DIFF_OUT)"

diff-tracked:  ## Generate diff docx with tracked changes (legacy mode)
	./scripts/diff.sh --tracked-changes
	@echo "Diff (tracked changes) complete: $(DIFF_OUT)"

reference:  ## Force-(re)generate reference.docx from template
	cp $(DOCX_TMPL) $(REF_DOC)
	$(RUN) python3 scripts/fix-reference-cols.py $(REF_DOC)
	@echo "Reference doc created: $(REF_DOC)"

$(REF_DOC): $(DOCX_TMPL) scripts/fix-reference-cols.py
	cp $(DOCX_TMPL) $(REF_DOC)
	$(RUN) python3 scripts/fix-reference-cols.py $(REF_DOC)
	@echo "Reference doc created: $(REF_DOC)"

# Independent slide-prep helper — NOT wired into build/all. Requires HOST tools
# (gs + inkscape, outside Docker) and a bring-your-own PDF (default src/figs/fig1.pdf,
# not shipped). Skips (exit 0) when the input PDF or host tools are absent.
fig-pptx:  ## src/figs/<name>.pdf -> dist/figs/<name>.emf (PowerPoint vector; HOST gs+inkscape, bring-your-own PDF)
	./scripts/pdf-to-pptx-vector.sh

clean:  ## Remove generated docx and PDF files
	rm -f $(DIST_DIR)/$(PROJECT_NAME)*.docx $(DIST_DIR)/$(PROJECT_NAME)*.pdf
	rm -f $(SRC_DIR)/figs/*.svg.png
	@echo "Cleaned: generated docx + PDF + SVG PNG files"

docker-build:  ## Build the Docker image
	$(COMPOSE) build

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
