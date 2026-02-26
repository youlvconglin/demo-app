#!/bin/bash
echo "========== API 日志（最后 50 行）=========="
sudo journalctl -u pdfshift-production-api -n 50 --no-pager

echo ""
echo "========== Worker 日志（最后 30 行）=========="
sudo journalctl -u pdfshift-production-worker -n 30 --no-pager

echo ""
echo "========== 检查端口监听 =========="
sudo ss -tlnp | grep -E ':(8000|8001)'

echo ""
echo "========== 检查进程 =========="
ps aux | grep -E 'uvicorn|celery' | grep -v grep

echo ""
echo "========== 检查环境变量文件 =========="
ls -la /opt/pdfshift/production/.env
sudo cat /opt/pdfshift/production/.env | grep -E 'APP_ENV|API_PORT|DATABASE_URL'

echo ""
echo "========== 检查后端代码是否存在 =========="
ls -la /opt/pdfshift/production/backend/app/main.py
