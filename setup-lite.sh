#!/bin/bash
# PDFShift 轻量化部署一键安装脚本
# 适用于 Ubuntu 22.04 LTS
# 版本: 1.0

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  PDFShift 轻量化部署脚本 v1.0${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ 请使用 root 权限运行此脚本${NC}"
  echo "   使用命令: sudo bash setup-lite.sh"
  exit 1
fi

# 检查操作系统
if [ ! -f /etc/lsb-release ]; then
  echo -e "${RED}❌ 此脚本仅支持 Ubuntu 系统${NC}"
  exit 1
fi

echo -e "${YELLOW}📋 系统信息:${NC}"
cat /etc/lsb-release
echo ""

# 询问是否继续
read -p "是否继续安装? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "安装已取消"
  exit 0
fi

# ========== 1. 更新系统 ==========
echo -e "${GREEN}1. 更新系统包...${NC}"
apt update && apt upgrade -y

# ========== 2. 安装基础依赖 ==========
echo -e "${GREEN}2. 安装基础依赖...${NC}"
apt install -y \
    python3.10 \
    python3.10-venv \
    python3-pip \
    nginx \
    redis-server \
    sqlite3 \
    git \
    curl \
    wget \
    htop \
    apache2-utils \
    build-essential \
    software-properties-common

# ========== 3. 安装 PDF 处理工具 ==========
echo -e "${GREEN}3. 安装 PDF 处理工具...${NC}"
apt install -y \
    poppler-utils \
    ghostscript \
    imagemagick

# LibreOffice (可选，用于高质量转换)
read -p "是否安装 LibreOffice? (需要 ~500MB 空间) (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  apt install -y libreoffice --no-install-recommends
  echo -e "${GREEN}✅ LibreOffice 已安装${NC}"
else
  echo -e "${YELLOW}⚠️  跳过 LibreOffice 安装${NC}"
fi

# ========== 4. 创建目录结构 ==========
echo -e "${GREEN}4. 创建目录结构...${NC}"
mkdir -p /opt/pdfshift/{backend,frontend/dist,data,backups,logs,scripts,tmp}

# ========== 5. 创建 Python 虚拟环境 ==========
echo -e "${GREEN}5. 创建 Python 虚拟环境...${NC}"
python3.10 -m venv /opt/pdfshift/venv

# 升级 pip
/opt/pdfshift/venv/bin/pip install --upgrade pip setuptools wheel

# ========== 6. 配置环境变量 ==========
echo -e "${GREEN}6. 配置环境变量...${NC}"

if [ -f /opt/pdfshift/.env ]; then
  echo -e "${YELLOW}⚠️  .env 文件已存在，创建备份...${NC}"
  cp /opt/pdfshift/.env /opt/pdfshift/.env.backup.$(date +%Y%m%d_%H%M%S)
fi

cat > /opt/pdfshift/.env << 'EOF'
# 数据库配置
DATABASE_URL=sqlite:////opt/pdfshift/data/pdfshift.db

# Redis 配置
REDIS_URL=redis://localhost:6379/0

# OSS 配置 (阿里云对象存储)
OSS_ACCESS_KEY=LTAI5txxxxxxxxxxxxxx
OSS_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OSS_BUCKET=coreshift-storage
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

# JWT 密钥 (至少 32 个字符)
JWT_SECRET=your_random_secret_key_change_me_in_production_at_least_32_chars

# 管理员账号
ADMIN_USERNAME=admin
ADMIN_PASSWORD=Admin@2026!ChangeMe

# 支付配置 (支付宝)
ALIPAY_APP_ID=
ALIPAY_PRIVATE_KEY=
ALIPAY_PUBLIC_KEY=

# 微信支付配置
WECHAT_APP_ID=
WECHAT_MCH_ID=
WECHAT_API_KEY=

# 应用配置
APP_ENV=production
APP_DEBUG=false
EOF

chmod 600 /opt/pdfshift/.env

echo -e "${YELLOW}⚠️  重要: 请编辑 /opt/pdfshift/.env 修改配置！${NC}"
echo -e "   特别是: OSS_ACCESS_KEY, OSS_SECRET_KEY, JWT_SECRET, ADMIN_PASSWORD"
echo ""

# ========== 7. 初始化数据库 ==========
echo -e "${GREEN}7. 初始化数据库...${NC}"

if [ -f ./backend/init.sql ]; then
  sqlite3 /opt/pdfshift/data/pdfshift.db < ./backend/init.sql
  echo -e "${GREEN}✅ 数据库初始化成功${NC}"
else
  echo -e "${YELLOW}⚠️  未找到 init.sql，请手动初始化数据库${NC}"
  echo "   命令: sqlite3 /opt/pdfshift/data/pdfshift.db < /opt/pdfshift/backend/init.sql"
fi

# ========== 8. 设置权限 ==========
echo -e "${GREEN}8. 设置文件权限...${NC}"
chown -R www-data:www-data /opt/pdfshift
chmod 755 /opt/pdfshift
chmod 644 /opt/pdfshift/data/pdfshift.db

# ========== 9. 配置 Nginx ==========
echo -e "${GREEN}9. 配置 Nginx...${NC}"

# 创建管理员密码
echo -e "${YELLOW}请设置管理后台访问密码:${NC}"
htpasswd -c /opt/pdfshift/.htpasswd admin
chmod 644 /opt/pdfshift/.htpasswd

# Nginx 配置
cat > /etc/nginx/sites-available/pdfshift << 'EOF'
server {
    listen 80;
    server_name _;  # 替换为你的域名

    client_max_body_size 500M;
    client_body_timeout 300s;

    access_log /var/log/nginx/pdfshift_access.log;
    error_log /var/log/nginx/pdfshift_error.log;

    # 前端静态文件
    location / {
        root /opt/pdfshift/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # 管理后台
    location /admin/ {
        auth_basic "Admin Area";
        auth_basic_user_file /opt/pdfshift/.htpasswd;

        proxy_pass http://127.0.0.1:8000/admin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
EOF

# 启用站点
ln -sf /etc/nginx/sites-available/pdfshift /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 测试配置
nginx -t
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Nginx 配置成功${NC}"
else
  echo -e "${RED}❌ Nginx 配置错误${NC}"
  exit 1
fi

# ========== 10. 创建 Systemd 服务 ==========
echo -e "${GREEN}10. 创建 Systemd 服务...${NC}"

# FastAPI 服务
cat > /etc/systemd/system/pdfshift-api.service << 'EOF'
[Unit]
Description=PDFShift FastAPI Service
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/backend
Environment="PATH=/opt/pdfshift/venv/bin"
EnvironmentFile=/opt/pdfshift/.env
ExecStart=/opt/pdfshift/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 2

Restart=always
RestartSec=5

StandardOutput=append:/opt/pdfshift/logs/api.log
StandardError=append:/opt/pdfshift/logs/api.log

[Install]
WantedBy=multi-user.target
EOF

# Celery Worker
cat > /etc/systemd/system/pdfshift-worker.service << 'EOF'
[Unit]
Description=PDFShift Celery Worker
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/backend
Environment="PATH=/opt/pdfshift/venv/bin"
EnvironmentFile=/opt/pdfshift/.env
ExecStart=/opt/pdfshift/venv/bin/celery -A app.celery worker --loglevel=info --concurrency=2 --max-tasks-per-child=50

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/logs/worker.log
StandardError=append:/opt/pdfshift/logs/worker.log

[Install]
WantedBy=multi-user.target
EOF

# Celery Beat
cat > /etc/systemd/system/pdfshift-beat.service << 'EOF'
[Unit]
Description=PDFShift Celery Beat Scheduler
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/backend
Environment="PATH=/opt/pdfshift/venv/bin"
EnvironmentFile=/opt/pdfshift/.env
ExecStart=/opt/pdfshift/venv/bin/celery -A app.celery beat --loglevel=info --schedule=/opt/pdfshift/data/celerybeat-schedule.db

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/logs/celery-beat.log
StandardError=append:/opt/pdfshift/logs/celery-beat.log

[Install]
WantedBy=multi-user.target
EOF

# ========== 11. 创建备份脚本 ==========
echo -e "${GREEN}11. 创建备份脚本...${NC}"

cat > /opt/pdfshift/scripts/backup_db.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/pdfshift/backups"
DB_FILE="/opt/pdfshift/data/pdfshift.db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR
sqlite3 $DB_FILE ".backup '$BACKUP_DIR/pdfshift_$TIMESTAMP.db'"
gzip "$BACKUP_DIR/pdfshift_$TIMESTAMP.db"
find $BACKUP_DIR -name "pdfshift_*.db.gz" -mtime +7 -delete

echo "[$(date)] Database backup completed: pdfshift_$TIMESTAMP.db.gz"
EOF

chmod +x /opt/pdfshift/scripts/backup_db.sh

# 添加到 crontab
(crontab -l 2>/dev/null | grep -v backup_db.sh; echo "0 2 * * * /opt/pdfshift/scripts/backup_db.sh") | crontab -

# ========== 12. 重载配置并启动服务 ==========
echo -e "${GREEN}12. 启动服务...${NC}"

systemctl daemon-reload

# 启用服务
systemctl enable redis-server nginx
systemctl enable pdfshift-api pdfshift-worker pdfshift-beat

# 启动 Redis 和 Nginx
systemctl restart redis-server
systemctl reload nginx

echo -e "${YELLOW}⚠️  注意: PDFShift 服务尚未启动${NC}"
echo -e "   需要先部署代码和安装 Python 依赖"

# ========== 13. 显示摘要 ==========
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📋 下一步操作:${NC}"
echo ""
echo "1. 编辑配置文件:"
echo "   nano /opt/pdfshift/.env"
echo ""
echo "2. 部署代码:"
echo "   - 上传 backend/ 代码到 /opt/pdfshift/backend/"
echo "   - 上传 frontend/dist/ 到 /opt/pdfshift/frontend/dist/"
echo ""
echo "3. 安装 Python 依赖:"
echo "   sudo -u www-data /opt/pdfshift/venv/bin/pip install -r /opt/pdfshift/backend/requirements.txt"
echo ""
echo "4. 启动服务:"
echo "   sudo systemctl start pdfshift-api"
echo "   sudo systemctl start pdfshift-worker"
echo "   sudo systemctl start pdfshift-beat"
echo ""
echo "5. 检查状态:"
echo "   sudo systemctl status pdfshift-api"
echo "   curl http://localhost/health"
echo ""
echo "6. 查看日志:"
echo "   tail -f /opt/pdfshift/logs/api.log"
echo "   sudo journalctl -u pdfshift-api -f"
echo ""
echo -e "${GREEN}✅ 系统已准备就绪！${NC}"
echo ""
