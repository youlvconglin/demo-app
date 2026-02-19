"""
系统相关 API
"""
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class HealthResponse(BaseModel):
    """健康检查响应"""

    status: str
    timestamp: str


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """系统健康检查"""
    from datetime import datetime

    return HealthResponse(status="healthy", timestamp=datetime.now().isoformat())
