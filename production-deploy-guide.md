# 生产环境手动部署指南

## 1. 服务器端操作

### 1.1 配置环境变量
```bash
# 编辑生产环境配置
sudo nano /opt/pdfshift/production/.env

# 配置内容（参考测试环境，修改关键参数）：
APP_ENV=production
APP_DEBUG=false
DATABASE_URL=sqlite:////opt/pdfshift/production/data/production.db
REDIS_URL=redis://localhost:6379/0
STORAGE_TYPE=local
STORAGE_BASE_PATH=/opt/pdfshift/production/storage
JWT_SECRET=<生成新的随机字符串>
ADMIN_PASSWORD=<设置强密码>
API_PORT=8000
```

### 1.2 初始化数据库
```bash
cd ~/demo-app
sudo -u www-data sqlite3 /opt/pdfshift/production/data/production.db < backend/init.sql
```

### 1.3 复制代码
```bash
sudo cp -r ~/demo-app/backend/* /opt/pdfshift/production/backend/
sudo cp -r /opt/pdfshift/staging/frontend/dist/* /opt/pdfshift/production/frontend/dist/
sudo chown -R www-data:www-data /opt/pdfshift/production
```

### 1.4 安装依赖
```bash
cd /opt/pdfshift/production/backend
/opt/pdfshift/production/venv/bin/pip install \
  -r requirements.txt \
  --index-url https://mirrors.aliyun.com/pypi/simple/ \
  --trusted-host mirrors.aliyun.com
```

### 1.5 创建 systemd 服务
```bash
# API 服务
sudo cat > /etc/systemd/system/pdfshift-production-api.service << 'ENDOFFILE'
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
ENDOFFILE

# Worker 服务
sudo cat > /etc/systemd/system/pdfshift-production-worker.service << 'ENDOFFILE'
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
ExecStart=/opt/pdfshift/production/venv/bin/celery -A app.celery_app worker --loglevel=info --concurrency=2

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/production/logs/worker.log
StandardError=append:/opt/pdfshift/production/logs/worker.log

[Install]
WantedBy=multi-user.target
ENDOFFILE

# Beat 服务
sudo cat > /etc/systemd/system/pdfshift-production-beat.service << 'ENDOFFILE'
[Unit]
Description=PDFShift Production Beat
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/production/backend
Environment="PATH=/opt/pdfshift/production/venv/bin"
EnvironmentFile=/opt/pdfshift/production/.env
ExecStart=/opt/pdfshift/production/venv/bin/celery -A app.celery_app beat --loglevel=info

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/production/logs/beat.log
StandardError=append:/opt/pdfshift/production/logs/beat.log

[Install]
WantedBy=multi-user.target
ENDOFFILE
```

### 1.6 启动服务
```bash
sudo systemctl daemon-reload
sudo systemctl enable pdfshift-production-api pdfshift-production-worker pdfshift-production-beat
sudo systemctl start pdfshift-production-api pdfshift-production-worker pdfshift-production-beat

# 检查状态
sudo systemctl status pdfshift-production-api
curl http://localhost:8000/health
```

### 1.7 配置 Nginx
```bash
# 编辑配置，取消生产环境的注释
sudo nano /etc/nginx/sites-available/coreshift

# 或者直接添加生产环境配置
sudo bash -c 'cat >> /etc/nginx/sites-available/coreshift' << 'ENDCONFIG'

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
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
    }
}
ENDCONFIG

# 重载 Nginx
sudo nginx -t
sudo systemctl reload nginx
```

## 2. 域名配置

在域名服务商添加 A 记录：
```
主机记录: @
记录值: ECS_IP
```

## 3. 验证部署

```bash
# 服务器验证
curl http://localhost:8000/health

# 浏览器访问
http://coreshift.cn/health
```
