# Huong dan trien khai OpenClaw + OpenZalo tren VPS

## Yeu cau VPS

- Ubuntu 22.04+ / Debian 12+
- RAM: toi thieu 4GB (khuyen nghi 8GB vi texlive-full + AI packages)
- Disk: toi thieu 30GB trong (image ~15GB + AI packages ~5GB + data)
- Docker + Docker Compose da cai
- Traefik da chay (hoac reverse proxy khac)

---

## PHAN 1: CHUAN BI (5 phut)

### Buoc 1: Cai Docker (neu chua co)

```bash
# Cai Docker
curl -fsSL https://get.docker.com | sh

# Them user hien tai vao group docker (khong can sudo moi lan)
sudo usermod -aG docker $USER

# Dang xuat roi dang nhap lai de co hieu luc
exit
```

Kiem tra:

```bash
docker --version
docker compose version
```

### Buoc 2: Tao thu muc project

```bash
mkdir -p ~/openclaw
cd ~/openclaw
```

### Buoc 3: Upload file vao ~/openclaw/

Copy cac file vao thu muc `~/openclaw/`:

```
~/openclaw/
├── docker/
│   └── Dockerfile
├── docker-compose.yml
├── .env.example
└── init.sh
```

Cach upload tu may tinh local len VPS:

```bash
# Cach 1: scp tu may local
scp -r ./docker ./docker-compose.yml ./.env.example ./init.sh user@your-vps-ip:~/openclaw/

# Cach 2: rsync
rsync -avz ./docker ./docker-compose.yml ./.env.example ./init.sh user@your-vps-ip:~/openclaw/

# Cach 3: git clone (neu da push len repo)
cd ~ && git clone https://github.com/your-repo/openclaw.git
```

### Buoc 4: Chay init.sh

```bash
cd ~/openclaw
chmod +x init.sh
bash init.sh
```

Script se tu dong:
- Tao `data/openclaw/`, `data/zalo/`, `data/postgres/`
- Tao `.env` tu `.env.example`
- Tao docker network `traefik-network` (neu chua co)

Ket qua mong doi:

```
🚀 Dang khoi tao OpenClaw...
✅ Da tao data/openclaw, data/zalo, data/postgres
✅ Da tao .env tu mau → Hay sua .env truoc khi chay!
✅ Da tao docker network: traefik-network

==========================================
  Cau truc thu muc:
==========================================

  /root/openclaw/
  ├── docker/
  │   └── Dockerfile
  ├── docker-compose.yml
  ├── .env              ← SUA FILE NAY
  ├── .env.example
  ├── init.sh
  └── data/
      ├── openclaw/     → config, skills, extensions, workspace
      ├── zalo/         → du lieu Zalo
      └── postgres/     → database

  Docker Volumes (tu dong tao khi docker compose up):
      openclaw-ai-persist  → AI packages (persist qua down/up)
      openclaw-opt-*       → repos (neural-memory, crawl4ai...)
```

### Buoc 5: Sua file .env

```bash
nano .env
```

Dien thong tin that:

```env
# Database
DB_USER=openclaw
DB_PASS=MatKhauManh123!      # <-- DOI MAT KHAU

# API Keys
OPENAI_API_KEY=sk-xxx         # <-- KEY THAT
ANTHROPIC_API_KEY=sk-ant-xxx  # <-- KEY THAT
GOOGLE_API_KEY=AIza-xxx       # <-- KEY THAT (cho Gemini)

# Domain
SUBDOMAIN=openclaw            # <-- subdomain cua ban
DOMAIN_NAME=example.com       # <-- domain cua ban
```

Luu: `Ctrl+O` -> `Enter` -> `Ctrl+X`

---

## PHAN 2: BUILD & CHAY

### Buoc 6: Build image

```bash
cd ~/openclaw
docker compose build
```

> Lan dau build rat lau (~15-30 phut) do tai texlive-full (~5GB).
> Lan sau rebuild nhanh hon nhieu nho Docker layer cache.

Neu muon xem tien trinh chi tiet:

```bash
docker compose build --progress=plain
```

Neu build bi loi timeout mang:

```bash
# Retry voi no-cache
docker compose build --no-cache
```

### Buoc 7: Khoi dong tat ca services

```bash
docker compose up -d
```

Lan dau chay se:
1. Khoi dong PostgreSQL + pgvector
2. Khoi dong OpenClaw Gateway
3. **Tu dong cai 48 AI packages** (OCR, embedding, RAG, data analysis...) ~10-15 phut
4. Setup repos (neural-memory, crawl4ai, openzalo...)
5. Cai plugin OpenZalo
6. Chay doctor --fix

### Buoc 8: Kiem tra trang thai

```bash
# Xem tat ca containers
docker compose ps
```

Ket qua mong doi:

```
NAME                 STATUS              PORTS
openclaw-postgres    running (healthy)
openclaw-gateway     running             18789/tcp
```

