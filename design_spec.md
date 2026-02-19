# PDFShift 技术设计文档 (Technical Design Document)

**版本**: 1.0
**日期**: 2026-01-05
**状态**: 草稿

---

## 1. 系统概述 (System Overview)

PDFShift 是一个在线 PDF 处理平台，提供格式转换（Word/Excel/PPT）、拆分、合并等功能。系统设计重点在于处理大文件（平均 50MB）、区分付费/免费用户的存储策略，以及高并发下的异步处理能力。

### 1.1 核心指标
- **流量预期**: 1000 PV/月 (初期低频，但需预留扩展性)。
- **文件特征**: 平均 50MB，最大可能达几百 MB。
- **性能要求**: 转换任务需异步处理，避免 HTTP 超时。

---

## 2. 系统架构 (System Architecture)

采用 **前后端分离** + **异步任务队列** 的架构模式。考虑到阿里云环境，推荐使用云原生组件以降低运维成本。

### 2.1 架构图 (逻辑视图)

```mermaid
graph TD
    User[用户浏览器]
    
    subgraph "前端应用"
        SPA[React/Vue SPA]
    end
    
    subgraph "接入层"
        LB[负载均衡 / 网关]
    end
    
    subgraph "后端服务 (Python)"
        API[Web API 服务 (FastAPI)]
        Worker[转换工作节点 (Celery)]
    end
    
    subgraph "数据存储"
        Redis[Redis (缓存 & 消息队列)]
        DB[MySQL (元数据 & 日志)]
        OSS[对象存储 (源文件 & 结果)]
    end

    User -- HTTPS --> SPA
    SPA -- API请求 --> LB --> API
    API -- 1.生成签名 --> OSS
    User -- 2.直传文件 --> OSS
    API -- 3.提交任务 --> Redis
    Redis -- 4.消费任务 --> Worker
    Worker -- 5.下载/处理/上传 --> OSS
    Worker -- 6.更新状态 --> DB
    SPA -- 7.轮询状态 --> API
```

---

## 3. 技术选型 (Technology Stack)

### 3.1 前端 (Frontend)
- **框架**: **React** 或 **Vue 3** (轻量、生态丰富)。
- **UI 组件库**: **Ant Design** 或 **Tailwind CSS** (快速构建响应式界面)。
- **布局系统**: 采用 Grid 或 Flex 布局实现响应式三栏结构（左侧广告-主功能区-右侧广告）。
- **广告集成**: 预留 Google AdSense / 百度联盟 JS 注入位，支持移动端自动折叠侧边广告。
- **上传组件**: **Uppy** 或 **React-Dropzone** (支持分片上传、拖拽、进度显示)。
- **后台管理**: 独立的 Admin 页面 (React Admin / Ant Design Pro)，用于参数配置和数据监控。
- **交互**: Axios (HTTP 请求), WebSocket (可选，用于实时进度推送，初期可用轮询代替)。

### 3.2 后端 (Backend)
- **语言**: **Python 3.10+** (拥有最丰富的 PDF 处理生态)。
- **Web 框架**: **FastAPI** (高性能，原生支持异步，自动生成文档)。
- **任务队列**: **Celery** (成熟的分布式任务队列)。
- **运行环境**: Docker 容器化部署。

### 3.3 核心处理库 (Core Libraries)
| 功能 | 推荐库/工具 | 备注 |
| :--- | :--- | :--- |
| **PDF 转 Word** | `pdf2docx` | 开源，效果尚可。进阶可选 LibreOffice Headless。 |
| **PDF 转 Excel** | `pdfplumber` / `camelot-py` | 擅长表格提取。 |
| **PDF 转 PPT** | `python-pptx` + 图片提取 | 将 PDF 转为图片后插入 PPT，或提取文本重组。 |
| **拆分/合并** | `PyPDF2` 或 `pikepdf` | `pikepdf` 基于 QPDF，性能更好。 |
| **预览生成** | `pdf2image` (Poppler) | 生成首图或前10页图片。 |

