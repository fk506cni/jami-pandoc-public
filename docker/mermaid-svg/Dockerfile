# Mermaid/SVG to PDF Conversion Environment
# Image: latex-template-mermaid

FROM node:20-slim

# Install system packages
# - inkscape: SVG to PDF conversion
# - chromium: Required by mermaid-cli (puppeteer)
# - fonts-noto-cjk: Japanese fonts
# - fonts-ipafont: IPA fonts for Japanese
RUN apt-get update && apt-get install -y --no-install-recommends \
    inkscape \
    chromium \
    fonts-noto-cjk \
    fonts-ipafont \
    fonts-liberation \
    fontconfig \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Update font cache
RUN fc-cache -fv

# Set puppeteer to use system chromium instead of downloading its own
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Install mermaid-cli globally
RUN npm install -g @mermaid-js/mermaid-cli

# Copy puppeteer config for sandboxed execution
COPY puppeteer-config.json /etc/puppeteer-config.json

# Set working directory
WORKDIR /workspace

# Default command
CMD ["mmdc", "--version"]
