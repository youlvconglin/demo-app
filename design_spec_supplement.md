# PDFShift 技术设计文档补充 (Supplement)

**版本**: 1.0
**日期**: 2026-02-19
**说明**: 本文档补充单服务器部署方案和 GitHub CI/CD 配置

---

## 8. 部署架构与 CI/CD (Deployment & CI/CD)

### 8.1 单服务器架构图

```
┌─────────────────────────────────────────────────────┐
│                  阿里云 ECS (单服务器)                  │
│  ┌───────────────────────────────────────────────┐  │
│  │          Nginx (反向代理 + 静态文件)            │  │
│  │  - 前端: /                                     │  │
│  │  - API: /api/*                                │  │
│  │  - Admin: /admin (独立入口 + 认证)             │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  │
│  │  FastAPI    │  │ Celery Worker│  │  Redis   │  │
│  │  (Web API)  │◄─┤  (PDF处理)   │◄─┤ (队列)   │  │
│  └─────────────┘  └──────────────┘  └──────────┘  │
│         │                │                         │
│         └────────┬───────┘                         │
│                  ▼                                 │
│         ┌──────────────┐                           │
│         │    MySQL     │                           │
│         │  (元数据)     │                           │
│         └──────────────┘                           │
└─────────────────────────────────────────────────────┘
                     │
                     ▼
            ┌─────────────────┐
            │   阿里云 OSS     │
            │  (文件存储)      │
            └─────────────────┘
```

### 8.2 Docker Compose 完整配置

创建 `docker-compose.yml`:

```yaml
version: '3.8'

services:
  # Nginx 反向代理
  nginx:
    image: nginx:alpine
    container_name: pdfshift-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./frontend/dist:/usr/share/nginx/html:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/logs:/var/log/nginx
    depends_on:
      - api
    restart: unless-stopped
    networks:
      - pdfshift-network

  # FastAPI Web 服务
  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: pdfshift-api
    environment:
      - DATABASE_URL=mysql+pymysql://pdfshift:${DB_PASSWORD}@db:3306/pdfshift
      - REDIS_URL=redis://redis:6379/0
      - OSS_ACCESS_KEY=${OSS_ACCESS_KEY}
      - OSS_SECRET_KEY=${OSS_SECRET_KEY}
      - OSS_BUCKET=${OSS_BUCKET}
      - OSS_ENDPOINT=${OSS_ENDPOINT}
      - JWT_SECRET=${JWT_SECRET}
      - ADMIN_USERNAME=${ADMIN_USERNAME}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
    depends_on:
      - db
      - redis
    restart: unless-stopped
    networks:
      - pdfshift-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  # Celery Worker (PDF 处理)
  worker:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: pdfshift-worker
    command: celery -A app.celery worker --loglevel=info --concurrency=2
    environment:
      - DATABASE_URL=mysql+pymysql://pdfshift:${DB_PASSWORD}@db:3306/pdfshift
      - REDIS_URL=redis://redis:6379/0
      - OSS_ACCESS_KEY=${OSS_ACCESS_KEY}
      - OSS_SECRET_KEY=${OSS_SECRET_KEY}
      - OSS_BUCKET=${OSS_BUCKET}
      - OSS_ENDPOINT=${OSS_ENDPOINT}
    depends_on:
      - db
      - redis
    volumes:
      - /tmp/pdfshift:/tmp/pdfshift
    restart: unless-stopped
    networks:
      - pdfshift-network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  # Celery Beat (定时任务调度器)
  beat:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: pdfshift-beat
    command: celery -A app.celery beat --loglevel=info
    environment:
      - DATABASE_URL=mysql+pymysql://pdfshift:${DB_PASSWORD}@db:3306/pdfshift
      - REDIS_URL=redis://redis:6379/0
      - OSS_ACCESS_KEY=${OSS_ACCESS_KEY}
      - OSS_SECRET_KEY=${OSS_SECRET_KEY}
    depends_on:
      - db
      - redis
    restart: unless-stopped
    networks:
      - pdfshift-network

  # Redis (消息队列 + 缓存)
  redis:
    image: redis:7-alpine
    container_name: pdfshift-redis
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
    networks:
      - pdfshift-network
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  # MySQL 数据库
  db:
    image: mysql:8.0
    container_name: pdfshift-db
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=pdfshift
      - MYSQL_USER=pdfshift
      - MYSQL_PASSWORD=${DB_PASSWORD}
      - TZ=Asia/Shanghai
    volumes:
      - mysql_data:/var/lib/mysql
      - ./backend/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    restart: unless-stopped
    networks:
      - pdfshift-network
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G

networks:
  pdfshift-network:
    driver: bridge

volumes:
  mysql_data:
  redis_data:
```