Neu `openclaw-gateway` hien `starting` → dang cai AI packages, doi them.

### Buoc 9: Xem logs

```bash
# Logs gateway (quan trong nhat)
docker compose logs -f openclaw-gateway
```

Logs thanh cong se thay:

```
[entrypoint] OpenClaw v4.4-ai-autopkg
[entrypoint] Python: 3.11 | AI site: /opt/ai-persist/python-packages/lib/python3.11/site-packages
[entrypoint] 🤖 Kiem tra AI packages...
[ai-pkg] 🚀 Bat dau cai AI packages...           ← CHI LAN DAU
[ai-pkg] ✅ Da cai xong 48 packages!
[repo] ✅ neural-memory da co tren volume
[repo] ✅ googleworkspace-cli da co tren volume
[repo] ✅ camofox-browser da co tren volume
[repo] ✅ crawl4ai da co tren volume
[repo] ✅ openzalo-src da co tren volume
[entrypoint] ✅ OpenZalo da cai.
[entrypoint] 🩺 Chay doctor --fix...
[entrypoint] 🚀 Exec: node /app/dist/index.js gateway --bind lan
```

Lan khoi dong tiep theo (sau restart/down+up):

```
[ai-pkg] ✅ AI packages da co tren volume (skip cai dat)   ← ~2 giay
```

Chi xem log AI packages:

```bash
docker compose logs openclaw-gateway | grep ai-pkg
```

Thoat logs: `Ctrl+C`

---

## PHAN 3: CAI DAT OPENZALO (5 phut)

### Buoc 10: Login Zalo bang QR code

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js channels login --channel openzalo
```

- QR code se hien ra hoac luu thanh file
- Mo Zalo tren dien thoai → Quet ma QR
- QR co thoi han, quet nhanh! Het han thi chay lai lenh tren

### Buoc 11: Restart gateway sau khi login

```bash
docker compose restart openclaw-gateway
```

### Buoc 12: Test nhan tin

- Mo Zalo tren dien thoai
- Nhan tin cho tai khoan vua quet QR
- Bot se tra ve **ma pairing** (VD: `ABC12345`)

### Buoc 13: Approve pairing

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js pairing approve openzalo ABC12345
```

> Thay `ABC12345` bang ma pairing that

### Buoc 14: Nhan lai tren Zalo

Bot se tra loi!

---

## PHAN 4: LENH CLI

OpenClaw CLI chay qua Docker voi `--profile cli`.

### Cac lenh CLI co ban

```bash
# Onboard (cau hinh lan dau)
docker compose --profile cli run --rm openclaw-cli onboard

# Doctor fix
docker compose --profile cli run --rm openclaw-cli doctor --fix

# Xem help
docker compose --profile cli run --rm openclaw-cli --help

# Xem danh sach plugins
docker compose --profile cli run --rm openclaw-cli plugins list
```

### Truyen full command (cung duoc)

```bash
docker compose --profile cli run --rm openclaw-cli node /app/dist/index.js doctor --fix
```

> **Luu y:**
> - Phai co `--profile cli` khi dung `openclaw-cli`
> - Khong can go `node /app/dist/index.js` — entrypoint tu them
> - CLI co `stdin_open` va `tty` → ho tro interactive (nhap lieu)

---

## PHAN 5: LENH QUAN TRI THUONG DUNG

### Xem trang thai

```bash
# Trang thai containers
docker compose ps

# Logs realtime
docker compose logs -f openclaw-gateway

# Kiem tra plugins
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

# Restart tat ca
docker compose restart

# Dung tat ca (GIU volumes — AI packages khong mat)
docker compose down

# Dung + xoa volumes (⚠️ MAT DU LIEU + AI packages)
docker compose down -v
```

### Cai them goi trong container

```bash
# Vao shell container
docker exec -it openclaw-gateway bash

# Ben trong container:
install-pkg imagemagick        # cai apt package (mat khi recreate)
install-pip pandas numpy       # cai Python package (PERSIST tren volume!)
install-npm typescript         # cai NPM package (mat khi recreate)
```

> `install-pip` luu vao volume `/opt/ai-persist` → **khong mat khi docker compose down**.
> `install-pkg` (apt) va `install-npm` se mat khi recreate container.

### Xem AI packages da cai

```bash
# Kiem tra trang thai
docker exec -it openclaw-gateway cat /opt/ai-persist/.ai-packages-installed

# Xem danh sach packages trong volume
docker exec -it openclaw-gateway ls /opt/ai-persist/python-packages/bin/

# Cai lai AI packages (neu can — VD: sau khi down -v)
docker exec -it openclaw-gateway /usr/local/bin/ai-pkg-setup
```

### Cap nhat OpenClaw len version moi

```bash
cd ~/openclaw
docker compose build --no-cache --build-arg CACHE_BUST=$(date +%s)
docker compose up -d
```

