"""
任务相关 API 路由
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timedelta
import uuid

from app.database import get_db
from app.models import Task
from app.config import settings
from app.celery_app import convert_pdf_task
from pydantic import BaseModel

router = APIRouter()


# Pydantic 模型
class TaskCreate(BaseModel):
    """创建任务请求"""

    oss_key: str
    task_type: str  # pdf2word, pdf2excel, pdf2ppt, merge, split
    file_name: str
    file_size: int
    client_id: str
    options: Optional[dict] = None


class TaskResponse(BaseModel):
    """任务响应"""

    task_id: str
    status: str
    file_name: Optional[str] = None
    created_at: datetime
    completed_at: Optional[datetime] = None
    download_url: Optional[str] = None
    error_msg: Optional[str] = None

    class Config:
        from_attributes = True


@router.post("/tasks", response_model=TaskResponse)
async def create_task(task_data: TaskCreate, db: Session = Depends(get_db)):
    """
    创建转换任务

    - **oss_key**: OSS 文件路径
    - **task_type**: 任务类型 (pdf2word, pdf2excel, pdf2ppt, merge, split)
    - **file_name**: 文件名
    - **file_size**: 文件大小（字节）
    - **client_id**: 客户端 ID
    """

    # 检查文件大小限制
    file_size_mb = task_data.file_size / (1024 * 1024)

    if file_size_mb > settings.MAX_FILE_SIZE_MB:
        raise HTTPException(
            status_code=400,
            detail=f"文件过大，最大支持 {settings.MAX_FILE_SIZE_MB}MB",
        )

    # 检查是否需要付费
    is_paid = False
    if file_size_mb > settings.FREE_FILE_SIZE_MB:
        # 这里应该检查 orders 表，查看是否已付费
        # 简化处理：需要前端先调用支付接口
        raise HTTPException(
            status_code=402,
            detail=f"文件大小超过免费限制 ({settings.FREE_FILE_SIZE_MB}MB)，请先完成支付",
        )

    # 创建任务
    task_id = str(uuid.uuid4())
    task = Task(
        task_id=task_id,
        client_id=task_data.client_id,
        file_name=task_data.file_name,
        file_size=task_data.file_size,
        oss_key_source=task_data.oss_key,
        task_type=task_data.task_type,
        status="pending",
        is_paid=is_paid,
        created_at=datetime.now(),
        expire_at=datetime.now()
        + timedelta(hours=settings.RETENTION_PAID_HOURS if is_paid else settings.RETENTION_FREE_HOURS),
    )

    db.add(task)
    db.commit()
    db.refresh(task)

    # 提交到 Celery 队列
    convert_pdf_task.delay(task_id, task_data.oss_key, task_data.task_type)

    return task


@router.get("/tasks/{task_id}", response_model=TaskResponse)
async def get_task(task_id: str, db: Session = Depends(get_db)):
    """
    查询任务状态

    返回任务详情，包括处理状态和下载链接
    """
    task = db.query(Task).filter(Task.task_id == task_id).first()

    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")

    # 检查是否过期
    if task.expire_at and task.expire_at < datetime.now():
        if task.status != "expired":
            task.status = "expired"
            db.commit()

        raise HTTPException(status_code=410, detail="文件已过期")

    response = TaskResponse(
        task_id=task.task_id,
        status=task.status,
        file_name=task.file_name,
        created_at=task.created_at,
        completed_at=task.completed_at,
        error_msg=task.error_msg,
    )

    # 如果任务完成，生成下载链接
    if task.status == "completed" and task.oss_key_result:
        # TODO: 生成带签名的 OSS 下载链接
        response.download_url = f"/api/v1/download/{task.task_id}"

    return response


@router.get("/history", response_model=List[TaskResponse])
async def get_history(
    client_id: str = Query(..., description="客户端 ID"),
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """
    查询历史记录

    仅返回付费用户的历史记录
    """
    tasks = (
        db.query(Task)
        .filter(Task.client_id == client_id, Task.is_paid == True)
        .order_by(Task.created_at.desc())
        .limit(limit)
        .all()
    )

    return [
        TaskResponse(
            task_id=t.task_id,
            status=t.status,
            file_name=t.file_name,
            created_at=t.created_at,
            completed_at=t.completed_at,
        )
        for t in tasks
    ]


@router.delete("/tasks/{task_id}")
async def delete_task(task_id: str, client_id: str = Query(...), db: Session = Depends(get_db)):
    """
    删除任务

    用户可以主动删除自己的任务
    """
    task = db.query(Task).filter(Task.task_id == task_id, Task.client_id == client_id).first()

    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")

    # 更新状态为 expired
    task.status = "expired"
    db.commit()

    return {"message": "任务已删除"}