### 8.3 Nginx 配置

创建 `nginx/nginx.conf`:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_size_bytes "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 500M;  # 允许上传大文件

    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    # 主站配置
    server {
        listen 80;
        server_name coreshift.cn www.coreshift.cn;  # 替换为你的域名

        # 强制跳转 HTTPS (生产环境启用)
        # return 301 https://$server_name$request_uri;

        # 前端静态文件
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;  # SPA 路由支持

            # 静态资源缓存
            location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
                expires 1y;
                add_header Cache-Control "public, immutable";
            }
        }

        # API 代理
        location /api/ {
            proxy_pass http://api:8000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # 超时设置
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # 管理后台 (独立路由 + 基础认证)
        location /admin/ {
            auth_basic "Admin Area";
            auth_basic_user_file /etc/nginx/.htpasswd;  # 需要创建密码文件

            proxy_pass http://api:8000/admin/;
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

    # HTTPS 配置 (可选，配置 SSL 后启用)
    # server {
    #     listen 443 ssl http2;
    #     server_name coreshift.cn www.coreshift.cn;
    #
    #     ssl_certificate /etc/nginx/ssl/fullchain.pem;
    #     ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    #     ssl_protocols TLSv1.2 TLSv1.3;
    #     ssl_ciphers HIGH:!aNULL:!MD5;
    #
    #     # 其他配置同上 HTTP 部分
    # }
}
```

### 8.4 GitHub Actions CI/CD 完整配置

创建 `.github/workflows/deploy.yml`:

```yaml
name: Deploy PDFShift to ECS

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  DEPLOY_PATH: /opt/pdfshift

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      # 1. 检出代码
      - name: Checkout code
        uses: actions/checkout@v4

      # 2. 设置 Node.js 环境
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      # 3. 构建前端
      - name: Build frontend
        run: |
          cd frontend
          npm ci --legacy-peer-deps
          npm run build
          echo "Frontend build completed at $(date)"

      # 4. 打包部署文件
      - name: Package deployment files
        run: |
          mkdir -p deploy_package
          cp -r frontend/dist deploy_package/frontend_dist
          cp -r backend deploy_package/
          cp docker-compose.yml deploy_package/
          cp -r nginx deploy_package/
          tar -czf deploy.tar.gz deploy_package/

      # 5. 上传到 ECS
      - name: Upload to ECS
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.ECS_HOST }}
          username: ${{ secrets.ECS_USERNAME }}
          key: ${{ secrets.ECS_SSH_KEY }}
          port: 22
          source: "deploy.tar.gz"
          target: "/tmp"

      # 6. 部署并重启服务
      - name: Deploy and restart services
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

            # 备份旧版本
            if [ -d "${{ env.DEPLOY_PATH }}" ]; then
              sudo cp -r ${{ env.DEPLOY_PATH }} ${{ env.DEPLOY_PATH }}.backup.$(date +%Y%m%d_%H%M%S)
              echo "已备份旧版本"
            fi

            # 创建部署目录
            sudo mkdir -p ${{ env.DEPLOY_PATH }}

            # 复制新文件
            sudo cp -r /tmp/deploy_package/* ${{ env.DEPLOY_PATH }}/

            # 移动前端文件到正确位置
            sudo rm -rf ${{ env.DEPLOY_PATH }}/frontend/dist
            sudo mv ${{ env.DEPLOY_PATH }}/frontend_dist ${{ env.DEPLOY_PATH }}/frontend/dist

            # 进入部署目录
            cd ${{ env.DEPLOY_PATH }}

            # 检查 .env 文件
            if [ ! -f .env ]; then
              echo "警告: .env 文件不存在，请手动创建！"
              exit 1
            fi

            # 加载环境变量
            export $(cat .env | xargs)

            echo "========== 构建镜像 =========="
            sudo docker-compose build --no-cache

            echo "========== 停止旧服务 =========="
            sudo docker-compose down || true

            echo "========== 启动新服务 =========="
            sudo docker-compose up -d

            echo "========== 等待服务启动 =========="
            sleep 10

            echo "========== 检查服务状态 =========="
            sudo docker-compose ps

            echo "========== 检查服务健康 =========="
            if curl -f http://localhost/health > /dev/null 2>&1; then
              echo "✅ 健康检查通过"
            else
              echo "❌ 健康检查失败"
              sudo docker-compose logs --tail=50
              exit 1
            fi

            echo "========== 清理旧镜像 =========="
            sudo docker image prune -f

            echo "========== 清理临时文件 =========="
            rm -rf /tmp/deploy.tar.gz /tmp/deploy_package

            echo "========== 部署完成 =========="
            echo "部署时间: $(date)"
            echo "服务访问: http://${{ secrets.ECS_HOST }}"
```

### 8.5 环境变量配置文件

在 ECS 服务器手动创建 `/opt/pdfshift/.env`:

```bash
# 数据库配置
DB_ROOT_PASSWORD=your_secure_root_password_here
DB_PASSWORD=your_secure_password_here

# OSS 配置
OSS_ACCESS_KEY=LTAI5txxxxxxxxxxxxxx
OSS_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxx
OSS_BUCKET=coreshift-storage
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com

# JWT 配置
JWT_SECRET=your_random_jwt_secret_key_min_32_chars

# 管理员账号 (用于后台登录)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your_strong_admin_password

# 支付配置 (支付宝)
ALIPAY_APP_ID=2021xxxxxxxxxx
ALIPAY_PRIVATE_KEY=MIIEvQIBADANBgkq...
ALIPAY_PUBLIC_KEY=MIIBIjANBgkqhkiG9w0B...

# 微信支付配置
WECHAT_APP_ID=wxxxxxxxxxxx
WECHAT_MCH_ID=1234567890
WECHAT_API_KEY=your_wechat_api_key
```

**重要安全提示**:
```bash
# 设置文件权限
sudo chmod 600 /opt/pdfshift/.env
sudo chown root:root /opt/pdfshift/.env
```

### 8.6 管理后台访问配置

创建 Nginx 基础认证密码文件：

```bash
# 在 ECS 服务器上执行
sudo apt install apache2-utils -y

# 创建密码文件
sudo htpasswd -c /opt/pdfshift/nginx/.htpasswd admin

# 输入密码（会提示两次）
# 文件会生成在 nginx/.htpasswd
```

**多层安全策略**:
1. **Nginx 基础认证**: 第一层密码保护 (`/admin` 路由)
2. **JWT Token 认证**: 后端 API 验证管理员身份
3. **IP 白名单** (可选): 仅允许特定 IP 访问管理后台

---

## 9. 监控与日志 (Monitoring & Logging)

### 9.1 日志策略

**Docker 日志配置** (已在 docker-compose.yml 中设置):

```yaml
services:
  api:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"    # 单文件最大 10MB
        max-file: "3"      # 保留 3 个文件 (共 30MB)
```

**查看日志命令**:
```bash
# 查看所有服务日志
sudo docker-compose logs

# 查看特定服务日志
sudo docker-compose logs -f api
sudo docker-compose logs -f worker --tail=100

# 查看 Nginx 访问日志
tail -f /opt/pdfshift/nginx/logs/access.log
```

### 9.2 阿里云监控配置

**基础监控** (免费):
1. 登录阿里云控制台 → 云监控
2. 添加 ECS 主机监控
3. 配置告警规则：
   - CPU 使用率 > 85% 持续 5 分钟 → 发送短信
   - 内存使用率 > 90% → 发送邮件
   - 磁盘使用率 > 80% → 发送通知

**自定义监控指标** (可选):
```python
# backend/app/monitoring.py
from aliyun.log import LogClient

def report_metric(metric_name, value):
    """上报自定义指标到阿里云监控"""
    client = LogClient(endpoint, access_key_id, access_key_secret)
    # 实现具体上报逻辑
```

### 9.3 关键指标监控

| 指标类型 | 监控项 | 告警阈值 | 处理方式 |
|---------|--------|---------|---------|
| **系统** | CPU 使用率 | > 85% 持续 5min | 检查 Worker 负载 |
| **系统** | 内存使用率 | > 90% | 重启服务释放内存 |
| **系统** | 磁盘使用率 | > 80% | 清理临时文件 |
| **应用** | 任务队列长度 | > 50 | 增加 Worker 并发数 |
| **应用** | 转换成功率 | < 95% (日) | 检查 Worker 错误日志 |
| **应用** | API 响应时间 (P95) | > 2s | 检查数据库慢查询 |
| **业务** | 日活用户 (DAU) | 异常下降 | 检查服务可用性 |
| **业务** | 支付成功率 | < 98% | 检查支付网关 |

---

## 10. 管理后台详细设计

### 10.1 认证流程

```
用户访问 /admin
    ↓
Nginx 基础认证 (第一层防护)
    ↓ 通过
前端跳转到登录页
    ↓
输入管理员账号密码
    ↓
后端验证 (对比环境变量)
    ↓ 通过
返回 JWT Token
    ↓
前端存储 Token
    ↓
后续请求携带 Token
    ↓
后端中间件验证 Token
    ↓ 通过
访问管理功能
```

### 10.2 后台功能模块

**数据库表设计 - 管理员表**:
```sql
CREATE TABLE admin_users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- bcrypt 加密
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    INDEX idx_username (username)
);
```

**FastAPI 认证实现**:
```python
# backend/app/admin/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from passlib.context import CryptContext
import jwt
import os

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()

JWT_SECRET = os.getenv("JWT_SECRET")
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME")
ADMIN_PASSWORD_HASH = pwd_context.hash(os.getenv("ADMIN_PASSWORD"))

def verify_admin_credentials(username: str, password: str) -> bool:
    """验证管理员凭据"""
    if username != ADMIN_USERNAME:
        return False
    return pwd_context.verify(password, ADMIN_PASSWORD_HASH)

def create_admin_token(username: str) -> str:
    """生成 JWT Token"""
    payload = {"sub": username, "role": "admin"}
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """验证 Token 中间件"""
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=["HS256"])
        if payload.get("role") != "admin":
            raise HTTPException(status_code=403, detail="Not authorized")
        return payload
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

# 路由示例
from fastapi import APIRouter
router = APIRouter(prefix="/admin", tags=["admin"])

@router.post("/login")
async def admin_login(username: str, password: str):
    if not verify_admin_credentials(username, password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_admin_token(username)
    return {"access_token": token, "token_type": "bearer"}

@router.get("/configs", dependencies=[Depends(get_current_admin)])
async def get_configs():
    # 获取系统配置
    return {"configs": [...]}
```

### 10.3 后台管理页面路由

| 路由 | 功能 | 权限要求 |
|------|------|---------|
| `/admin/login` | 登录页面 | 无 |
| `/admin/dashboard` | 控制台首页 | Admin Token |
| `/admin/tasks` | 任务管理 | Admin Token |
| `/admin/users` | 用户管理 | Admin Token |
| `/admin/configs` | 系统配置 | Admin Token |
| `/admin/stats` | 数据统计 | Admin Token |
| `/admin/logs` | 操作日志 | Admin Token |

---

## 11. 数据库补充设计

### 11.1 管理员操作日志表

```sql
CREATE TABLE admin_logs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    admin_username VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,          -- 操作类型: UPDATE_CONFIG, MANUAL_CLEANUP 等
    target_table VARCHAR(50),              -- 操作的表
    target_id VARCHAR(64),                 -- 操作的记录 ID
    old_value TEXT,                        -- 修改前的值 (JSON)
    new_value TEXT,                        -- 修改后的值 (JSON)
    ip_address VARCHAR(45),                -- 管理员 IP
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_username, created_at),
    INDEX idx_action (action, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**记录示例**:
```python
# 记录配置修改
log_admin_action(
    admin_username="admin",
    action="UPDATE_CONFIG",
    target_table="system_configs",
    target_id="retention_free_hours",
    old_value='{"value": "1"}',
    new_value='{"value": "2"}',
    ip_address=request.client.host
)
```

### 11.2 数据报表视图

```sql
-- 每日转换统计视图
CREATE VIEW daily_conversion_stats AS
SELECT
    DATE(created_at) as date,
    task_type,
    COUNT(*) as total_tasks,
    SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed_tasks,
    SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed_tasks,
    SUM(CASE WHEN is_paid=TRUE THEN 1 ELSE 0 END) as paid_tasks,
    AVG(TIMESTAMPDIFF(SECOND, created_at, completed_at)) as avg_processing_time
FROM tasks
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at), task_type;

-- 收入统计视图
CREATE VIEW daily_revenue_stats AS
SELECT
    DATE(payment_time) as date,
    COUNT(*) as order_count,
    SUM(amount) as total_revenue,
    SUM(CASE WHEN status='refunded' THEN amount ELSE 0 END) as refunded_amount
FROM orders
WHERE status IN ('paid', 'refunded')
  AND payment_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(payment_time);
```

---

## 12. 部署检查清单

### 12.1 初次部署步骤

```bash
# 1. 登录 ECS 服务器
ssh root@your-ecs-ip

# 2. 安装 Docker 和 Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 3. 创建部署目录
sudo mkdir -p /opt/pdfshift
sudo chown $USER:$USER /opt/pdfshift

# 4. 配置环境变量
cd /opt/pdfshift
nano .env  # 填入上面 8.5 节的环境变量

# 5. 创建 Nginx 密码文件
sudo apt install apache2-utils -y
sudo htpasswd -c nginx/.htpasswd admin

# 6. 配置 GitHub Secrets
# 在 GitHub 仓库 Settings → Secrets 中添加:
# - ECS_HOST: 你的 ECS 公网 IP
# - ECS_USERNAME: root (或你的 SSH 用户名)
# - ECS_SSH_KEY: SSH 私钥完整内容

# 7. 推送代码触发自动部署
# 或手动运行 GitHub Actions

# 8. 首次部署后初始化数据库
sudo docker exec -it pdfshift-db mysql -u root -p
# 执行初始化 SQL 脚本
```

### 12.2 部署后验证

```bash
# 1. 检查所有容器运行状态
sudo docker-compose ps

# 2. 检查健康状态
curl http://localhost/health

# 3. 测试 API
curl http://localhost/api/v1/upload/policy

# 4. 测试管理后台
curl -u admin:your_password http://localhost/admin/

# 5. 查看日志
sudo docker-compose logs --tail=50

# 6. 检查磁盘空间
df -h

# 7. 检查内存使用
free -h
```

---

## 13. 故障排查指南

### 13.1 常见问题

| 问题现象 | 可能原因 | 解决方案 |
|---------|---------|---------|
| 容器无法启动 | 端口被占用 | `sudo lsof -i :80` 检查端口占用 |
| API 502 错误 | FastAPI 容器未启动 | `docker logs pdfshift-api` 查看错误 |
| 转换失败 | Worker 内存不足 | 增加 Worker 内存限制或减少并发数 |
| 数据库连接失败 | MySQL 未就绪 | 等待 30 秒后重试 |
| OSS 上传失败 | 凭证错误 | 检查 `.env` 中的 OSS 配置 |
| 管理后台 403 | Nginx 密码错误 | 重新生成 `.htpasswd` |
| 磁盘满 | 临时文件未清理 | `sudo rm -rf /tmp/pdfshift/*` |

### 13.2 紧急回滚

```bash
# 查看可用的备份
ls -lh /opt/pdfshift.backup.*

# 停止当前服务
cd /opt/pdfshift
sudo docker-compose down

# 恢复备份
sudo rm -rf /opt/pdfshift
sudo cp -r /opt/pdfshift.backup.20260219_103000 /opt/pdfshift

# 重启服务
cd /opt/pdfshift
sudo docker-compose up -d
```

---

**文档结束** - 完整的单服务器部署方案和 CI/CD 配置已完成。
