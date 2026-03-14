# 🚀 Hướng dẫn triển khai OpenClaw + OpenZalo trên VPS

## Yêu cầu VPS
- Ubuntu 22.04+ / Debian 12+
- RAM: tối thiểu 4GB (khuyến nghị 8GB vì texlive-full + AI packages)
- Disk: tối thiểu 30GB trống (image ~15GB + AI packages ~5GB + data)
- Docker + Docker Compose đã cài
- Traefik đã chạy (hoặc reverse proxy khác)

---

## PHẦN 1: CHUẨN BỊ (5 phút)

### Bước 1: Tạo thư mục project

```bash
mkdir -p ~/openclaw
cd ~/openclaw
```

### Bước 2: Upload 4 file vào ~/openclaw/

Copy 4 file vào thư mục `~/openclaw/`:

```
~/openclaw/
├── docker/
│   └── Dockerfile
├── docker-compose.yml
├── .env.example
└── init.sh
```

> Có thể dùng `scp`, `rsync`, hoặc paste trực tiếp bằng `nano`.

### Bước 3: Chạy init.sh

```bash
cd ~/openclaw
chmod +x init.sh
bash init.sh
```

Script sẽ tự động:
- Tạo `data/openclaw/`, `data/zalo/`, `data/postgres/`
- Tạo `.env` từ `.env.example`
- Tạo docker network `traefik-network` (nếu chưa có)

### Bước 4: Sửa file .env

```bash
nano .env
```

Điền thông tin thật:

```env
# Database
DB_USER=openclaw
DB_PASS=MatKhauManh123!      ← ĐỔI MẬT KHẨU

# API Keys
OPENAI_API_KEY=sk-xxx         ← KEY THẬT
ANTHROPIC_API_KEY=sk-ant-xxx  ← KEY THẬT
GOOGLE_API_KEY=AIza-xxx       ← KEY THẬT (cho Gemini)

# Domain
SUBDOMAIN=openclaw            ← subdomain của bạn
DOMAIN_NAME=example.com       ← domain của bạn
```

Lưu: `Ctrl+O` → `Enter` → `Ctrl+X`

---

## PHẦN 2: BUILD & CHẠY (15-30 phút lần đầu)

### Bước 5: Build image

```bash
cd ~/openclaw
docker compose build
```

> ⏳ Lần đầu build rất lâu (~15-30 phút) do tải texlive-full (~5GB).
> Lần sau rebuild nhanh hơn nhiều nhờ Docker layer cache.

Nếu muốn xem tiến trình chi tiết:

```bash
docker compose build --progress=plain
```

### Bước 6: Khởi động tất cả services

```bash
docker compose up -d
```

### Bước 7: Kiểm tra trạng thái

```bash
# Xem tất cả containers
docker compose ps

# Kết quả mong đợi:
# openclaw-postgres    running (healthy)
# openclaw-gateway     running
```

### Bước 8: Xem logs

```bash
# Logs gateway (quan trọng nhất)
docker compose logs -f openclaw-gateway

# Logs PostgreSQL
docker compose logs -f postgres

# Tất cả
docker compose logs -f
```

Logs gateway thành công sẽ thấy:

```
[entrypoint] OpenClaw v4.4-ai-autopkg
[ai-pkg] 🚀 Bắt đầu cài AI packages...        ← lần đầu (~10-15 phút)
[ai-pkg] ✅ Đã cài xong 48 packages!
[repo] ✅ neural-memory đã có trên volume
[entrypoint] ✅ OpenZalo đã cài.
[entrypoint] 🩺 Chạy doctor --fix...
[entrypoint] 🚀 Exec: node /app/dist/index.js gateway --bind lan
```

> Lần khởi động tiếp theo sẽ thấy `[ai-pkg] ✅ AI packages đã có trên volume (skip cài đặt)` (~2 giây)

Thoát logs: `Ctrl+C`

---

## PHẦN 3: CÀI ĐẶT OPENZALO (5 phút)

### Bước 9: Login Zalo bằng QR code

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js channels login --channel openzalo
```

- QR code sẽ hiện ra hoặc lưu thành file
- Mở Zalo trên điện thoại → Quét mã QR
- ⚠️ QR có thời hạn, quét nhanh! Hết hạn thì chạy lại lệnh trên

### Bước 10: Restart gateway sau khi login

```bash
docker compose restart openclaw-gateway
```

### Bước 11: Test nhắn tin

- Mở Zalo trên điện thoại
- Nhắn tin cho tài khoản vừa quét QR
- Bot sẽ trả về **mã pairing** (VD: `ABC12345`)

### Bước 12: Approve pairing

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js pairing approve openzalo ABC12345
```

