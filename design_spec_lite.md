# PDFShift 轻量化部署方案 (Lite Deployment)

**版本**: 2.0
**日期**: 2026-02-19
**状态**: 推荐方案

---

## 1. 架构调整说明

### 1.1 变更内容

| 组件 | 原方案 | 新方案 | 理由 |
|------|--------|--------|------|
| **数据库** | MySQL (Docker) | SQLite | 轻量级，无需额外进程，适合中小流量 |
| **部署方式** | Docker Compose | Systemd 服务 | 减少 Docker 镜像占用，节省磁盘空间 |
| **Redis** | Docker 容器 | 直接安装 | 减少 Docker 开销 |
| **Nginx** | Docker 容器 | 直接安装 | 系统包管理更简单 |

**磁盘占用对比**：
- Docker 方案：~5GB (镜像 + 数据卷)
- 轻量化方案：~500MB (代码 + SQLite + 依赖)

### 1.2 架构图

```
┌─────────────────────────────────────────────────┐
│              阿里云 ECS (单服务器)                │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  Nginx (systemctl)                       │  │
│  │  - 前端: /usr/share/nginx/html           │  │
│  │  - API: proxy_pass → localhost:8000      │  │
│  │  - Admin: /admin + 认证                  │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  ┌────────────┐  ┌─────────────┐  ┌────────┐  │
│  │  FastAPI   │  │   Celery    │  │ Redis  │  │
│  │ (Uvicorn)  │◄─┤   Worker    │◄─┤(系统服务)│ │
│  │ (systemd)  │  │  (systemd)  │  └────────┘  │
│  └────────────┘  └─────────────┘               │
│         │               │                       │
│         └───────┬───────┘                       │
│                 ▼                               │
│         ┌──────────────┐                        │
│         │   SQLite     │                        │
│         │ (文件数据库)  │                        │
│         └──────────────┘                        │
└─────────────────────────────────────────────────┘
                  │
                  ▼
         ┌─────────────────┐
         │   阿里云 OSS     │
         │  (文件存储)      │
         └─────────────────┘
```

---

## 2. 硬件配置调整

### 2.1 ECS 服务器配置

| 组件 | 推荐配置 | 说明 |
|------|---------|------|
| **ECS 规格** | 2 vCPU / 4GB RAM | 比 Docker 方案节省 4GB 内存 |
| **系统盘** | 40GB SSD | 无需数据盘，系统盘足够 |
| **带宽** | 3 Mbps (按流量) | 主要流量走 OSS |
| **操作系统** | Ubuntu 22.04 LTS | 稳定、软件包丰富 |

**成本估算**（阿里云华北区）：
- ECS: ¥70/月
- OSS 存储: ¥2/月 (20GB)
- 流量: ¥15/月 (100GB)
- **总计**: ~¥87/月

---

## 3. 数据库设计 (SQLite)

### 3.1 SQLite 配置

**数据库文件路径**: `/opt/pdfshift/data/pdfshift.db`

**SQLite 优化配置**:
```python
# backend/app/database.py
import sqlite3

# 连接配置
conn = sqlite3.connect(
    '/opt/pdfshift/data/pdfshift.db',
    check_same_thread=False,  # 允许多线程访问
    timeout=30.0              # 写锁超时 30 秒
)

# 性能优化
conn.execute("PRAGMA journal_mode=WAL")        # 启用 WAL 模式，提升并发性能
conn.execute("PRAGMA synchronous=NORMAL")      # 平衡性能与安全
conn.execute("PRAGMA cache_size=-64000")       # 设置缓存大小 64MB
conn.execute("PRAGMA temp_store=MEMORY")       # 临时表存储在内存
```

### 3.2 表结构 (兼容 SQLite)

