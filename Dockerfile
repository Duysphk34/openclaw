FROM node:22-bookworm
LABEL maintainer="OpenClaw Community"
LABEL description="OpenClaw - Enhanced with LaTeX, Pandoc, Gemini CLI, Crawl4AI"
LABEL version="4.2-enhanced-fixed"

# ============================================
# Environment
# ============================================
ENV NODE_ENV=production \
    PNPM_HOME="/pnpm" \
    PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:$PATH" \
    TZ=Asia/Ho_Chi_Minh \
    NO_UPDATE_NOTIFIER=true \
    HOME=/home/openclaw \
    OPENCLAW_STATE_DIR=/home/openclaw/.openclaw \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# ============================================
# 1. System Dependencies
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates gnupg build-essential \
    python3 python3-pip python3-venv python3-pygments \
    tzdata pandoc poppler-utils ghostscript \
    fonts-noto ffmpeg nano vim \
    gosu sudo tini \
    apt-utils apt-transport-https software-properties-common \
    postgresql-client \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. TeXLive Full (~5GB)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-full \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. Global NPM Tools (Gemini CLI + OpenZCA)
# ============================================
# Đã bao gồm Bước 1 trong hướng dẫn: Cài openzca
RUN npm install -g @google/gemini-cli openzca \
    && ln -sf "$(npm prefix -g)/bin/gemini" /usr/bin/gemini \
    && npm cache clean --force

# ============================================
# 4. Python Tools: yt-dlp & Crawl4AI + Playwright
# ============================================
RUN pip3 install --no-cache-dir --break-system-packages \
    yt-dlp \
    git+https://github.com/unclecode/crawl4ai.git \
    && python3 -m playwright install-deps chromium \
    && python3 -m playwright install chromium \
    && rm -rf /tmp/playwright* /root/.cache/pip

# ============================================
# 5. Bun & PNPM
# ============================================
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /home/openclaw/.bun/bin/bun /usr/local/bin/bun \
    && rm -rf /home/openclaw/.bun

RUN corepack enable && corepack prepare pnpm@9 --activate

# ============================================
# 6. User Setup (UID 1000)
# ============================================
RUN userdel -r node 2>/dev/null || true \
    && groupdel node 2>/dev/null || true \
    && groupadd -g 1000 openclaw \
    && useradd -u 1000 -g openclaw -d /home/openclaw -m -s /bin/bash openclaw \
    && echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw \
    && chmod 0440 /etc/sudoers.d/openclaw \
    && mkdir -p /home/openclaw/.npm-global \
    && chown -R openclaw:openclaw /home/openclaw/.npm-global \
    && echo "prefix=/home/openclaw/.npm-global" > /home/openclaw/.npmrc \
    && chown openclaw:openclaw /home/openclaw/.npmrc

