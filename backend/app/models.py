"""
数据库模型
"""
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, Text
from sqlalchemy.sql import func
from app.database import Base


class Task(Base):
    """任务表"""

    __tablename__ = "tasks"

    task_id = Column(String(64), primary_key=True)
    client_id = Column(String(64), nullable=False, index=True)
    file_name = Column(String(255))
    file_size = Column(Integer)
    file_key_source = Column(String(255))  # 源文件相对路径
    file_key_result = Column(String(255))  # 结果文件相对路径
    task_type = Column(String(50))  # pdf2word, pdf2excel, pdf2ppt, merge, split
    status = Column(String(50), default="pending", index=True)  # pending, processing, completed, failed, expired
    is_paid = Column(Boolean, default=False)
    error_msg = Column(Text)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    completed_at = Column(DateTime)
    expire_at = Column(DateTime, index=True)


class Order(Base):
    """订单表"""

    __tablename__ = "orders"

    order_id = Column(String(64), primary_key=True)
    client_id = Column(String(64), index=True)
    task_id = Column(String(64))
    amount = Column(Float)
    status = Column(String(50), default="unpaid", index=True)  # unpaid, paid, refunded
    payment_time = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())


class SystemConfig(Base):
    """系统配置表"""

    __tablename__ = "system_configs"

    config_key = Column(String(50), primary_key=True)
    config_value = Column(String(255))
    description = Column(String(100))
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class AdminUser(Base):
    """管理员用户表"""

    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    email = Column(String(100))
    created_at = Column(DateTime, server_default=func.now())
    last_login = Column(DateTime)
    is_active = Column(Boolean, default=True)
    is_super = Column(Boolean, default=False)


class AdminLog(Base):
    """管理员操作日志表"""

    __tablename__ = "admin_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    admin_username = Column(String(50), nullable=False, index=True)
    action = Column(String(100), nullable=False, index=True)
    target_table = Column(String(50))
    target_id = Column(String(64))
    old_value = Column(Text)
    new_value = Column(Text)
    ip_address = Column(String(45))
    user_agent = Column(String(255))
    created_at = Column(DateTime, server_default=func.now(), index=True)


class Feedback(Base):
    """用户反馈表"""

    __tablename__ = "feedbacks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    client_id = Column(String(64), index=True)
    task_id = Column(String(64))
    feedback_type = Column(String(50))  # conversion_failed, result_unsatisfied, payment_issue, other
    description = Column(Text, nullable=False)
    screenshot_url = Column(String(255))
    contact_email = Column(String(100))
    status = Column(String(50), default="pending", index=True)  # pending, processing, resolved
    admin_reply = Column(Text)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