```sql
-- 任务表
CREATE TABLE tasks (
    task_id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    oss_key_source TEXT,
    oss_key_result TEXT,
    task_type TEXT CHECK(task_type IN ('pdf2word', 'pdf2excel', 'pdf2ppt', 'merge', 'split')),
    status TEXT CHECK(status IN ('pending', 'processing', 'completed', 'failed', 'expired')) DEFAULT 'pending',
    is_paid INTEGER DEFAULT 0,  -- SQLite 使用 INTEGER 代替 BOOLEAN (0=false, 1=true)
    error_msg TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    expire_at DATETIME
);

CREATE INDEX idx_client ON tasks(client_id);
CREATE INDEX idx_expire ON tasks(expire_at);
CREATE INDEX idx_status ON tasks(status, created_at);

-- 订单表
CREATE TABLE orders (
    order_id TEXT PRIMARY KEY,
    client_id TEXT,
    task_id TEXT,
    amount REAL,  -- SQLite 使用 REAL 代替 DECIMAL
    status TEXT CHECK(status IN ('unpaid', 'paid', 'refunded')) DEFAULT 'unpaid',
    payment_time DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_order_client ON orders(client_id);
CREATE INDEX idx_order_status ON orders(status);

-- 系统配置表
CREATE TABLE system_configs (
    config_key TEXT PRIMARY KEY,
    config_value TEXT,
    description TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 预设配置数据
INSERT INTO system_configs (config_key, config_value, description) VALUES
    ('retention_free_hours', '1', '免费文件保留小时数'),
    ('retention_paid_hours', '24', '付费文件保留小时数'),
    ('price_large_file', '5.00', '大文件解锁价格'),
    ('daily_free_quota_gb', '100', '每日免费流量限额(GB)');

-- 管理员用户表
CREATE TABLE admin_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME,
    is_active INTEGER DEFAULT 1
);

-- 管理员操作日志表
CREATE TABLE admin_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_username TEXT NOT NULL,
    action TEXT NOT NULL,
    target_table TEXT,
    target_id TEXT,
    old_value TEXT,
    new_value TEXT,
    ip_address TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_admin_logs ON admin_logs(admin_username, created_at);
```

### 3.3 数据库备份

```bash
#!/bin/bash
# /opt/pdfshift/scripts/backup_db.sh

BACKUP_DIR="/opt/pdfshift/backups"
DB_FILE="/opt/pdfshift/data/pdfshift.db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 使用 SQLite 的在线备份功能
sqlite3 $DB_FILE ".backup '$BACKUP_DIR/pdfshift_$TIMESTAMP.db'"

# 压缩备份
gzip "$BACKUP_DIR/pdfshift_$TIMESTAMP.db"

# 删除 7 天前的备份
find $BACKUP_DIR -name "pdfshift_*.db.gz" -mtime +7 -delete

echo "Database backup completed: pdfshift_$TIMESTAMP.db.gz"
```

**定时备份** (crontab):
```bash
# 每天凌晨 2 点备份
0 2 * * * /opt/pdfshift/scripts/backup_db.sh
```

---

## 4. 服务部署配置

### 4.1 目录结构

```
/opt/pdfshift/
├── backend/               # Python 后端代码
│   ├── app/
│   │   ├── main.py       # FastAPI 应用
│   │   ├── celery.py     # Celery 配置
│   │   ├── database.py   # SQLite 连接
│   │   ├── models.py     # 数据模型
│   │   └── ...
│   ├── requirements.txt  # Python 依赖
│   └── init.sql          # 数据库初始化脚本
├── frontend/
│   └── dist/             # 前端构建产物
├── data/
│   └── pdfshift.db       # SQLite 数据库文件
├── backups/              # 数据库备份
├── logs/                 # 应用日志
│   ├── api.log
│   ├── worker.log
│   └── celery-beat.log
├── scripts/              # 运维脚本
│   ├── backup_db.sh
│   └── cleanup.sh
├── .env                  # 环境变量
└── venv/                 # Python 虚拟环境
```

### 4.2 系统依赖安装

```bash
#!/bin/bash
# 在 ECS 服务器上执行

# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础工具
sudo apt install -y \
    python3.10 \
    python3.10-venv \
    python3-pip \
    nginx \
    redis-server \
    sqlite3 \
    git \
    curl \
    htop

# 安装 PDF 处理依赖
sudo apt install -y \
    poppler-utils \
    libreoffice \
    ghostscript

# 启动 Redis
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### 4.3 Systemd 服务配置

#### FastAPI 服务

创建 `/etc/systemd/system/pdfshift-api.service`:

```ini
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
ExecStart=/opt/pdfshift/venv/bin/uvicorn app.main:app \
    --host 127.0.0.1 \
    --port 8000 \
    --workers 2 \
    --log-config logging.yml

Restart=always
RestartSec=5

# 日志
StandardOutput=append:/opt/pdfshift/logs/api.log
StandardError=append:/opt/pdfshift/logs/api.log

[Install]
WantedBy=multi-user.target
```

#### Celery Worker 服务

创建 `/etc/systemd/system/pdfshift-worker.service`:

```ini
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
ExecStart=/opt/pdfshift/venv/bin/celery -A app.celery worker \
    --loglevel=info \
    --concurrency=2 \
    --max-tasks-per-child=50