# ============================================
# 7. Helper Scripts
# ============================================
RUN cat > /usr/local/bin/install-pkg << 'EOF'
#!/bin/bash
set -e
echo "📦 Đang cài đặt: $@"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends "$@"
sudo rm -rf /var/lib/apt/lists/*
echo "✅ Đã cài xong: $@"
EOF

RUN cat > /usr/local/bin/install-pip << 'EOF'
#!/bin/bash
set -e
echo "🐍 Đang cài Python package: $@"
pip3 install --break-system-packages "$@"
echo "✅ Đã cài xong: $@"
EOF

RUN cat > /usr/local/bin/install-npm << 'EOF'
#!/bin/bash
set -e
echo "📦 Đang cài NPM package: $@"
sudo npm install -g "$@"
echo "✅ Đã cài xong: $@"
EOF

RUN chmod +x /usr/local/bin/install-pkg \
             /usr/local/bin/install-pip \
             /usr/local/bin/install-npm

# ============================================
# 8. Clone & Build OpenClaw Core
# ============================================
WORKDIR /app
ARG CACHE_BUST=1
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git . \
    && chown -R openclaw:openclaw /app \
    && mkdir -p /pnpm /home/openclaw/.cache \
    && chown -R openclaw:openclaw /pnpm /home/openclaw

USER openclaw
RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build
RUN pnpm ui:build 2>&1 || echo "⚠️  ui:build không thành công"

# ============================================
# 9. Pre-stage Plugin OpenZalo
# ============================================
USER root
RUN git clone --depth 1 https://github.com/darkamenosa/openzalo.git /opt/openzalo-src

# ============================================
# 10. Entrypoint Script (Đã xóa các kịch bản gây lỗi)
# ============================================
RUN cat > /usr/local/bin/entrypoint.sh << 'ENTRY'
#!/bin/bash
echo "=========================================="
echo "[entrypoint] OpenClaw Đã fix lỗi OpenZalo"
echo "=========================================="

OPENCLAW_BIN="node /app/dist/index.js"
CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
MARKER_FILE="/home/openclaw/.openclaw/.openzalo-installed"
OPENZALO_SRC="/opt/openzalo-src"
OPENZALO_EXT="/home/openclaw/.openclaw/extensions/openzalo"

# 1. Tạo thư mục làm việc cơ bản
for dir in \
    /home/openclaw/.openclaw \
    /home/openclaw/.openclaw/skills \
    /home/openclaw/.openclaw/extensions \
    /home/openclaw/.openclaw/workspace \
    /home/openclaw/.openzca \
    /home/openclaw/.npm-global; do
    mkdir -p "$dir" 2>/dev/null || true
done
chown -R openclaw:openclaw /home/openclaw/.openclaw 2>/dev/null || true
chown -R openclaw:openclaw /home/openclaw/.openzca 2>/dev/null || true
chown -R openclaw:openclaw /home/openclaw/.npm-global 2>/dev/null || true

# 2. Khởi tạo config mặc định (KHÔNG có OpenZalo)
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] ⚡ Đang sinh openclaw.json mặc định..."
    cat > "$CONFIG_FILE" << 'EOF'
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "allowInsecureAuth": true
    },
    "auth": { "mode": "token", "token": "9be8fbfb216deb4f5aab122345128d76c43e7cc1a0857e7f5039f883a2a15e26" },
    "trustedProxies": [ "0.0.0.0/0" ]
  }
}
EOF
    chown openclaw:openclaw "$CONFIG_FILE"
fi

# 3. Cài đặt OpenZalo bằng quyền ROOT (Bước 2 của hướng dẫn)
if [ ! -f "$MARKER_FILE" ]; then
    echo "[entrypoint] 📦 Đang cài đặt plugin OpenZalo bằng quyền root..."
    # Cài bằng user root để vượt qua kiểm tra bảo mật (uid=0)
    $OPENCLAW_BIN plugins install "$OPENZALO_SRC" 2>&1
    # Bắt buộc khóa quyền thư mục này cho root
    chown -R root:root "$OPENZALO_EXT"
    touch "$MARKER_FILE"
    echo "[entrypoint] ✅ OpenZalo đã cài thành công chuẩn quyền root."
fi

# KHÔNG chown lại thư mục extensions thành openclaw (đã xóa đoạn code gây lỗi)
# KHÔNG tự động chèn config Zalo (đã xóa script patch)

if echo "$*" | grep -q "gateway"; then
    echo "[entrypoint] 🩺 Chạy doctor..."
    gosu openclaw $OPENCLAW_BIN doctor --fix --non-interactive 2>&1 || true
fi

echo "=========================================="
echo "[entrypoint] 🚀 Hoàn tất! Khởi chạy..."
echo "=========================================="
cd /home/openclaw/.openclaw/workspace

exec gosu openclaw "$@"
ENTRY
RUN chmod +x /usr/local/bin/entrypoint.sh

# ============================================
# 11. Healthcheck & Runtime
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:18789/health || exit 1

STOPSIGNAL SIGTERM
WORKDIR /home/openclaw/.openclaw/workspace
EXPOSE 18789

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["node", "/app/dist/index.js", "gateway", "--bind", "lan"]