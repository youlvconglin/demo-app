#!/bin/bash
# 生产环境 Systemd 服务创建脚本

echo "创建生产环境 systemd 服务..."

# 1. 创建 API 服务
cat > /tmp/pdfshift-production-api.service << 'EOF'
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
EOF

# 2. 创建 Worker 服务
cat > /tmp/pdfshift-production-worker.service << 'EOF'
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
EOF

# 3. 创建 Beat 服务
cat > /tmp/pdfshift-production-beat.service << 'EOF'
[Unit]
Description=PDFShift Production Beat Scheduler
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/pdfshift/production/backend
Environment="PATH=/opt/pdfshift/production/venv/bin"
EnvironmentFile=/opt/pdfshift/production/.env
ExecStart=/opt/pdfshift/production/venv/bin/celery -A app.celery beat --loglevel=info

Restart=always
RestartSec=10

StandardOutput=append:/opt/pdfshift/production/logs/beat.log
StandardError=append:/opt/pdfshift/production/logs/beat.log

[Install]
WantedBy=multi-user.target
EOF

# 4. 安装服务文件
sudo mv /tmp/pdfshift-production-api.service /etc/systemd/system/
sudo mv /tmp/pdfshift-production-worker.service /etc/systemd/system/
sudo mv /tmp/pdfshift-production-beat.service /etc/systemd/system/

# 5. 重载 systemd
sudo systemctl daemon-reload

# 6. 启用服务（开机自启）
sudo systemctl enable pdfshift-production-api
sudo systemctl enable pdfshift-production-worker
sudo systemctl enable pdfshift-production-beat

# 7. 启动服务
sudo systemctl start pdfshift-production-api
sudo systemctl start pdfshift-production-worker
sudo systemctl start pdfshift-production-beat

# 8. 检查状态
echo ""
echo "========================================="
echo "服务状态:"
echo "========================================="
sudo systemctl status pdfshift-production-api --no-pager | head -15
echo ""
sudo systemctl status pdfshift-production-worker --no-pager | head -15
echo ""
sudo systemctl status pdfshift-production-beat --no-pager | head -15

# 9. 测试健康检查
echo ""
echo "========================================="
echo "健康检查:"
echo "========================================="
sleep 3
curl -s http://localhost:8000/api/v1/health | jq . || curl -s http://localhost:8000/api/v1/health

echo ""
echo "✅ 生产环境服务配置完成！"