Restart=always
RestartSec=10

# 日志
StandardOutput=append:/opt/pdfshift/logs/worker.log
StandardError=append:/opt/pdfshift/logs/worker.log

[Install]
WantedBy=multi-user.target
```

#### Celery Beat 服务

创建 `/etc/systemd/system/pdfshift-beat.service`:

```ini
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
ExecStart=/opt/pdfshift/venv/bin/celery -A app.celery beat \
    --loglevel=info \
    --schedule=/opt/pdfshift/data/celerybeat-schedule.db

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/logs/celery-beat.log
StandardError=append:/opt/pdfshift/logs/celery-beat.log

[Install]
WantedBy=multi-user.target
```

### 4.4 启动服务

```bash
# 重载 systemd 配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl enable pdfshift-api
sudo systemctl enable pdfshift-worker
sudo systemctl enable pdfshift-beat

sudo systemctl start pdfshift-api
sudo systemctl start pdfshift-worker
sudo systemctl start pdfshift-beat

# 检查状态
sudo systemctl status pdfshift-api
sudo systemctl status pdfshift-worker
sudo systemctl status pdfshift-beat
```

---

## 5. Nginx 配置

创建 `/etc/nginx/sites-available/pdfshift`:

```nginx
server {
    listen 80;
    server_name pdfshift.com www.pdfshift.com;  # 替换为你的域名

    client_max_body_size 500M;
    client_body_timeout 300s;

    # 访问日志
    access_log /var/log/nginx/pdfshift_access.log;
    error_log /var/log/nginx/pdfshift_error.log;

    # 前端静态文件
    location / {
        root /opt/pdfshift/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;

        # 静态资源缓存
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

        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # 管理后台（基础认证）
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
```

启用站点：
```bash
sudo ln -s /etc/nginx/sites-available/pdfshift /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 6. GitHub Actions CI/CD (轻量化)

创建 `.github/workflows/deploy-lite.yml`:

```yaml
name: Deploy PDFShift (Lite)

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  DEPLOY_PATH: /opt/pdfshift

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - name: Build frontend
        run: |
          cd frontend
          npm ci --legacy-peer-deps
          npm run build
          echo "✅ Frontend build completed"

      - name: Package deployment files
        run: |
          mkdir -p deploy_package
          cp -r frontend/dist deploy_package/
          cp -r backend deploy_package/
          tar -czf deploy.tar.gz deploy_package/
          echo "✅ Package created: $(du -h deploy.tar.gz | cut -f1)"

      - name: Upload to ECS
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.ECS_HOST }}
          username: ${{ secrets.ECS_USERNAME }}
          key: ${{ secrets.ECS_SSH_KEY }}
          port: 22
          source: "deploy.tar.gz"
          target: "/tmp"

      - name: Deploy to server
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.ECS_HOST }}
          username: ${{ secrets.ECS_USERNAME }}
          key: ${{ secrets.ECS_SSH_KEY }}
          port: 22
          script: |
            set -e

            echo "========== 开始部署 =========="

            # 解压文件
            cd /tmp
            tar -xzf deploy.tar.gz

            # 备份数据库
            if [ -f "${{ env.DEPLOY_PATH }}/data/pdfshift.db" ]; then
              sudo cp ${{ env.DEPLOY_PATH }}/data/pdfshift.db \
                   ${{ env.DEPLOY_PATH }}/backups/pdfshift.db.$(date +%Y%m%d_%H%M%S)
              echo "✅ Database backed up"
            fi

            # 停止服务
            echo "========== 停止服务 =========="
            sudo systemctl stop pdfshift-api || true
            sudo systemctl stop pdfshift-worker || true
            sudo systemctl stop pdfshift-beat || true

            # 更新代码
            echo "========== 更新代码 =========="
            sudo cp -r /tmp/deploy_package/backend/* ${{ env.DEPLOY_PATH }}/backend/
            sudo cp -r /tmp/deploy_package/dist/* ${{ env.DEPLOY_PATH }}/frontend/dist/

            # 更新 Python 依赖
            echo "========== 更新依赖 =========="
            cd ${{ env.DEPLOY_PATH }}/backend
            sudo -u www-data ${{ env.DEPLOY_PATH }}/venv/bin/pip install -r requirements.txt --upgrade

            # 数据库迁移（如有需要）
            # sudo -u www-data ${{ env.DEPLOY_PATH }}/venv/bin/python migrate.py

            # 启动服务
            echo "========== 启动服务 =========="
            sudo systemctl start pdfshift-api
            sudo systemctl start pdfshift-worker
            sudo systemctl start pdfshift-beat

            # 等待服务启动
            sleep 5

            # 检查服务状态
            echo "========== 检查服务状态 =========="
            sudo systemctl is-active pdfshift-api
            sudo systemctl is-active pdfshift-worker
            sudo systemctl is-active pdfshift-beat

            # 健康检查
            echo "========== 健康检查 =========="
            if curl -f http://localhost/health > /dev/null 2>&1; then
              echo "✅ 健康检查通过"
            else
              echo "❌ 健康检查失败"
              sudo systemctl status pdfshift-api
              sudo journalctl -u pdfshift-api -n 50
              exit 1
            fi

            # 清理临时文件
            rm -rf /tmp/deploy.tar.gz /tmp/deploy_package

            echo "========== 部署完成 =========="
            echo "部署时间: $(date)"
```

---

## 7. 初次部署脚本

创建一键部署脚本 `setup.sh`:

```bash
#!/bin/bash
# 在 ECS 服务器上运行此脚本进行初次部署

set -e

echo "========== PDFShift 初次部署脚本 =========="

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本: sudo bash setup.sh"
  exit 1
fi

# 1. 安装系统依赖
echo "1. 安装系统依赖..."
apt update && apt upgrade -y
apt install -y python3.10 python3.10-venv python3-pip nginx redis-server sqlite3 git curl htop
apt install -y poppler-utils libreoffice ghostscript apache2-utils

# 2. 创建目录结构
echo "2. 创建目录结构..."
mkdir -p /opt/pdfshift/{backend,frontend/dist,data,backups,logs,scripts}
chown -R www-data:www-data /opt/pdfshift

# 3. 创建 Python 虚拟环境
echo "3. 创建 Python 虚拟环境..."
sudo -u www-data python3.10 -m venv /opt/pdfshift/venv

# 4. 配置环境变量
echo "4. 配置环境变量..."
cat > /opt/pdfshift/.env << 'EOF'
# 数据库
DATABASE_URL=sqlite:////opt/pdfshift/data/pdfshift.db

# Redis
REDIS_URL=redis://localhost:6379/0

# OSS 配置
OSS_ACCESS_KEY=your_access_key_here
OSS_SECRET_KEY=your_secret_key_here
OSS_BUCKET=pdfshift-storage
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

# JWT
JWT_SECRET=your_random_secret_key_min_32_characters

# 管理员账号
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your_strong_password_here

# 支付配置
ALIPAY_APP_ID=
ALIPAY_PRIVATE_KEY=
WECHAT_APP_ID=
EOF

chmod 600 /opt/pdfshift/.env
chown www-data:www-data /opt/pdfshift/.env

echo "⚠️  请编辑 /opt/pdfshift/.env 填入真实配置！"

# 5. 初始化数据库
echo "5. 初始化数据库..."
# 这里需要你的 init.sql 脚本
# sqlite3 /opt/pdfshift/data/pdfshift.db < /opt/pdfshift/backend/init.sql
# chown www-data:www-data /opt/pdfshift/data/pdfshift.db

# 6. 创建 Nginx 密码文件
echo "6. 创建管理员密码..."
echo "请输入管理后台密码:"
htpasswd -c /opt/pdfshift/.htpasswd admin
chmod 644 /opt/pdfshift/.htpasswd

# 7. 配置 Nginx
echo "7. 配置 Nginx..."
# 将前面的 Nginx 配置写入 /etc/nginx/sites-available/pdfshift
ln -sf /etc/nginx/sites-available/pdfshift /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 8. 配置 Systemd 服务
echo "8. 配置 Systemd 服务..."
# 将前面的三个 .service 文件写入 /etc/systemd/system/

systemctl daemon-reload
systemctl enable redis-server nginx
systemctl enable pdfshift-api pdfshift-worker pdfshift-beat

# 9. 配置定时任务
echo "9. 配置定时备份..."
cat > /opt/pdfshift/scripts/backup_db.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/pdfshift/backups"
DB_FILE="/opt/pdfshift/data/pdfshift.db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR
sqlite3 $DB_FILE ".backup '$BACKUP_DIR/pdfshift_$TIMESTAMP.db'"
gzip "$BACKUP_DIR/pdfshift_$TIMESTAMP.db"
find $BACKUP_DIR -name "pdfshift_*.db.gz" -mtime +7 -delete
echo "Backup completed: pdfshift_$TIMESTAMP.db.gz"
EOF

chmod +x /opt/pdfshift/scripts/backup_db.sh

# 添加到 crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/pdfshift/scripts/backup_db.sh") | crontab -

echo ""
echo "========== 部署完成 =========="
echo ""
echo "下一步操作:"
echo "1. 编辑配置文件: nano /opt/pdfshift/.env"
echo "2. 上传后端代码到 /opt/pdfshift/backend/"
echo "3. 安装 Python 依赖: sudo -u www-data /opt/pdfshift/venv/bin/pip install -r /opt/pdfshift/backend/requirements.txt"
echo "4. 初始化数据库: sqlite3 /opt/pdfshift/data/pdfshift.db < /opt/pdfshift/backend/init.sql"
echo "5. 启动服务: sudo systemctl start pdfshift-api pdfshift-worker pdfshift-beat"
echo "6. 查看日志: sudo journalctl -u pdfshift-api -f"
echo ""
```

---

## 8. 运维命令

### 8.1 服务管理

```bash
# 查看服务状态
sudo systemctl status pdfshift-api
sudo systemctl status pdfshift-worker
sudo systemctl status pdfshift-beat

# 重启服务
sudo systemctl restart pdfshift-api
sudo systemctl restart pdfshift-worker
sudo systemctl restart pdfshift-beat

# 查看日志
sudo journalctl -u pdfshift-api -f --lines=100
sudo journalctl -u pdfshift-worker -f --lines=100

# 或查看日志文件
tail -f /opt/pdfshift/logs/api.log
tail -f /opt/pdfshift/logs/worker.log
```

### 8.2 数据库管理

```bash
# 进入 SQLite
sqlite3 /opt/pdfshift/data/pdfshift.db

# 常用查询
SELECT COUNT(*) FROM tasks;
SELECT * FROM tasks WHERE status='failed' LIMIT 10;
SELECT * FROM system_configs;

# 手动备份
/opt/pdfshift/scripts/backup_db.sh

# 恢复备份
gunzip /opt/pdfshift/backups/pdfshift_20260219_120000.db.gz
cp /opt/pdfshift/backups/pdfshift_20260219_120000.db /opt/pdfshift/data/pdfshift.db
sudo systemctl restart pdfshift-api pdfshift-worker
```

### 8.3 性能监控

```bash
# 系统资源
htop

# 磁盘使用
df -h
du -sh /opt/pdfshift/*

# 数据库大小
ls -lh /opt/pdfshift/data/pdfshift.db

# Redis 状态
redis-cli INFO stats
redis-cli LLEN celery  # 查看任务队列长度

# Nginx 日志分析
tail -f /var/log/nginx/pdfshift_access.log
```

---

## 9. 优势与限制

### 9.1 优势

| 项目 | 优势 |
|------|------|
| **磁盘占用** | ~500MB vs Docker 的 ~5GB |
| **内存占用** | ~1.5GB vs Docker 的 ~3GB |
| **启动速度** | 秒级启动 vs Docker 的十几秒 |
| **运维简单** | 标准 Linux 服务管理 |
| **成本** | ECS 可选更低配置（2C4G） |

### 9.2 限制与注意事项

| 限制 | 说明 | 应对方案 |
|------|------|---------|
| **并发写入** | SQLite 不支持高并发写 | 当前流量（1000 PV/月）完全够用 |
| **扩展性** | 单机部署，无法水平扩展 | 流量增长后可迁移到 MySQL |
| **数据库备份** | 需要定时备份 | 已配置自动备份脚本 |

**升级路径**：
- 当流量达到 **10,000 PV/月** 时，考虑迁移到 MySQL。
- 数据迁移工具：`sqlite3 pdfshift.db .dump | mysql -u root -p pdfshift`

---

## 10. 性能测试

### 10.1 压力测试

使用 `ab` (ApacheBench) 测试：

```bash
# 测试 API 响应
ab -n 1000 -c 10 http://your-ecs-ip/health

# 测试文件上传
ab -n 100 -c 5 -p test.pdf -T application/pdf http://your-ecs-ip/api/v1/tasks
```

**预期性能**（2C4G ECS）：
- API 响应时间: P95 < 200ms
- 并发处理能力: 50 req/s
- PDF 转换: 50MB 文件 < 30 秒

---

**轻量化部署方案完成**。相比 Docker 方案节省 90% 磁盘空间和 50% 内存占用，适合初期部署。
