"""
管理后台 API
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from sqlalchemy import func
from pydantic import BaseModel
from datetime import datetime, timedelta
from passlib.context import CryptContext
from jose import jwt, JWTError

from app.database import get_db
from app.models import Task, Order, SystemConfig, AdminLog
from app.config import settings

router = APIRouter()
security = HTTPBearer()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


# Pydantic 模型
class AdminLogin(BaseModel):
    """管理员登录"""

    username: str
    password: str


class TokenResponse(BaseModel):
    """Token 响应"""

    access_token: str
    token_type: str = "bearer"


class DailyStats(BaseModel):
    """每日统计"""

    date: str
    total_tasks: int
    completed_tasks: int
    failed_tasks: int
    paid_tasks: int
    total_revenue: float


class ConfigUpdate(BaseModel):
    """配置更新"""

    config_key: str
    config_value: str


# 认证相关
def verify_admin(username: str, password: str) -> bool:
    """验证管理员凭据"""
    if username != settings.ADMIN_USERNAME:
        return False
    # 这里简化处理，实际应该从数据库读取并验证哈希密码
    return password == settings.ADMIN_PASSWORD


def create_access_token(data: dict) -> str:
    """创建 JWT Token"""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings.JWT_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """验证 Token"""
    try:
        payload = jwt.decode(credentials.credentials, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        username = payload.get("sub")
        role = payload.get("role")

        if username is None or role != "admin":
            raise HTTPException(status_code=401, detail="Invalid authentication")

        return username
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


# 路由
@router.post("/login", response_model=TokenResponse)
async def admin_login(login_data: AdminLogin):
    """管理员登录"""
    if not verify_admin(login_data.username, login_data.password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")

    access_token = create_access_token({"sub": login_data.username, "role": "admin"})

    return TokenResponse(access_token=access_token)


@router.get("/stats/daily")
async def get_daily_stats(
    days: int = 7, admin: str = Depends(get_current_admin), db: Session = Depends(get_db)
):
    """获取每日统计"""

    start_date = datetime.now() - timedelta(days=days)

    # 查询任务统计
    results = (
        db.query(
            func.date(Task.created_at).label("date"),
            func.count(Task.task_id).label("total_tasks"),
            func.sum(func.case((Task.status == "completed", 1), else_=0)).label("completed_tasks"),
            func.sum(func.case((Task.status == "failed", 1), else_=0)).label("failed_tasks"),
            func.sum(func.case((Task.is_paid == True, 1), else_=0)).label("paid_tasks"),
        )
        .filter(Task.created_at >= start_date)
        .group_by(func.date(Task.created_at))
        .all()
    )

    return [
        {
            "date": str(r.date),
            "total_tasks": r.total_tasks,
            "completed_tasks": r.completed_tasks or 0,
            "failed_tasks": r.failed_tasks or 0,
            "paid_tasks": r.paid_tasks or 0,
        }
        for r in results
    ]


@router.get("/stats/revenue")
async def get_revenue_stats(admin: str = Depends(get_current_admin), db: Session = Depends(get_db)):
    """获取收入统计"""

    # 查询订单统计
    result = db.query(
        func.count(Order.order_id).label("total_orders"),
        func.sum(func.case((Order.status == "paid", Order.amount), else_=0)).label("total_revenue"),
        func.sum(func.case((Order.status == "refunded", Order.amount), else_=0)).label("refunded_amount"),
    ).first()

    return {
        "total_orders": result.total_orders or 0,
        "total_revenue": float(result.total_revenue or 0),
        "refunded_amount": float(result.refunded_amount or 0),
        "net_revenue": float((result.total_revenue or 0) - (result.refunded_amount or 0)),
    }


@router.get("/configs")
async def get_configs(admin: str = Depends(get_current_admin), db: Session = Depends(get_db)):
    """获取系统配置"""

    configs = db.query(SystemConfig).all()

    return [
        {
            "config_key": c.config_key,
            "config_value": c.config_value,
            "description": c.description,
        }
        for c in configs
    ]


@router.put("/configs")
async def update_config(
    config: ConfigUpdate,
    request: Request,
    admin: str = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """更新系统配置"""

    existing = db.query(SystemConfig).filter(SystemConfig.config_key == config.config_key).first()

    if not existing:
        raise HTTPException(status_code=404, detail="配置项不存在")

    old_value = existing.config_value
    existing.config_value = config.config_value
    existing.updated_at = datetime.now()

    # 记录操作日志
    log = AdminLog(
        admin_username=admin,
        action="UPDATE_CONFIG",
        target_table="system_configs",
        target_id=config.config_key,
        old_value=old_value,
        new_value=config.config_value,
        ip_address=request.client.host if request.client else None,
    )

    db.add(log)
    db.commit()

    return {"message": "配置已更新"}


@router.get("/tasks")
async def get_all_tasks(
    status: str = None,
    limit: int = 50,
    admin: str = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """查询所有任务"""

    query = db.query(Task)

    if status:
        query = query.filter(Task.status == status)

    tasks = query.order_by(Task.created_at.desc()).limit(limit).all()

    return [
        {
            "task_id": t.task_id,
            "client_id": t.client_id,
            "file_name": t.file_name,
            "status": t.status,
            "task_type": t.task_type,
            "created_at": t.created_at,
            "completed_at": t.completed_at,
        }
        for t in tasks
    ]


@router.get("/logs")
async def get_logs(limit: int = 100, admin: str = Depends(get_current_admin), db: Session = Depends(get_db)):
    """查询操作日志"""

    logs = db.query(AdminLog).order_by(AdminLog.created_at.desc()).limit(limit).all()

    return [
        {
            "id": log.id,
            "admin_username": log.admin_username,
            "action": log.action,
            "target_table": log.target_table,
            "target_id": log.target_id,
            "ip_address": log.ip_address,
            "created_at": log.created_at,
        }
        for log in logs
    ]