### 3.4 存储与数据库 (Storage & DB)
- **对象存储**: **阿里云 OSS**。
    - 必须开启 **生命周期管理 (Lifecycle)** 规则。
    - 必须开启 **跨域访问 (CORS)** 支持前端直传。
- **数据库**: **MySQL 8.0** (存储用户 ID、任务状态、订单信息)。
- **缓存/队列**: **Redis** (Celery Broker，以及缓存短期任务状态)。

### 3.5 安全与支付 (Security & Payment)
- **支付 SDK**:
    - **Alipay/WeChat SDK**: 国内支付。
- **安全组件**:
    - **HTTPS**: 阿里云 SSL 证书。
    - **MFA**: `pyotp` (用于后台管理员登录)。
    - **OSS 防盗链**: 配置 Referer 白名单。

---

## 4. 硬件与云资源配置 (Infrastructure)

基于"每月 1000 次访问"的初期目标和**单服务器部署**的约束，推荐以下配置：

### 4.1 单服务器架构 (Single Server Setup)

**架构调整说明**：
- Web API、Worker、Redis、MySQL 全部运行在同一台 ECS 上。
- 使用 **Docker Compose** 进行容器编排，实现服务隔离和资源限制。
- 通过 Nginx 作为反向代理，统一处理前端和 API 请求。

| 组件 | 规格建议 | 说明 |
| :--- | :--- | :--- |
| **ECS 服务器** | 4 vCPU / 8GB RAM / 40GB SSD | 需要运行多个服务，建议 8GB 内存以保证 PDF 转换性能。 |
| **磁盘** | 系统盘 40GB + 数据盘 100GB | 数据盘用于 Docker 数据和临时文件。 |
| **带宽** | 5 Mbps (按流量计费) | 主要流量走 OSS，ECS 带宽需求不高。 |
| **OSS** | 按量付费 | 标准存储包 + 下行流量包（根据实际用量调整）。 |

**服务资源分配** (Docker Compose 限制)：
- FastAPI (Web): 1 vCPU / 1GB RAM
- Celery Worker: 2 vCPU / 4GB RAM (PDF 转换主力)
- Redis: 0.5 vCPU / 512MB RAM
- MySQL: 0.5 vCPU / 1GB RAM
- Nginx: 0.2 vCPU / 256MB RAM

*注：留出约 1.5GB 内存和 0.8 vCPU 给系统和临时进程。*

---

## 5. 数据库设计 (Database Schema)
### 5.1 任务表 (`tasks`)
记录每一次转换请求。

```sql
CREATE TABLE tasks (
    task_id VARCHAR(64) PRIMARY KEY, -- UUID
    client_id VARCHAR(64) NOT NULL,  -- 浏览器指纹
    file_name VARCHAR(255),
    file_size BIGINT,
    oss_key_source VARCHAR(255),     -- 源文件路径
    oss_key_result VARCHAR(255),     -- 结果文件路径
    task_type ENUM('pdf2word', 'merge', 'split', ...),
    status ENUM('pending', 'processing', 'completed', 'failed', 'expired'),
    is_paid BOOLEAN DEFAULT FALSE,   -- 是否付费任务
    error_msg TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    expire_at DATETIME,              -- 过期时间 (关键)
    INDEX idx_client (client_id),
    INDEX idx_expire (expire_at)
);
```

### 5.2 订单表 (`orders`)
记录付费解锁记录。

```sql
CREATE TABLE orders (
    order_id VARCHAR(64) PRIMARY KEY,
    client_id VARCHAR(64),
    task_id VARCHAR(64),
    amount DECIMAL(10, 2),
    status ENUM('unpaid', 'paid', 'refunded'),
    payment_time DATETIME
);
```

### 5.3 系统配置表 (`system_configs`)
存储动态系统参数。

