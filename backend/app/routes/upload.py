"""
文件上传相关 API
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import oss2
from datetime import datetime, timedelta
import base64
import json
import hmac
import hashlib

from app.config import settings

router = APIRouter()


class UploadPolicyRequest(BaseModel):
    """上传凭证请求"""

    filename: str
    size: int  # 文件大小（字节）


class UploadPolicyResponse(BaseModel):
    """上传凭证响应"""

    access_key_id: str
    policy: str
    signature: str
    dir: str
    host: str
    expire: int
    callback: str = ""


@router.post("/upload/policy", response_model=UploadPolicyResponse)
async def get_upload_policy(request: UploadPolicyRequest):
    """
    获取 OSS 上传凭证

    客户端使用此凭证直接上传文件到 OSS
    """

    # 检查文件大小
    file_size_mb = request.size / (1024 * 1024)

    if file_size_mb > settings.MAX_FILE_SIZE_MB:
        raise HTTPException(
            status_code=400,
            detail=f"文件过大，最大支持 {settings.MAX_FILE_SIZE_MB}MB",
        )

    # 生成上传路径
    now = datetime.now()
    upload_dir = f"uploads/{now.year}/{now.month:02d}/{now.day:02d}/"

    # 设置过期时间（30 分钟）
    expire_time = int((datetime.now() + timedelta(minutes=30)).timestamp())

    # 构建 Policy
    policy_dict = {
        "expiration": datetime.utcfromtimestamp(expire_time).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "conditions": [
            {"bucket": settings.OSS_BUCKET},
            ["starts-with", "$key", upload_dir],
            ["content-length-range", 0, settings.MAX_FILE_SIZE_MB * 1024 * 1024],
        ],
    }

    policy_encoded = base64.b64encode(json.dumps(policy_dict).encode("utf-8")).decode("utf-8")

    # 计算签名
    signature = base64.b64encode(
        hmac.new(
            settings.OSS_SECRET_KEY.encode("utf-8"), policy_encoded.encode("utf-8"), hashlib.sha1
        ).digest()
    ).decode("utf-8")

    # OSS 访问地址
    host = f"https://{settings.OSS_BUCKET}.{settings.OSS_ENDPOINT}"

    return UploadPolicyResponse(
        access_key_id=settings.OSS_ACCESS_KEY,
        policy=policy_encoded,
        signature=signature,
        dir=upload_dir,
        host=host,
        expire=expire_time,
    )


@router.get("/download/{task_id}")
async def download_file(task_id: str):
    """
    生成下载链接

    返回带签名的临时下载 URL
    """
    # TODO: 从数据库查询任务，获取 OSS key
    # TODO: 生成带签名的下载 URL

    # 临时实现
    auth = oss2.Auth(settings.OSS_ACCESS_KEY, settings.OSS_SECRET_KEY)
    bucket = oss2.Bucket(auth, f"https://{settings.OSS_ENDPOINT}", settings.OSS_BUCKET)

    # 生成 1 小时有效的下载链接
    oss_key = f"results/{task_id}.docx"  # 示例
    url = bucket.sign_url("GET", oss_key, 3600)

    return {"download_url": url}