> Thay `ABC12345` bằng mã pairing thật

### Bước 13: Nhắn lại trên Zalo

Bot sẽ trả lời! 🎉

---

## PHẦN 4: LỆNH QUẢN TRỊ THƯỜNG DÙNG

### Xem trạng thái

```bash
# Trạng thái containers
docker compose ps

# Logs realtime
docker compose logs -f openclaw-gateway

# Kiểm tra plugins
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js plugins list

# Doctor check
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js doctor --non-interactive
```

### Restart / Stop

```bash
# Restart gateway
docker compose restart openclaw-gateway

# Restart tất cả
docker compose restart

# Dừng tất cả
docker compose down

# Dừng + xóa volumes (⚠️ MẤT DỮ LIỆU)
docker compose down -v
```

### Dùng CLI

```bash
# Onboard (cấu hình lần đầu)
docker compose --profile cli run --rm openclaw-cli onboard

# Doctor fix
docker compose --profile cli run --rm openclaw-cli doctor --fix

# Hoặc truyền full command (cũng được)
docker compose --profile cli run --rm openclaw-cli node /app/dist/index.js doctor --fix

# Help
docker compose --profile cli run --rm openclaw-cli --help
```

> **Lưu ý:** Phải có `--profile cli` khi dùng `openclaw-cli`.
> Không cần gõ `node /app/dist/index.js` — entrypoint tự thêm.

### Cài thêm gói trong container

```bash
# Vào shell container
docker exec -it openclaw-gateway bash

# Bên trong container, bot có quyền sudo:
install-pkg imagemagick        # cài apt package
install-pip pandas numpy       # cài Python package (persist trên volume!)
install-npm typescript         # cài NPM package
```

> 💡 Gói cài bằng `install-pip` được lưu vào volume `/opt/ai-persist` → **không mất khi docker compose down**.
> Gói cài bằng `install-pkg` (apt) sẽ mất khi recreate container.

### Xem AI packages đã cài

```bash
# Kiểm tra trạng thái AI packages
docker exec -it openclaw-gateway cat /opt/ai-persist/.ai-packages-installed

# Xem danh sách packages
docker exec -it openclaw-gateway pip3 list --user

# Cài lại AI packages (nếu cần)
docker exec -it openclaw-gateway /usr/local/bin/ai-pkg-setup
```

### Cập nhật OpenClaw lên version mới

```bash
cd ~/openclaw
docker compose build --no-cache --build-arg CACHE_BUST=$(date +%s)
docker compose up -d
```

### Xem/sửa config

```bash
# Xem config
cat data/openclaw/openclaw.json | python3 -m json.tool

# Sửa config
nano data/openclaw/openclaw.json

# Restart để áp dụng
docker compose restart openclaw-gateway
```

### Backup

```bash
# Backup toàn bộ data
cd ~/openclaw
tar czf backup-$(date +%Y%m%d).tar.gz data/ .env
```

### Zalo hết phiên / cần login lại

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js channels login --channel openzalo

# Quét QR xong thì restart
docker compose restart openclaw-gateway
```

---

## XỬ LÝ LỖI THƯỜNG GẶP

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `unknown channel id: openzalo` | Plugin chưa loaded | `docker compose restart openclaw-gateway` rồi chờ |
| `Config JSON bị lỗi` | openclaw.json hỏng | Entrypoint tự backup + tạo mới, chỉ cần restart |
| `PostgreSQL timeout` | DB chưa sẵn sàng | `docker compose restart openclaw-gateway` |
| QR code hết hạn | Quét chậm | Chạy lại lệnh login (Bước 9) |
| Gateway không start | Xem logs | `docker compose logs openclaw-gateway` |
| Build quá lâu | texlive-full ~5GB | Bình thường lần đầu, lần sau cache nhanh |
| AI packages cài lâu | Lần đầu ~10-15 phút | Bình thường, lần sau skip (~2 giây). Xem logs: `docker compose logs openclaw-gateway \| grep ai-pkg` |
| AI packages mất sau down | Dùng `down -v` xóa volume | Dùng `docker compose down` (không có `-v`) để giữ volumes |
| Port 18789 đã dùng | Trùng port | Sửa port trong docker-compose.yml |
