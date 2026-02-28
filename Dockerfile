FROM node:22-bookworm
LABEL maintainer="OpenClaw Community"
LABEL description="OpenClaw - Enhanced with LaTeX, Pandoc, Gemini CLI, Crawl4AI"
LABEL version="4.2-enhanced"

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
# 2. TeXLive Full (~5GB - tách layer riêng để cache)
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
# 5. Bun & PNPM
# ============================================
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun/bin/bun /usr/local/bin/bun \
    && rm -rf /root/.bun

RUN corepack enable && corepack prepare pnpm@9 --activate

# ============================================
# 6. User Setup (UID 1000) + QUYỀN ROOT
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
# 7. Helper Scripts (bot cài gói nhanh)
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

# CACHE_BUST để force clone lại khi cần (docker build --build-arg CACHE_BUST=$(date +%s))
ARG CACHE_BUST=1
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git . \
    && chown -R openclaw:openclaw /app \
    && mkdir -p /pnpm /home/openclaw/.cache \
    && chown -R openclaw:openclaw /pnpm /home/openclaw

USER openclaw
RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build
RUN pnpm ui:build 2>&1 || echo "⚠️  ui:build không thành công (OK nếu dùng API-only mode)"

# ============================================
# 9. Pre-stage Plugin OpenZalo
# ============================================
USER root
RUN git clone --depth 1 https://github.com/darkamenosa/openzalo.git /opt/openzalo-src \
    && chown -R openclaw:openclaw /opt/openzalo-src

# ============================================
# 10. Script Patch Config Zalo
# ============================================
# Tự động thêm channels.openzalo vào openclaw.json
# (Bước 5 hướng dẫn: thêm channel config)
# ⚠️  CHỈ thêm SAU khi plugin đã loaded, KHÔNG thêm trước
RUN cat > /usr/local/bin/patch-openzalo.js << 'PATCH'
const fs = require('fs');
const configPath = '/home/openclaw/.openclaw/openclaw.json';

try {
  if (!fs.existsSync(configPath)) {
    console.log('[patch] ℹ️  Config chưa tồn tại, bỏ qua.');
    process.exit(0);
  }

  const raw = fs.readFileSync(configPath, 'utf8');
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch (parseErr) {
    console.error('[patch] ❌ Lỗi parse JSON config:', parseErr.message);
    const backupPath = configPath + '.backup.' + Date.now();
    fs.copyFileSync(configPath, backupPath);
    console.log('[patch] 📋 Đã backup config lỗi tại:', backupPath);
    process.exit(1);
  }

  let changed = false;

  // Thêm channels.openzalo nếu chưa có
  if (!cfg.channels) cfg.channels = {};
  if (!cfg.channels.openzalo) {
    cfg.channels.openzalo = {
      enabled: true,
      dmPolicy: "pairing",
      groupPolicy: "allowlist",
      groupRequireMention: true,
      sendFailureNotice: true,
      textChunkLimit: 2000
    };
    changed = true;
    console.log('[patch] ✅ Đã thêm cấu hình channels.openzalo');
  } else {
    console.log('[patch] ℹ️  channels.openzalo đã tồn tại, bỏ qua.');
  }

  if (changed) {
    const tmpPath = configPath + '.tmp';
    fs.writeFileSync(tmpPath, JSON.stringify(cfg, null, 2));
    fs.renameSync(tmpPath, configPath);
    console.log('[patch] ✅ Đã lưu config thành công.');
  }
} catch (err) {
  console.error('[patch] ❌ Lỗi không mong muốn:', err.message);
  process.exit(1);
}
PATCH
RUN chmod +x /usr/local/bin/patch-openzalo.js

# ============================================
# 11. Entrypoint Script
# ============================================
RUN cat > /usr/local/bin/entrypoint.sh << 'ENTRY'
#!/bin/bash

echo "=========================================="
echo "[entrypoint] OpenClaw v4.2-enhanced"
echo "[entrypoint] Đang chuẩn bị môi trường..."
echo "=========================================="

OPENCLAW_BIN="node /app/dist/index.js"
CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
MARKER_FILE="/home/openclaw/.openclaw/.openzalo-installed"
OPENZALO_SRC="/opt/openzalo-src"
OPENZALO_EXT="/home/openclaw/.openclaw/extensions/openzalo"

# -------------------------------------------
# 1. Tạo và cấp quyền thư mục
# -------------------------------------------
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

if [ ! -f /home/openclaw/.npmrc ]; then
    echo "prefix=/home/openclaw/.npm-global" > /home/openclaw/.npmrc
    chown openclaw:openclaw /home/openclaw/.npmrc
fi

# -------------------------------------------
# 2. Tự động khởi tạo config nếu trống
# -------------------------------------------
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
    "auth": {
      "mode": "token",
      "token": ""
    },
    "trustedProxies": [
      "0.0.0.0/0"
    ],
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "nodes": {
      "denyCommands": [
        "camera.snap",
        "camera.clip",
        "screen.record",
        "calendar.add",
        "contacts.add",
        "reminders.add"
      ]
    }
  }
}
EOF
    chown openclaw:openclaw "$CONFIG_FILE"
    echo "[entrypoint] ✅ Đã tạo config mặc định."
