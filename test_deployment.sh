#!/bin/bash
# 部署测试脚本

set -e

echo "========================================="
echo "  PDFShift 部署测试"
echo "========================================="

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 1. 检查服务状态
echo ""
echo "1. 检查服务状态..."

if systemctl is-active --quiet pdfshift-production-api; then
  echo -e "${GREEN}✓${NC} API 服务运行中"
else
  echo -e "${RED}✗${NC} API 服务未运行"
  exit 1
fi

if systemctl is-active --quiet pdfshift-production-worker; then
  echo -e "${GREEN}✓${NC} Worker 服务运行中"
else
  echo -e "${RED}✗${NC} Worker 服务未运行"
fi

# 2. 测试健康检查
echo ""
echo "2. 测试健康检查..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)

if [ "$HTTP_CODE" == "200" ]; then
  echo -e "${GREEN}✓${NC} 健康检查通过 (HTTP $HTTP_CODE)"
else
  echo -e "${RED}✗${NC} 健康检查失败 (HTTP $HTTP_CODE)"
  exit 1
fi

# 3. 测试 API 端点
echo ""
echo "3. 测试 API 端点..."

# 测试根路径
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/)
if [ "$HTTP_CODE" == "200" ]; then
  echo -e "${GREEN}✓${NC} 根路径测试通过"
else
  echo -e "${RED}✗${NC} 根路径测试失败"
fi

# 测试上传凭证
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8000/api/v1/upload/policy \
  -H "Content-Type: application/json" \
  -d '{"filename":"test.pdf","size":1024000}')

if [ "$HTTP_CODE" == "200" ]; then
  echo -e "${GREEN}✓${NC} 上传凭证 API 测试通过"
else
  echo -e "${RED}✗${NC} 上传凭证 API 测试失败"
fi

# 4. 检查数据库
echo ""
echo "4. 检查数据库..."

DB_FILE="/opt/pdfshift/production/data/production.db"

if [ -f "$DB_FILE" ]; then
  echo -e "${GREEN}✓${NC} 数据库文件存在"
  echo "   大小: $(du -h $DB_FILE | cut -f1)"

  # 检查表
  TABLES=$(sqlite3 $DB_FILE "SELECT name FROM sqlite_master WHERE type='table';" | wc -l)
  echo "   表数量: $TABLES"
else
  echo -e "${RED}✗${NC} 数据库文件不存在"
fi

# 5. 检查磁盘空间
echo ""
echo "5. 检查磁盘空间..."

DISK_USAGE=$(df -h /opt/pdfshift | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -lt 80 ]; then
  echo -e "${GREEN}✓${NC} 磁盘使用率正常 ($DISK_USAGE%)"
else
  echo -e "${RED}⚠${NC} 磁盘使用率较高 ($DISK_USAGE%)"
fi

# 6. 检查内存
echo ""
echo "6. 检查内存使用..."

MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')

if [ "$MEM_USAGE" -lt 90 ]; then
  echo -e "${GREEN}✓${NC} 内存使用正常 ($MEM_USAGE%)"
else
  echo -e "${RED}⚠${NC} 内存使用率较高 ($MEM_USAGE%)"
fi

# 7. 检查 Redis
echo ""
echo "7. 检查 Redis..."

if redis-cli ping > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Redis 运行正常"
else
  echo -e "${RED}✗${NC} Redis 无法连接"
fi

# 完成
echo ""
echo "========================================="
echo -e "${GREEN}  测试完成！${NC}"
echo "========================================="
