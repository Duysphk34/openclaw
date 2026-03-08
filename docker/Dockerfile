FROM node:22-bookworm
LABEL maintainer="OpenClaw Community"
LABEL description="OpenClaw - Enhanced with LaTeX, Pandoc, Gemini CLI, Crawl4AI"
LABEL version="4.3-persistent"

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
    # FIX: symlink gosu vào /usr/local/bin để luôn tìm thấy trong mọi PATH context
    && ln -sf /usr/sbin/gosu /usr/local/bin/gosu \
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
# 4b. Clone repos vào /opt/repos-seed/ (baked vào image)
#     Volume /opt/<repo>/ sẽ được entrypoint populate khi khởi động
# ============================================
RUN mkdir -p /opt/repos-seed

RUN git clone --depth 1 https://github.com/nhadaututtheky/neural-memory.git \
        /opt/repos-seed/neural-memory

RUN git clone --depth 1 https://github.com/googleworkspace/cli.git \
        /opt/repos-seed/googleworkspace-cli \
    && if [ -f /opt/repos-seed/googleworkspace-cli/package.json ]; then \
           npm install --prefix /opt/repos-seed/googleworkspace-cli --ignore-scripts; \
       fi

RUN git clone --depth 1 https://github.com/jo-inc/camofox-browser.git \
        /opt/repos-seed/camofox-browser \
    && if [ -f /opt/repos-seed/camofox-browser/requirements.txt ]; then \
           pip3 install --no-cache-dir --break-system-packages \
               -r /opt/repos-seed/camofox-browser/requirements.txt; \
       fi \
    && rm -rf /root/.cache/pip

RUN git clone --depth 1 https://github.com/unclecode/crawl4ai.git \
        /opt/repos-seed/crawl4ai

RUN git clone --depth 1 https://github.com/darkamenosa/openzalo.git \
        /opt/repos-seed/openzalo

# Placeholder cho volume mount points
RUN mkdir -p \
        /opt/neural-memory \
        /opt/googleworkspace-cli \
        /opt/camofox-browser \
        /opt/crawl4ai \
        /opt/openzalo-src \
    && chown -R root:root /opt/repos-seed

# ============================================
# 4c. Fix PATH trong login shell
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
RUN pnpm install --frozen-lockfile --ignore-scripts || pnpm install --ignore-scripts
RUN pnpm build
RUN pnpm ui:build 2>&1 || echo "⚠️  ui:build không thành công"

# ============================================
# 9. Entrypoint Script
# ============================================
USER root
RUN cat > /usr/local/bin/entrypoint.sh << 'ENTRY'
#!/bin/bash
set -e

# FIX 1: Dùng đường dẫn tuyệt đối — tránh "gosu: command not found"
GOSU="/usr/local/bin/gosu"
OPENCLAW_BIN="node /app/dist/index.js"
CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
MARKER_OPENZALO="/home/openclaw/.openclaw/.openzalo-installed"
SEED_DIR="/opt/repos-seed"

echo "=========================================="
echo "[entrypoint] OpenClaw v4.3-persistent"
echo "[entrypoint] Args: $@"
echo "=========================================="

# ============================================================
# HELPER: Đảm bảo repo tồn tại trong /opt/<n>/
# Ưu tiên: volume có sẵn → seed trong image → clone từ git
# ============================================================
ensure_repo() {
    local name="$1"
    local url="$2"
    local dest="/opt/$name"
    local seed="$SEED_DIR/$name"

    if [ -d "$dest" ] && [ "$(ls -A "$dest" 2>/dev/null)" ]; then
        echo "[repo] ✅ $name đã có trên volume"
        return 0
    fi
    mkdir -p "$dest"
    if [ -d "$seed" ] && [ "$(ls -A "$seed" 2>/dev/null)" ]; then
        echo "[repo] 📋 Restore $name từ seed image..."
        cp -a "$seed/." "$dest/"
    else
        echo "[repo] 🌐 Clone $name từ git (fallback)..."
        git clone --depth 1 "$url" "$dest" 2>&1
    fi
    echo "[repo] ✅ $name sẵn sàng."
}