else
    if ! python3 -c "import json; json.load(open('$CONFIG_FILE'))" 2>/dev/null; then
        echo "[entrypoint] ⚠️  Config JSON bị lỗi! Backup và tạo mới..."
        cp "$CONFIG_FILE" "${CONFIG_FILE}.broken.$(date +%s)" 2>/dev/null || true
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
    "auth": {
      "mode": "token",
      "token": ""
    },
    "trustedProxies": [
      "0.0.0.0/0"
    ],
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "nodes": {
      "denyCommands": [
        "camera.snap",
        "camera.clip",
        "screen.record",
        "calendar.add",
        "contacts.add",
        "reminders.add"
      ]
    }
  }
}
EOF
        chown openclaw:openclaw "$CONFIG_FILE"
    else
        echo "[entrypoint] ✅ Config hợp lệ."
    fi
fi

# -------------------------------------------
# 3. Cài đặt Plugin OpenZalo (idempotent)
# -------------------------------------------
if [ -d "$OPENZALO_EXT" ] && [ -f "$MARKER_FILE" ]; then
    echo "[entrypoint] ℹ️  OpenZalo đã cài sẵn."
elif [ -d "$OPENZALO_SRC" ]; then
    echo "[entrypoint] 📦 Đang cài đặt plugin OpenZalo..."
    if gosu openclaw $OPENCLAW_BIN plugins install "$OPENZALO_SRC" 2>&1; then
        gosu openclaw touch "$MARKER_FILE"
        echo "[entrypoint] ✅ OpenZalo đã cài thành công."
    else
        echo "[entrypoint] ⚠️  CLI install thất bại, thử fallback copy..."
        if [ -f "${OPENZALO_SRC}/openclaw.plugin.json" ]; then
            gosu openclaw mkdir -p "$OPENZALO_EXT"
            gosu openclaw cp -r "${OPENZALO_SRC}/." "$OPENZALO_EXT/"
            if [ -f "${OPENZALO_EXT}/package.json" ]; then
                cd "$OPENZALO_EXT"
                gosu openclaw npm install --production 2>&1 || true
                cd /app
            fi
            gosu openclaw touch "$MARKER_FILE"
            echo "[entrypoint] ✅ OpenZalo đã copy qua fallback."
        else
            echo "[entrypoint] ⚠️  OpenZalo cài thất bại (thử lại lần sau)."
        fi
    fi
fi

# -------------------------------------------
# 4. Cấp quyền extensions
# -------------------------------------------
chown -R openclaw:openclaw /home/openclaw/.openclaw/extensions 2>/dev/null || true
chmod -R 755 /home/openclaw/.openclaw/extensions 2>/dev/null || true

# -------------------------------------------
# 5. Patch cấu hình OpenZalo
# -------------------------------------------
# ⚠️  Thứ tự quan trọng: cài plugin (bước 3) → patch config (bước 5)
# KHÔNG patch trước khi plugin loaded → gây lỗi "unknown channel id"
echo "[entrypoint] 🔧 Kiểm tra cấu hình OpenZalo..."
gosu openclaw node /usr/local/bin/patch-openzalo.js 2>&1 || true

# -------------------------------------------
# 6. Auto Doctor --fix
# -------------------------------------------
if echo "$*" | grep -q "gateway"; then
    echo "[entrypoint] 🩺 Chạy doctor --fix tự động..."
    gosu openclaw $OPENCLAW_BIN doctor --fix --non-interactive 2>&1 || true
fi

# -------------------------------------------
# 7. Chờ PostgreSQL (nếu có DB_HOST)
# -------------------------------------------
if [ -n "$DB_HOST" ]; then
    echo "[entrypoint] 🐘 Chờ PostgreSQL tại $DB_HOST:${DB_PORT:-5432}..."
    for i in $(seq 1 30); do
        if pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USER:-openclaw}" -q 2>/dev/null; then
            echo "[entrypoint] ✅ PostgreSQL sẵn sàng."
            break
        fi
        [ "$i" -eq 30 ] && echo "[entrypoint] ⚠️  PostgreSQL timeout 30s, tiếp tục..."
        sleep 1
    done
fi

# -------------------------------------------
# 8. Khởi chạy
# -------------------------------------------
echo "=========================================="
echo "[entrypoint] 🚀 Hoàn tất! Khởi chạy: $*"
echo "=========================================="
cd /home/openclaw/.openclaw/workspace

exec gosu openclaw "$@"
ENTRY
RUN chmod +x /usr/local/bin/entrypoint.sh

# ============================================
# 12. Healthcheck & Runtime
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:18789/health || exit 1

STOPSIGNAL SIGTERM
WORKDIR /home/openclaw/.openclaw/workspace
EXPOSE 18789

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["node", "/app/dist/index.js", "gateway", "--bind", "lan"]
