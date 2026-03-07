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
# 4b. Clone các Git Repos — baked vào image lúc build
#     Không bị mất khi docker compose down/up
# ============================================

# --- neural-memory (OpenClaw Skill dạng .md) ---
# Entrypoint sẽ copy sang ~/.openclaw/skills/ khi khởi động lần đầu
RUN git clone --depth 1 https://github.com/nhadaututtheky/neural-memory.git \
        /opt/neural-memory-src

# --- Google Workspace CLI ---
RUN git clone --depth 1 https://github.com/googleworkspace/cli.git \
        /opt/googleworkspace-cli \
    && if [ -f /opt/googleworkspace-cli/package.json ]; then \
           npm install --prefix /opt/googleworkspace-cli; \
       fi

# --- Camofox Browser ---
RUN git clone --depth 1 https://github.com/jo-inc/camofox-browser.git \
        /opt/camofox-browser \
    && if [ -f /opt/camofox-browser/requirements.txt ]; then \
           pip3 install --no-cache-dir --break-system-packages \
               -r /opt/camofox-browser/requirements.txt; \
       fi \
    && rm -rf /root/.cache/pip

# --- Crawl4AI source (pip đã cài ở bước 4, giữ source để dùng locally) ---
RUN git clone --depth 1 https://github.com/unclecode/crawl4ai.git \
        /opt/crawl4ai

# ============================================
# 4c. Fix lỗi PATH not found khi chạy openclaw onboard
#     Nguyên nhân: openclaw dùng "sh -lc" (login shell)
#     Login shell source /etc/profile → reset PATH → mất tool
#     Fix: thêm script vào /etc/profile.d/ để giữ PATH đúng
# ============================================
RUN printf '%s\n' \
    '# OpenClaw — giữ PATH đúng trong mọi login shell context' \
    'export PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:${PATH}"' \
    'export PNPM_HOME="/pnpm"' \
    'export NODE_ENV=production' \
    'export OPENCLAW_STATE_DIR=/home/openclaw/.openclaw' \
    'export HOME=/home/openclaw' \
    > /etc/profile.d/openclaw-path.sh \
    && chmod +x /etc/profile.d/openclaw-path.sh

# Wrapper /usr/local/bin/openclaw → node /app/dist/index.js
# Để lệnh "openclaw onboard" hoạt động trong mọi shell context
RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' \
        > /usr/local/bin/openclaw \
    && chmod +x /usr/local/bin/openclaw

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
    && chown openclaw:openclaw /home/openclaw/.npmrc \
    && chown -R openclaw:openclaw /opt/neural-memory-src \
    && chown -R openclaw:openclaw /opt/googleworkspace-cli \
    && chown -R openclaw:openclaw /opt/camofox-browser \
    && chown -R openclaw:openclaw /opt/crawl4ai

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
# 10. Entrypoint Script
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
    "auth": { "mode": "token", "token": "c95e046c2e849446da864f322fb9ef97bd6202181769da96dc39332bcacbd216" },
    "trustedProxies": [ "0.0.0.0/0" ]
  }
}
EOF
    chown openclaw:openclaw "$CONFIG_FILE"
fi

# 3. Cài neural-memory Skill (copy .md vào ~/.openclaw/skills/)
NEURAL_MEMORY_SRC="/opt/neural-memory-src"
NEURAL_MEMORY_MARKER="/home/openclaw/.openclaw/.neural-memory-installed"
if [ ! -f "$NEURAL_MEMORY_MARKER" ] && [ -d "$NEURAL_MEMORY_SRC" ]; then
    echo "[entrypoint] 🧠 Cài neural-memory skill..."
    mkdir -p /home/openclaw/.openclaw/skills
    find "$NEURAL_MEMORY_SRC" -maxdepth 2 -name "*.md" \
        -exec cp {} /home/openclaw/.openclaw/skills/ \;
    [ -d "$NEURAL_MEMORY_SRC/skills" ] && \
        cp -r "$NEURAL_MEMORY_SRC/skills/." /home/openclaw/.openclaw/skills/
    chown -R openclaw:openclaw /home/openclaw/.openclaw/skills
    touch "$NEURAL_MEMORY_MARKER"
    echo "[entrypoint] ✅ neural-memory skill đã cài vào ~/.openclaw/skills/"
fi

# 4. Cài đặt OpenZalo bằng quyền ROOT (Bước 2 của hướng dẫn)
if [ ! -f "$MARKER_FILE" ]; then
    echo "[entrypoint] 📦 Đang cài đặt plugin OpenZalo bằng quyền root..."
    $OPENCLAW_BIN plugins install "$OPENZALO_SRC" 2>&1
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