> AI packages tren volume KHONG bi anh huong khi rebuild image.

### Xem/sua config

```bash
# Xem config
cat data/openclaw/openclaw.json | python3 -m json.tool

# Sua config
nano data/openclaw/openclaw.json

# Restart de ap dung
docker compose restart openclaw-gateway
```

### Backup

```bash
cd ~/openclaw

# Backup data thu muc
tar czf backup-$(date +%Y%m%d).tar.gz data/ .env

# Backup luon AI packages volume (tuy chon)
docker run --rm -v openclaw-ai-persist:/data -v $(pwd):/backup \
  alpine tar czf /backup/ai-packages-backup.tar.gz -C /data .
```

### Restore AI packages tu backup

```bash
docker run --rm -v openclaw-ai-persist:/data -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/ai-packages-backup.tar.gz"
```

### Zalo het phien / can login lai

```bash
docker exec -it openclaw-gateway \
  gosu openclaw node /app/dist/index.js channels login --channel openzalo

# Quet QR xong thi restart
docker compose restart openclaw-gateway
```

---

## PHAN 6: AI PACKAGES — CHI TIET

### Danh sach 48 goi duoc tu dong cai

| Nhom | Goi |
|------|-----|
| AI/LLM SDKs | openai, anthropic, google-generativeai, langchain, langchain-community, langchain-openai, langchain-anthropic, litellm |
| Embedding & Vector DB | sentence-transformers, fastembed, tiktoken, chromadb, pgvector |
| RAG & Document | llama-index, unstructured, pypdf, pymupdf, python-docx, python-pptx, openpyxl, beautifulsoup4, lxml, markdownify |
| OCR | pytesseract, easyocr, Pillow, opencv-python-headless |
| Data Analysis | pandas, numpy, scipy, scikit-learn, matplotlib, seaborn, plotly, tabulate, psycopg2-binary, sqlalchemy |
| Image & Video | moviepy, rembg, imageio[ffmpeg] |
| Audio/Speech | openai-whisper, pydub, gtts, edge-tts |

### Them/xoa goi khoi danh sach tu dong

Sua file `/opt/ai-packages.txt` trong Dockerfile:

```bash
# Sua Dockerfile tren may local
nano docker/Dockerfile
# Tim dong "RUN cat > /opt/ai-packages.txt" va them/xoa goi

# Rebuild
docker compose build
docker compose up -d

# Xoa marker de buoc cai lai
docker exec -it openclaw-gateway rm /opt/ai-persist/.ai-packages-installed
docker compose restart openclaw-gateway
```

### Co che hoat dong

```
docker compose up -d
         │
         ▼
   entrypoint.sh
         │
         ├── Set PYTHONPATH (detect python version)
         │
         ▼
   ai-pkg-setup kiem tra volume /opt/ai-persist/
         │
         ├── Co marker .ai-packages-installed?
         │   └── YES → SKIP (~2 giay)
         │   └── NO  → pip install --prefix 48 goi → luu vao volume
         │
         ▼
   Setup repos, config, plugins, doctor
         │
         ▼
   Exec: node /app/dist/index.js gateway --bind lan
```

| Thao tac | AI packages |
|----------|-------------|
| `docker compose restart` | Giu nguyen |
| `docker compose down` roi `up` | Giu nguyen |
| `docker compose build` roi `up` | Giu nguyen |
| `docker compose down -v` | MAT (xoa volume) → tu cai lai lan start tiep |

---

## XU LY LOI THUONG GAP

| Loi | Nguyen nhan | Cach sua |
|-----|-------------|----------|
| `unknown channel id: openzalo` | Plugin chua loaded | `docker compose restart openclaw-gateway` roi cho |
| `Config JSON bi loi` | openclaw.json hong | Entrypoint tu backup + tao moi, chi can restart |
| `PostgreSQL timeout` | DB chua san sang | `docker compose restart openclaw-gateway` |
| QR code het han | Quet cham | Chay lai lenh login (Buoc 10) |
| Gateway khong start | Xem logs | `docker compose logs openclaw-gateway` |
| Build qua lau | texlive-full ~5GB | Binh thuong lan dau, lan sau cache nhanh |
| AI packages cai lau | Lan dau ~10-15 phut | Binh thuong, lan sau skip (~2 giay). Xem: `docker compose logs openclaw-gateway \| grep ai-pkg` |
| AI packages mat sau down | Dung `down -v` xoa volume | Dung `docker compose down` (khong co `-v`) de giu volumes |
| Port 18789 da dung | Trung port | Sua port trong docker-compose.yml |
| `traefik-network not found` | Chua tao network | `docker network create traefik-network` hoac chay lai `init.sh` |
| `pip install loi` trong container | Khong dung helper | Dung `install-pip ten-goi` thay vi `pip3 install` |
| Python import loi AI package | Thieu PYTHONPATH | Restart container hoac chay `source /etc/profile.d/openclaw-path.sh` |
