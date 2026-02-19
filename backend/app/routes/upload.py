"""
文件上传相关 API
"""
from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from pydantic import BaseModel
from datetime import datetime
import os
import uuid
import shutil

from app.config import settings

router = APIRouter()


class UploadResponse(BaseModel):
    """上传响应"""

    file_key: str
    filename: str
    size: int
    upload_time: str


@router.post("/upload", response_model=UploadResponse)
async def upload_file(file: UploadFile = File(...)):
    """
    上传文件到本地存储

    Args:
        file: 上传的文件

    Returns:
        文件信息
    """

    # 检查文件大小
    file.file.seek(0, 2)  # 移动到文件末尾
    file_size = file.file.tell()
    file.file.seek(0)  # 重置到开头

    file_size_mb = file_size / (1024 * 1024)

    if file_size_mb > settings.MAX_FILE_SIZE_MB:
        raise HTTPException(
            status_code=400,
            detail=f"文件过大，最大支持 {settings.MAX_FILE_SIZE_MB}MB",
        )

    # 生成文件存储路径
    now = datetime.now()
    upload_dir = os.path.join(
        settings.STORAGE_BASE_PATH,
        "uploads",
        str(now.year),
        f"{now.month:02d}",
        f"{now.day:02d}"
    )

    # 确保目录存在
    os.makedirs(upload_dir, exist_ok=True)

    # 生成唯一文件名
    file_ext = os.path.splitext(file.filename)[1]
    file_key = f"{uuid.uuid4().hex}{file_ext}"
    file_path = os.path.join(upload_dir, file_key)

    # 保存文件
    try:
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"文件保存失败: {str(e)}")

    # 返回相对路径作为 file_key
    relative_path = os.path.relpath(file_path, settings.STORAGE_BASE_PATH)

    return UploadResponse(
        file_key=relative_path.replace("\\", "/"),  # 统一使用斜杠
        filename=file.filename,
        size=file_size,
        upload_time=now.isoformat()
    )


@router.get("/download/{task_id}")
async def download_file(task_id: str):
    """
    下载转换后的文件

    Args:
        task_id: 任务 ID

    Returns:
        文件下载响应
    """
    from app.database import SessionLocal
    from app.models import Task

    db = SessionLocal()

    try:
        # 查询任务
        task = db.query(Task).filter(Task.task_id == task_id).first()

        if not task:
            raise HTTPException(status_code=404, detail="任务不存在")

        if task.status != "completed":
            raise HTTPException(status_code=400, detail="任务未完成")

        # 检查文件是否过期
        if task.expire_at and task.expire_at < datetime.now():
            raise HTTPException(status_code=410, detail="文件已过期")

        # 构建文件路径
        file_path = os.path.join(settings.STORAGE_BASE_PATH, task.file_key_result)

        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="文件不存在")

        # 获取文件名
        filename = f"{task_id}.{task.file_key_result.split('.')[-1]}"

        return FileResponse(
            path=file_path,
            filename=filename,
            media_type="application/octet-stream"
        )

    finally:
        db.close()
