# PDFShift 多环境部署方案

**版本**: 1.0
**日期**: 2026-02-19

---

## 1. 环境规划

### 1.1 环境定义

| 环境 | 用途 | 分支 | 域名示例 | 服务器 |
|------|------|------|---------|--------|
| **测试环境 (Staging)** | 功能测试、集成测试 | `develop` | test.pdfshift.com | 可与生产共用或独立 |
| **生产环境 (Production)** | 正式对外服务 | `main` | pdfshift.com | 独立 ECS |

### 1.2 部署策略

**方案 A: 单服务器双环境**（成本最低）
```
┌─────────────────────────────────────────┐
│           ECS (2C4G)                    │
│  ┌──────────────────────────────────┐  │
│  │ Nginx                            │  │
│  │ - test.pdfshift.com → :8001      │  │
│  │ - pdfshift.com      → :8000      │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌────────────┐  ┌─────────────────┐  │
│  │ Staging    │  │  Production     │  │
│  │ API :8001  │  │  API :8000      │  │
│  │ Worker x1  │  │  Worker x2      │  │
│  │ Redis DB1  │  │  Redis DB0      │  │
│  │ staging.db │  │  production.db  │  │
│  └────────────┘  └─────────────────┘  │
└─────────────────────────────────────────┘
```

**方案 B: 双服务器（推荐生产使用）**
```
┌─────────────────┐       ┌──────────────────┐
│  测试服务器      │       │   生产服务器      │
│  (1C2G 轻量)    │       │   (2C4G 标准)    │
│  test.pdfshift  │       │   pdfshift.com   │
└─────────────────┘       └──────────────────┘
```

---

## 2. 单服务器双环境配置

### 2.1 目录结构

```
/opt/pdfshift/
├── staging/                  # 测试环境
│   ├── backend/
│   ├── frontend/dist/
│   ├── data/
│   │   └── staging.db        # 测试数据库
│   ├── logs/
│   ├── .env                  # 测试环境变量
│   └── venv/                 # Python 虚拟环境
│
├── production/               # 生产环境
│   ├── backend/
│   ├── frontend/dist/
│   ├── data/
│   │   └── production.db     # 生产数据库
│   ├── logs/
│   ├── .env                  # 生产环境变量
│   └── venv/
│
└── shared/                   # 共享资源
    ├── backups/
    └── scripts/
```

### 2.2 环境变量配置

#### 测试环境 `/opt/pdfshift/staging/.env`

```bash
# 环境标识
APP_ENV=staging
APP_DEBUG=true

# 数据库
DATABASE_URL=sqlite:////opt/pdfshift/staging/data/staging.db

# Redis (使用不同的 DB)
REDIS_URL=redis://localhost:6379/1

# OSS (使用测试 Bucket)
OSS_BUCKET=pdfshift-staging
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

# JWT (测试密钥)
JWT_SECRET=staging_test_secret_key_for_development

# 管理员
ADMIN_USERNAME=admin
ADMIN_PASSWORD=Test@2026!

# API 端口
API_PORT=8001

# 其他配置（可选择性放宽限制）
MAX_FILE_SIZE_MB=500
FREE_FILE_SIZE_MB=100  # 测试环境可以更大
```

#### 生产环境 `/opt/pdfshift/production/.env`

```bash
# 环境标识
APP_ENV=production
APP_DEBUG=false

# 数据库
DATABASE_URL=sqlite:////opt/pdfshift/production/data/production.db

# Redis
REDIS_URL=redis://localhost:6379/0

# OSS (生产 Bucket)
OSS_BUCKET=pdfshift-production
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

# JWT (强密钥)
JWT_SECRET=production_super_strong_secret_key_min_32_chars_random

# 管理员
ADMIN_USERNAME=admin
ADMIN_PASSWORD=Production@2026!VeryStrong

# API 端口
API_PORT=8000

# 生产配置
MAX_FILE_SIZE_MB=500
FREE_FILE_SIZE_MB=50
```

### 2.3 Systemd 服务配置

创建独立的服务文件：

