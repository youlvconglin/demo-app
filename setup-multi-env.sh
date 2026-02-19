#!/bin/bash
# PDFShift 多环境部署初始化脚本
# 在单服务器上配置测试环境和生产环境

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  PDFShift 多环境部署初始化${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ 请使用 root 权限运行${NC}"
  exit 1
fi

# ========== 1. 安装基础依赖 ==========
echo -e "${GREEN}1. 安装基础依赖...${NC}"
apt update && apt upgrade -y
apt install -y python3.10 python3.10-venv python3-pip nginx redis-server sqlite3 \
    git curl htop apache2-utils poppler-utils ghostscript

# ========== 2. 创建目录结构 ==========
echo -e "${GREEN}2. 创建目录结构...${NC}"

# 测试环境
mkdir -p /opt/pdfshift/staging/{backend,frontend/dist,data,logs,backups,tmp}
mkdir -p /opt/pdfshift/staging/venv

# 生产环境
mkdir -p /opt/pdfshift/production/{backend,frontend/dist,data,logs,backups,tmp}
mkdir -p /opt/pdfshift/production/venv

# 共享目录
mkdir -p /opt/pdfshift/shared/{scripts,backups}

echo "✅ 目录结构创建完成"

# ========== 3. 创建虚拟环境 ==========
echo -e "${GREEN}3. 创建 Python 虚拟环境...${NC}"

echo "  - 测试环境..."
python3.10 -m venv /opt/pdfshift/staging/venv
/opt/pdfshift/staging/venv/bin/pip install --upgrade pip setuptools wheel --quiet

echo "  - 生产环境..."
python3.10 -m venv /opt/pdfshift/production/venv
/opt/pdfshift/production/venv/bin/pip install --upgrade pip setuptools wheel --quiet

echo "✅ 虚拟环境创建完成"

# ========== 4. 配置环境变量 ==========
echo -e "${GREEN}4. 配置环境变量...${NC}"

# 测试环境 .env
cat > /opt/pdfshift/staging/.env << 'EOF'
# 测试环境配置
APP_ENV=staging
APP_DEBUG=true

DATABASE_URL=sqlite:////opt/pdfshift/staging/data/staging.db
REDIS_URL=redis://localhost:6379/1

OSS_ACCESS_KEY=your_access_key
OSS_SECRET_KEY=your_secret_key
OSS_BUCKET=coreshift-staging
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

JWT_SECRET=staging_test_secret_key_change_me

ADMIN_USERNAME=admin
ADMIN_PASSWORD=Staging@2026!

API_PORT=8001
EOF

# 生产环境 .env
cat > /opt/pdfshift/production/.env << 'EOF'
# 生产环境配置
APP_ENV=production
APP_DEBUG=false

DATABASE_URL=sqlite:////opt/pdfshift/production/data/production.db
REDIS_URL=redis://localhost:6379/0

OSS_ACCESS_KEY=your_access_key
OSS_SECRET_KEY=your_secret_key
OSS_BUCKET=coreshift-production
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

JWT_SECRET=production_super_strong_secret_min_32_chars

ADMIN_USERNAME=admin
ADMIN_PASSWORD=Production@2026!Strong

API_PORT=8000
EOF

chmod 600 /opt/pdfshift/staging/.env
chmod 600 /opt/pdfshift/production/.env

echo "✅ 环境变量配置完成"
echo -e "${YELLOW}⚠️  请编辑 .env 文件修改敏感信息！${NC}"

# ========== 5. 初始化数据库 ==========
echo -e "${GREEN}5. 初始化数据库...${NC}"

if [ -f ./backend/init.sql ]; then
  sqlite3 /opt/pdfshift/staging/data/staging.db < ./backend/init.sql
  sqlite3 /opt/pdfshift/production/data/production.db < ./backend/init.sql
  echo "✅ 数据库初始化完成"
else
  echo -e "${YELLOW}⚠️  未找到 init.sql，请手动初始化${NC}"
fi

# ========== 6. 设置权限 ==========
echo -e "${GREEN}6. 设置文件权限...${NC}"
chown -R www-data:www-data /opt/pdfshift
echo "✅ 权限设置完成"

# ========== 7. 创建管理员密码 ==========
echo -e "${GREEN}7. 创建管理员密码...${NC}"

echo -e "${YELLOW}测试环境管理后台密码:${NC}"
htpasswd -c /opt/pdfshift/staging/.htpasswd admin

echo ""
echo -e "${YELLOW}生产环境管理后台密码:${NC}"
htpasswd -c /opt/pdfshift/production/.htpasswd admin

chmod 644 /opt/pdfshift/staging/.htpasswd
chmod 644 /opt/pdfshift/production/.htpasswd

# ========== 8. 配置 Nginx ==========
echo -e "${GREEN}8. 配置 Nginx...${NC}"

cat > /etc/nginx/sites-available/pdfshift-multi << 'NGINX_EOF'
# 测试环境
server {
    listen 80;
    server_name test.coreshift.cn;

    client_max_body_size 500M;

    access_log /var/log/nginx/staging_access.log;
    error_log /var/log/nginx/staging_error.log;

    location / {
        root /opt/pdfshift/staging/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /admin/ {
        auth_basic "Staging Admin";
        auth_basic_user_file /opt/pdfshift/staging/.htpasswd;

        proxy_pass http://127.0.0.1:8001/admin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /health {
        proxy_pass http://127.0.0.1:8001/health;
        access_log off;
    }
}

# 生产环境
server {
    listen 80;
    server_name coreshift.cn www.coreshift.cn;

    client_max_body_size 500M;

    access_log /var/log/nginx/production_access.log;
    error_log /var/log/nginx/production_error.log;

    location / {
        root /opt/pdfshift/production/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /admin/ {
        auth_basic "Production Admin";
        auth_basic_user_file /opt/pdfshift/production/.htpasswd;

        proxy_pass http://127.0.0.1:8000/admin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/pdfshift-multi /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && echo "✅ Nginx 配置成功"

# ========== 9. 创建 Systemd 服务 ==========
echo -e "${GREEN}9. 创建 Systemd 服务...${NC}"

# 测试环境 API
cat > /etc/systemd/system/pdfshift-staging-api.service << 'SERVICE_EOF'
[Unit]
Description=PDFShift Staging API
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/staging/backend
Environment="PATH=/opt/pdfshift/staging/venv/bin"
EnvironmentFile=/opt/pdfshift/staging/.env
ExecStart=/opt/pdfshift/staging/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8001 --workers 1

Restart=always
RestartSec=5

StandardOutput=append:/opt/pdfshift/staging/logs/api.log
StandardError=append:/opt/pdfshift/staging/logs/api.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 测试环境 Worker
cat > /etc/systemd/system/pdfshift-staging-worker.service << 'SERVICE_EOF'
[Unit]
Description=PDFShift Staging Worker
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/staging/backend
Environment="PATH=/opt/pdfshift/staging/venv/bin"
EnvironmentFile=/opt/pdfshift/staging/.env
ExecStart=/opt/pdfshift/staging/venv/bin/celery -A app.celery worker --loglevel=info --concurrency=1

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/staging/logs/worker.log
StandardError=append:/opt/pdfshift/staging/logs/worker.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 生产环境 API
cat > /etc/systemd/system/pdfshift-production-api.service << 'SERVICE_EOF'
[Unit]
Description=PDFShift Production API
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/production/backend
Environment="PATH=/opt/pdfshift/production/venv/bin"
EnvironmentFile=/opt/pdfshift/production/.env
ExecStart=/opt/pdfshift/production/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 2

Restart=always
RestartSec=5

StandardOutput=append:/opt/pdfshift/production/logs/api.log
StandardError=append:/opt/pdfshift/production/logs/api.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 生产环境 Worker
cat > /etc/systemd/system/pdfshift-production-worker.service << 'SERVICE_EOF'
[Unit]
Description=PDFShift Production Worker
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/production/backend
Environment="PATH=/opt/pdfshift/production/venv/bin"
EnvironmentFile=/opt/pdfshift/production/.env
ExecStart=/opt/pdfshift/production/venv/bin/celery -A app.celery worker --loglevel=info --concurrency=2

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/production/logs/worker.log
StandardError=append:/opt/pdfshift/production/logs/worker.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "✅ Systemd 服务创建完成"

# ========== 10. 重载配置 ==========
systemctl daemon-reload
systemctl enable redis-server nginx
systemctl enable pdfshift-staging-api pdfshift-staging-worker
systemctl enable pdfshift-production-api pdfshift-production-worker

systemctl restart redis-server
systemctl reload nginx

# ========== 完成 ==========
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  多环境初始化完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📋 环境配置:${NC}"
echo "  测试环境: test.coreshift.cn  (端口 8001)"
echo "  生产环境: coreshift.cn       (端口 8000)"
echo ""
echo -e "${YELLOW}📋 下一步操作:${NC}"
echo "1. 编辑配置文件:"
echo "   nano /opt/pdfshift/staging/.env"
echo "   nano /opt/pdfshift/production/.env"
echo ""
echo "2. 配置域名解析:"
echo "   test.coreshift.cn → $(curl -s ifconfig.me)"
echo "   coreshift.cn      → $(curl -s ifconfig.me)"
echo ""
echo "3. 部署代码（使用 GitHub Actions）:"
echo "   git push origin develop   # 部署到测试环境"
echo "   git push origin main      # 部署到生产环境"
echo ""
echo "4. 手动启动服务（如需要）:"
echo "   sudo systemctl start pdfshift-staging-api"
echo "   sudo systemctl start pdfshift-production-api"
echo ""
echo "5. 查看服务状态:"
echo "   sudo systemctl status pdfshift-staging-api"
echo "   sudo systemctl status pdfshift-production-api"
echo ""
echo -e "${GREEN}✅ 系统已准备就绪！${NC}"
