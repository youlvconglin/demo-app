-- PDFShift SQLite 数据库初始化脚本
-- 版本: 1.0
-- 日期: 2026-02-19

-- 任务表
CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    oss_key_source TEXT,
    oss_key_result TEXT,
    task_type TEXT CHECK(task_type IN ('pdf2word', 'pdf2excel', 'pdf2ppt', 'merge', 'split')),
    status TEXT CHECK(status IN ('pending', 'processing', 'completed', 'failed', 'expired')) DEFAULT 'pending',
    is_paid INTEGER DEFAULT 0,
    error_msg TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    expire_at DATETIME
);

CREATE INDEX IF NOT EXISTS idx_client ON tasks(client_id);
CREATE INDEX IF NOT EXISTS idx_expire ON tasks(expire_at);
CREATE INDEX IF NOT EXISTS idx_status ON tasks(status, created_at);
CREATE INDEX IF NOT EXISTS idx_task_created ON tasks(created_at DESC);

-- 订单表
CREATE TABLE IF NOT EXISTS orders (
    order_id TEXT PRIMARY KEY,
    client_id TEXT,
    task_id TEXT,
    amount REAL,
    status TEXT CHECK(status IN ('unpaid', 'paid', 'refunded')) DEFAULT 'unpaid',
    payment_time DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(task_id)
);

CREATE INDEX IF NOT EXISTS idx_order_client ON orders(client_id);
CREATE INDEX IF NOT EXISTS idx_order_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_payment_time ON orders(payment_time);

-- 系统配置表
CREATE TABLE IF NOT EXISTS system_configs (
    config_key TEXT PRIMARY KEY,
    config_value TEXT,
    description TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 预设系统配置
INSERT OR IGNORE INTO system_configs (config_key, config_value, description) VALUES
    ('retention_free_hours', '1', '免费文件保留小时数'),
    ('retention_paid_hours', '24', '付费文件保留小时数'),
    ('price_large_file', '5.00', '大文件解锁价格（元）'),
    ('daily_free_quota_gb', '100', '每日免费流量限额(GB)'),
    ('max_file_size_mb', '500', '单文件最大大小(MB)'),
    ('free_file_size_mb', '50', '免费文件大小上限(MB)');

-- 管理员用户表
CREATE TABLE IF NOT EXISTS admin_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    email TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME,
    is_active INTEGER DEFAULT 1,
    is_super INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_admin_username ON admin_users(username);

-- 管理员操作日志表
CREATE TABLE IF NOT EXISTS admin_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_username TEXT NOT NULL,
    action TEXT NOT NULL,
    target_table TEXT,
    target_id TEXT,
    old_value TEXT,
    new_value TEXT,
    ip_address TEXT,
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_logs_user ON admin_logs(admin_username, created_at);
CREATE INDEX IF NOT EXISTS idx_admin_logs_action ON admin_logs(action, created_at);

-- 用户反馈表
CREATE TABLE IF NOT EXISTS feedbacks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id TEXT,
    task_id TEXT,
    feedback_type TEXT CHECK(feedback_type IN ('conversion_failed', 'result_unsatisfied', 'payment_issue', 'other')),
    description TEXT NOT NULL,
    screenshot_url TEXT,
    contact_email TEXT,
    status TEXT CHECK(status IN ('pending', 'processing', 'resolved')) DEFAULT 'pending',
    admin_reply TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedbacks(status, created_at);
CREATE INDEX IF NOT EXISTS idx_feedback_client ON feedbacks(client_id);

-- 数据统计视图（每日任务统计）
CREATE VIEW IF NOT EXISTS daily_task_stats AS
SELECT
    DATE(created_at) as date,
    task_type,
    COUNT(*) as total_tasks,
    SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed_tasks,
    SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed_tasks,
    SUM(CASE WHEN is_paid=1 THEN 1 ELSE 0 END) as paid_tasks,
    AVG(CASE
        WHEN completed_at IS NOT NULL AND created_at IS NOT NULL
        THEN (julianday(completed_at) - julianday(created_at)) * 86400
        ELSE NULL
    END) as avg_processing_seconds
FROM tasks
WHERE created_at >= DATE('now', '-30 days')
GROUP BY DATE(created_at), task_type;

-- 收入统计视图
CREATE VIEW IF NOT EXISTS daily_revenue_stats AS
SELECT
    DATE(payment_time) as date,
    COUNT(*) as order_count,
    SUM(amount) as total_revenue,
    SUM(CASE WHEN status='refunded' THEN amount ELSE 0 END) as refunded_amount,
    SUM(CASE WHEN status='paid' THEN amount ELSE 0 END) as net_revenue
FROM orders
WHERE status IN ('paid', 'refunded')
  AND payment_time >= DATE('now', '-30 days')
GROUP BY DATE(payment_time);

-- 用户活跃统计视图
CREATE VIEW IF NOT EXISTS daily_user_stats AS
SELECT
    DATE(created_at) as date,
    COUNT(DISTINCT client_id) as dau,
    COUNT(*) as total_actions,
    SUM(file_size) as total_file_size_bytes
FROM tasks
WHERE created_at >= DATE('now', '-30 days')
GROUP BY DATE(created_at);

-- 插入测试数据（可选，生产环境注释掉）
-- INSERT INTO tasks (task_id, client_id, file_name, file_size, task_type, status, created_at) VALUES
--     ('test-001', 'client-001', 'test.pdf', 1024000, 'pdf2word', 'completed', DATETIME('now', '-1 hour')),
--     ('test-002', 'client-002', 'report.pdf', 5120000, 'pdf2excel', 'completed', DATETIME('now', '-2 hours'));

-- 数据库版本信息
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

INSERT INTO schema_version (version, description) VALUES (1, 'Initial schema');

-- 启用 WAL 模式（写前日志）以提升并发性能
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=-64000;  -- 64MB 缓存
PRAGMA temp_store=MEMORY;
PRAGMA busy_timeout=30000;  -- 30 秒超时

-- 完成
SELECT 'PDFShift database initialized successfully!' as message;
SELECT 'Database file: ' || database_file FROM pragma_database_list WHERE name='main';
SELECT 'Schema version: ' || MAX(version) FROM schema_version;