# 1. Đảm bảo repos tồn tại
ensure_repo "neural-memory"       "https://github.com/nhadaututtheky/neural-memory.git"
ensure_repo "googleworkspace-cli" "https://github.com/googleworkspace/cli.git"
ensure_repo "camofox-browser"     "https://github.com/jo-inc/camofox-browser.git"
ensure_repo "crawl4ai"            "https://github.com/unclecode/crawl4ai.git"
ensure_repo "openzalo-src"        "https://github.com/darkamenosa/openzalo.git"

chown -R openclaw:openclaw \
    /opt/neural-memory \
    /opt/googleworkspace-cli \
    /opt/camofox-browser \
    /opt/crawl4ai \
    /opt/openzalo-src 2>/dev/null || true

# 2. Tạo thư mục làm việc
echo "[entrypoint] 📁 Khởi tạo thư mục..."
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

# 3. Config mặc định
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] ⚡ Sinh openclaw.json mặc định..."
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

# 4. Sync neural-memory skills
MARKER_NEURAL="/home/openclaw/.openclaw/.neural-memory-installed"
if [ ! -f "$MARKER_NEURAL" ] && [ -d "/opt/neural-memory" ]; then
    echo "[entrypoint] 🧠 Sync neural-memory skills từ image → volume..."
    find "/opt/neural-memory" -maxdepth 2 -name "*.md" \
        -exec cp {} /home/openclaw/.openclaw/skills/ \;
    [ -d "/opt/neural-memory/skills" ] && \
        cp -r "/opt/neural-memory/skills/." /home/openclaw/.openclaw/skills/
    chown -R openclaw:openclaw /home/openclaw/.openclaw/skills
    touch "$MARKER_NEURAL"
    echo "[entrypoint] ✅ Skills đã sync."
fi

# 5. Cài OpenZalo (chỉ lần đầu)
if [ ! -f "$MARKER_OPENZALO" ]; then
    echo "[entrypoint] 📦 Cài plugin OpenZalo..."
    $GOSU openclaw $OPENCLAW_BIN plugins install "/opt/openzalo-src" 2>&1 || \
        echo "[entrypoint] ⚠️  OpenZalo install lỗi, tiếp tục..."
    touch "$MARKER_OPENZALO"
    echo "[entrypoint] ✅ OpenZalo đã cài."
else
    echo "[entrypoint] ✅ OpenZalo đã có (marker tồn tại trên volume)."
fi

# 6. Doctor --fix
echo "[entrypoint] 🩺 Chạy doctor --fix..."
$GOSU openclaw $OPENCLAW_BIN doctor --fix --non-interactive 2>&1 || true

# ============================================================
# FIX 2: Tránh double prefix "node /app/... node /app/... onboard"
#
# Nếu $1 là "node", "openclaw", hoặc path tuyệt đối
#   → user đã truyền command đầy đủ, exec trực tiếp
# Nếu $1 là subcommand như "onboard", "gateway", ...
#   → prepend $OPENCLAW_BIN
# ============================================================
case "$1" in
    node|openclaw|/usr/local/bin/openclaw|/usr/bin/node)
        FINAL_CMD="$@"
        ;;
    *)
        FINAL_CMD="$OPENCLAW_BIN $@"
        ;;
esac

echo "=========================================="
echo "[entrypoint] 🚀 Exec: $FINAL_CMD"
echo "=========================================="
cd /home/openclaw/.openclaw/workspace

exec $GOSU openclaw $FINAL_CMD
ENTRY
RUN chmod +x /usr/local/bin/entrypoint.sh

# ============================================
# 10. Healthcheck & Runtime
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:18789/health || exit 1

STOPSIGNAL SIGTERM
WORKDIR /home/openclaw/.openclaw/workspace
EXPOSE 18789

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["gateway", "--bind", "lan"]