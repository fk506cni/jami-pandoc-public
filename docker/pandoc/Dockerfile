# JAMI2026 Pandoc Build Environment
FROM ubuntu:24.04

ARG PANDOC_VERSION=3.6.4
ARG CROSSREF_VERSION=0.3.19

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    xz-utils \
    # Japanese fonts
    fonts-noto-cjk \
    fonts-ipafont-mincho \
    fonts-ipafont-gothic \
    fontconfig \
    # SVG to PNG conversion (rsvg-convert)
    librsvg2-bin \
    # LibreOffice Writer (headless, for .doc -> .docx conversion)
    libreoffice-writer \
    # Node.js for pandiff
    nodejs \
    npm \
    # git for pandiff git diff
    git \
    && rm -rf /var/lib/apt/lists/*

# Update font cache
RUN fc-cache -fv

# Install Pandoc from GitHub release
RUN wget -q "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-1-amd64.deb" \
    -O /tmp/pandoc.deb \
    && dpkg -i /tmp/pandoc.deb \
    && rm /tmp/pandoc.deb

# Install pandoc-crossref from GitHub release
RUN wget -q "https://github.com/lierdakil/pandoc-crossref/releases/download/v${CROSSREF_VERSION}/pandoc-crossref-Linux-X64.tar.xz" \
    -O /tmp/pandoc-crossref.tar.xz \
    && tar -xf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/pandoc-crossref \
    && rm /tmp/pandoc-crossref.tar.xz

# Install pandiff
RUN npm install -g pandiff

# Mark /workspace as safe for git
RUN git config --system --add safe.directory /workspace

WORKDIR /workspace

CMD ["pandoc", "--version"]
