"""
Celery 应用配置
"""
from celery import Celery
from celery.schedules import crontab
from app.config import settings

# 创建 Celery 应用
celery_app = Celery(
    "pdfshift",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
    include=["app.tasks"],
)

# Celery 配置
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Asia/Shanghai",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=30 * 60,  # 30 分钟超时
    task_soft_time_limit=25 * 60,  # 25 分钟软超时
    worker_prefetch_multiplier=1,  # 每次只取一个任务
    worker_max_tasks_per_child=50,  # 每个 worker 最多处理 50 个任务后重启
)

# 定时任务配置
celery_app.conf.beat_schedule = {
    # 每 10 分钟清理过期文件
    "cleanup-expired-files": {
        "task": "app.tasks.cleanup_expired_files",
        "schedule": crontab(minute="*/10"),
    },
    # 每小时统计数据
    "hourly-stats": {
        "task": "app.tasks.generate_hourly_stats",
        "schedule": crontab(minute=0),
    },
}