```sql
CREATE TABLE system_configs (
    config_key VARCHAR(50) PRIMARY KEY,
    config_value VARCHAR(255),
    description VARCHAR(100),
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
-- 预设数据:
-- ('retention_free_hours', '1', '免费文件保留小时数')
-- ('retention_paid_hours', '24', '付费文件保留小时数')
-- ('price_large_file', '5.00', '大文件解锁价格')
-- ('daily_free_quota_gb', '100', '每日免费流量限额(GB)')
```

---

## 6. 核心交互流程 (Core Workflows)
### 6.1 上传与转换流程
1.  **获取凭证**: 前端发送文件名、大小给后端 `/api/upload/sign`。
2.  **策略检查**: 后端检查大小。
    - 若 > 500MB: 直接拒绝 (硬性限制)。
    - 若 < 50MB: 返回 OSS 直传签名。
    - 若 50MB - 500MB: 检查 `orders` 表是否已付费。未付费则返回“需付费或预览”提示。
3.  **直传 OSS**: 前端直接 PUT 文件到 OSS（不经过后端服务器带宽）。
4.  **触发任务**: 上传完成后，前端调用 `/api/convert`，携带 OSS 路径。
    - **异常处理**: 若检测到 PDF 加密，Worker 抛出 `EncryptedError`，前端提示输入密码。
    - **预览模式**: 若用户选择预览，Worker 仅处理前 10 页并添加水印。
5.  **异步处理**: 后端将任务推入 Celery Redis 队列，立即返回 `task_id`。
6.  **轮询状态**: 前端每 2 秒轮询 `/api/status/{task_id}`。
7.  **任务执行**: Worker 节点下载 PDF -> 转换 -> 上传结果到 OSS -> 更新 DB。
8.  **下载**: 任务完成后，后端生成**带时效的下载链接**返回给前端。

### 6.2 空间清理流程 (Cleanup Strategy)
由于 OSS 原生生命周期通常最小粒度为“天”，为了实现 **1小时/24小时** 的精确清理，采用 **后端定时任务 (Celery Beat)**。

1.  **定时任务**: 每 10 分钟运行一次 `cleanup_job`。
2.  **查询过期**: `SELECT * FROM tasks WHERE status='completed' AND expire_at < NOW()`。
3.  **执行删除**:
    - 调用 OSS SDK 删除 `oss_key_source` 和 `oss_key_result`。
    - 更新 DB 状态为 `expired`。
4.  **用户访问**: 用户点击旧链接时，后端检查状态，若为 `expired` 则提示“文件已过期”。

### 6.3 支付与退款流程 (Payment & Refund)
1.  **创建订单**: 用户选择付费解锁，前端调用 `/api/orders`。
2.  **支付回调**: 支付网关回调 `/api/orders/callback`，更新订单状态为 `paid`，自动触发全量转换任务。
3.  **自动退款**: 若 Worker 转换失败（如文件损坏），后端自动调用支付网关退款接口，并更新订单状态为 `refunded`。

---

## 7. 接口定义 (API Design - RESTful)

- `POST /api/v1/upload/policy`: 获取 OSS 上传凭证。
- `POST /api/v1/tasks`: 创建转换任务 (参数: oss_key, type, options)。
- `GET /api/v1/tasks/{task_id}`: 查询任务状态及下载链接。
- `GET /api/v1/history`: 查询当前 Client ID 的历史记录 (仅限付费用户)。
- `POST /api/v1/orders`: 创建支付订单。
- `POST /api/v1/orders/callback`: 支付回调接口。

### 7.2 管理后台接口 (Admin API)
- `GET /api/admin/configs`: 获取系统参数。
- `PUT /api/admin/configs`: 更新系统参数（支持热更新）。
- `GET /api/admin/stats/daily`: 获取每日业务报表。
- `GET /api/admin/stats/revenue`: 获取收入统计。
- `GET /api/admin/logs`: 查询操作日志（支持分页和筛选）。
- `GET /api/admin/tasks`: 查询所有任务（支持按状态、时间筛选）。
- `POST /api/admin/cleanup`: 手动触发清理任务。
