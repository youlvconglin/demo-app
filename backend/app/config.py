"""
应用配置文件
"""
import os
from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """应用配置"""

    # 应用信息
    APP_NAME: str = "PDFShift"
    APP_VERSION: str = "1.0.0"
    APP_ENV: str = "production"  # staging, production
    APP_DEBUG: bool = False

    # API 配置
    API_PORT: int = 8000
    API_HOST: str = "127.0.0.1"

    # 数据库配置
    DATABASE_URL: str = "sqlite:////opt/pdfshift/data/pdfshift.db"

    # Redis 配置
    REDIS_URL: str = "redis://localhost:6379/0"

    # 文件存储配置
    STORAGE_TYPE: str = "local"  # local 或 oss
    STORAGE_BASE_PATH: str = "/opt/pdfshift/storage"  # 本地存储根目录

    # OSS 配置（可选，仅当 STORAGE_TYPE=oss 时使用）
    OSS_ACCESS_KEY: Optional[str] = None
    OSS_SECRET_KEY: Optional[str] = None
    OSS_BUCKET: Optional[str] = None
    OSS_ENDPOINT: str = "oss-cn-hangzhou.aliyuncs.com"

    # JWT 配置
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60 * 24  # 24 小时

    # 管理员配置
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str

    # 文件限制配置
    MAX_FILE_SIZE_MB: int = 500
    FREE_FILE_SIZE_MB: int = 50

    # 文件保留时间（小时）
    RETENTION_FREE_HOURS: int = 1
    RETENTION_PAID_HOURS: int = 24

    # 支付配置
    ALIPAY_APP_ID: Optional[str] = None
    ALIPAY_PRIVATE_KEY: Optional[str] = None
    ALIPAY_PUBLIC_KEY: Optional[str] = None

    # Celery 配置
    CELERY_BROKER_URL: str = "redis://localhost:6379/0"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/0"

    class Config:
        env_file = ".env"
        case_sensitive = True


# 创建全局配置实例
settings = Settings()