#### 测试环境服务

`/etc/systemd/system/pdfshift-staging-api.service`:
```ini
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
```

`/etc/systemd/system/pdfshift-staging-worker.service`:
```ini
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
```

#### 生产环境服务

`/etc/systemd/system/pdfshift-production-api.service`:
```ini
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
```

`/etc/systemd/system/pdfshift-production-worker.service`:
```ini
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
```

### 2.4 Nginx 配置（多环境）

`/etc/nginx/sites-available/pdfshift-multi`:

```nginx
# ========== 测试环境 ==========
server {
    listen 80;
    server_name test.pdfshift.com;

    client_max_body_size 500M;

    access_log /var/log/nginx/staging_access.log;
    error_log /var/log/nginx/staging_error.log;

    # 前端静态文件
    location / {
        root /opt/pdfshift/staging/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    # API 代理到 8001 端口
    location /api/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Environment staging;  # 环境标识头
    }

    # 管理后台
    location /admin/ {
        auth_basic "Staging Admin";
        auth_basic_user_file /opt/pdfshift/staging/.htpasswd;

        proxy_pass http://127.0.0.1:8001/admin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 健康检查
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:8001/health;
    }
}

# ========== 生产环境 ==========
server {
    listen 80;
    server_name pdfshift.com www.pdfshift.com;

    client_max_body_size 500M;

    access_log /var/log/nginx/production_access.log;
    error_log /var/log/nginx/production_error.log;

    # 前端静态文件
    location / {
        root /opt/pdfshift/production/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;

        # 静态资源缓存
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # API 代理到 8000 端口
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Environment production;
    }

    # 管理后台
    location /admin/ {
        auth_basic "Production Admin";
        auth_basic_user_file /opt/pdfshift/production/.htpasswd;

        proxy_pass http://127.0.0.1:8000/admin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 健康检查
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:8000/health;
    }
}
```

---

## 3. GitHub Actions 多环境部署

创建 `.github/workflows/deploy-multi-env.yml`:

```yaml
name: Deploy PDFShift (Multi Environment)

on:
  push:
    branches:
      - develop      # 触发测试环境部署
      - main         # 触发生产环境部署
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        type: choice
        options:
          - staging
          - production

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      # ========== 1. 确定部署环境 ==========
      - name: Determine environment
        id: env
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            ENV="${{ github.event.inputs.environment }}"
          elif [ "${{ github.ref }}" == "refs/heads/main" ]; then
            ENV="production"
          elif [ "${{ github.ref }}" == "refs/heads/develop" ]; then
            ENV="staging"
          else
            echo "Unknown branch: ${{ github.ref }}"
            exit 1
          fi

          echo "environment=$ENV" >> $GITHUB_OUTPUT

          # 设置环境特定的配置
          if [ "$ENV" == "production" ]; then
            echo "deploy_path=/opt/pdfshift/production" >> $GITHUB_OUTPUT
            echo "api_port=8000" >> $GITHUB_OUTPUT
            echo "service_prefix=pdfshift-production" >> $GITHUB_OUTPUT
          else
            echo "deploy_path=/opt/pdfshift/staging" >> $GITHUB_OUTPUT
            echo "api_port=8001" >> $GITHUB_OUTPUT
            echo "service_prefix=pdfshift-staging" >> $GITHUB_OUTPUT
          fi

          echo "✅ Deploying to: $ENV"

      # ========== 2. 检出代码 ==========
      - name: Checkout code
        uses: actions/checkout@v4

      # ========== 3. 构建前端 ==========
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

          # 根据环境设置构建变量
          if [ "${{ steps.env.outputs.environment }}" == "production" ]; then
            export VITE_API_BASE_URL=https://pdfshift.com/api
          else
            export VITE_API_BASE_URL=https://test.pdfshift.com/api
          fi

          npm run build
          echo "✅ Frontend build completed for ${{ steps.env.outputs.environment }}"

      # ========== 4. 打包 ==========
      - name: Package deployment files
        run: |
          mkdir -p deploy_package
          cp -r backend deploy_package/
          cp -r frontend/dist deploy_package/frontend_dist
          tar -czf deploy.tar.gz deploy_package/

      # ========== 5. 上传到 ECS ==========
      - name: Upload to ECS
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.ECS_HOST }}
          username: ${{ secrets.ECS_USERNAME }}
          key: ${{ secrets.ECS_SSH_KEY }}
          port: 22
          source: "deploy.tar.gz"
          target: "/tmp"

      # ========== 6. 部署 ==========
      - name: Deploy to ${{ steps.env.outputs.environment }}
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.ECS_HOST }}
          username: ${{ secrets.ECS_USERNAME }}
          key: ${{ secrets.ECS_SSH_KEY }}
          port: 22
          command_timeout: 10m
          script: |
            set -e

            ENV="${{ steps.env.outputs.environment }}"
            DEPLOY_PATH="${{ steps.env.outputs.deploy_path }}"
            SERVICE_PREFIX="${{ steps.env.outputs.service_prefix }}"

            echo "========================================="
            echo "  部署环境: $ENV"
            echo "  目标路径: $DEPLOY_PATH"
            echo "========================================="

            # 解压
            cd /tmp
            tar -xzf deploy.tar.gz

            # 备份数据库
            if [ -f "$DEPLOY_PATH/data/${ENV}.db" ]; then
              sudo -u www-data cp $DEPLOY_PATH/data/${ENV}.db \
                   $DEPLOY_PATH/data/${ENV}.db.$(date +%Y%m%d_%H%M%S)
              echo "✅ 数据库已备份"
            fi

            # 停止服务
            echo "🛑 停止 $ENV 服务..."
            sudo systemctl stop ${SERVICE_PREFIX}-api || true
            sudo systemctl stop ${SERVICE_PREFIX}-worker || true
            sudo systemctl stop ${SERVICE_PREFIX}-beat || true

            # 更新代码
            echo "📝 更新代码..."
            sudo cp -r /tmp/deploy_package/backend/* $DEPLOY_PATH/backend/
            sudo cp -r /tmp/deploy_package/frontend_dist/* $DEPLOY_PATH/frontend/dist/
            sudo chown -R www-data:www-data $DEPLOY_PATH

            # 更新依赖
            cd $DEPLOY_PATH/backend
            sudo -u www-data $DEPLOY_PATH/venv/bin/pip install -r requirements.txt --upgrade --quiet

            # 启动服务
            echo "🚀 启动 $ENV 服务..."
            sudo systemctl start ${SERVICE_PREFIX}-api
            sudo systemctl start ${SERVICE_PREFIX}-worker
            sudo systemctl start ${SERVICE_PREFIX}-beat

            sleep 5

            # 健康检查
            if curl -sf http://localhost:${{ steps.env.outputs.api_port }}/health > /dev/null; then
              echo "✅ $ENV 环境健康检查通过"
            else
              echo "❌ $ENV 环境健康检查失败"
              sudo journalctl -u ${SERVICE_PREFIX}-api -n 30
              exit 1
            fi

            # 清理
            rm -rf /tmp/deploy.tar.gz /tmp/deploy_package

            echo "✅ $ENV 环境部署完成"

      # ========== 7. 生产环境人工审批（可选）==========
      - name: Production deployment approval
        if: steps.env.outputs.environment == 'production'
        run: |
          echo "========================================="
          echo "  生产环境部署成功！"
          echo "  访问地址: https://pdfshift.com"
          echo "========================================="
```

---

## 4. 环境管理命令

### 4.1 服务控制

```bash
# ========== 测试环境 ==========
# 启动
sudo systemctl start pdfshift-staging-api
sudo systemctl start pdfshift-staging-worker

# 停止
sudo systemctl stop pdfshift-staging-api
sudo systemctl stop pdfshift-staging-worker

# 重启
sudo systemctl restart pdfshift-staging-api

# 查看状态
sudo systemctl status pdfshift-staging-api
sudo journalctl -u pdfshift-staging-api -f

# 查看日志
tail -f /opt/pdfshift/staging/logs/api.log

# ========== 生产环境 ==========
sudo systemctl start pdfshift-production-api
sudo systemctl start pdfshift-production-worker
```

### 4.2 数据库管理

```bash
# 测试数据库
sqlite3 /opt/pdfshift/staging/data/staging.db

# 生产数据库
sqlite3 /opt/pdfshift/production/data/production.db

# 从生产复制数据到测试（用于测试）
sudo -u www-data cp /opt/pdfshift/production/data/production.db \
                     /opt/pdfshift/staging/data/staging.db
```

### 4.3 环境切换测试

```bash
# 测试环境
curl http://localhost:8001/health
curl http://test.pdfshift.com/health

# 生产环境
curl http://localhost:8000/health
curl http://pdfshift.com/health
```

---

## 5. 部署流程

### 5.1 开发流程

```
开发分支 (feature/xxx)
    ↓ PR 合并
develop 分支
    ↓ 自动触发 (push)
测试环境部署 (test.pdfshift.com)
    ↓ 测试通过
main 分支
    ↓ 需要手动触发 (workflow_dispatch)
    ↓ 输入确认码: DEPLOY
生产环境部署 (pdfshift.com)
```

**安全策略**：
- ✅ 测试环境：develop 分支 push 时**自动部署**
- ⚠️ 生产环境：需要在 GitHub Actions 页面**手动触发**
- 🔒 生产环境部署需要输入确认码 `DEPLOY` 防止误操作

### 5.2 首次部署

```bash
# 1. 在服务器上初始化两个环境
sudo bash setup-multi-env.sh

# 2. 配置域名解析
test.pdfshift.com → ECS IP
pdfshift.com      → ECS IP

# 3. 推送代码到 develop 分支 → 自动部署测试环境
git push origin develop

# 4. 测试通过后，合并到 main 分支（不会自动部署）
git checkout main
git merge develop
git push origin main

# 5. 手动触发生产环境部署（见下节）
```

### 5.3 手动触发生产环境部署

**步骤**：

1. 访问 GitHub Actions 页面：
   ```
   https://github.com/你的用户名/demo-app/actions/workflows/deploy-multi-env.yml
   ```

2. 点击右侧 **"Run workflow"** 按钮

3. 在弹出的表单中：
   - **Use workflow from**: 选择 `main` 分支
   - **选择部署环境**: 选择 `production`
   - **生产环境部署确认**: 输入 `DEPLOY` (必须大写)

4. 点击绿色的 **"Run workflow"** 按钮

5. 等待部署完成（约 2-3 分钟）

6. 查看部署日志确认成功

**安全机制**：
- ✅ 必须手动点击触发
- ✅ 必须输入确认码 `DEPLOY`
- ✅ 部署失败自动回滚（生产环境）
- ✅ 记录完整的操作日志（操作人、时间、版本）

**快速命令（使用 gh CLI）**：
```bash
# 触发生产环境部署
gh workflow run deploy-multi-env.yml \
  --ref main \
  -f environment=production \
  -f confirm_production=DEPLOY
```

---

## 6. 监控与告警

### 6.1 监控指标

| 环境 | 监控内容 | 告警策略 |
|------|---------|---------|
| **测试** | 功能可用性 | 仅记录，不告警 |
| **生产** | 所有指标 | 立即告警 |

### 6.2 日志查看

```bash
# 对比两个环境的日志
tail -f /opt/pdfshift/staging/logs/api.log &
tail -f /opt/pdfshift/production/logs/api.log &
```

---

## 7. 成本分析

| 方案 | 配置 | 月成本 | 说明 |
|------|------|--------|------|
| **单服务器双环境** | 2C4G ECS | ~¥87 | 测试+生产共用 |
| **双服务器** | 1C2G + 2C4G | ~¥150 | 独立测试服务器 |

**推荐**: 初期使用单服务器双环境，流量增长后升级到双服务器。

---

**多环境配置完成**！现在支持测试环境和生产环境分离部署。
