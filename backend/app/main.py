"""
PDFShift FastAPI 主应用
"""
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
import structlog
from contextlib import asynccontextmanager

from app.config import settings
from app.database import init_db
from app.routes import tasks, upload, admin, system

# 配置日志
logger = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    # 启动时
    logger.info("Application starting", env=settings.APP_ENV)
    init_db()
    logger.info("Database initialized")

    yield

    # 关闭时
    logger.info("Application shutting down")


# 创建 FastAPI 应用
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="在线 PDF 处理平台",
    lifespan=lifespan,
    docs_url="/api/docs" if settings.APP_DEBUG else None,
    redoc_url="/api/redoc" if settings.APP_DEBUG else None,
)

# CORS 中间件
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.APP_DEBUG else ["https://coreshift.cn", "https://test.coreshift.cn"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)

# 受信任主机中间件
if not settings.APP_DEBUG:
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=["coreshift.cn", "*.coreshift.cn", "localhost", "127.0.0.1"],
    )


# 全局异常处理
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """全局异常处理器"""
    logger.error(
        "Unhandled exception",
        path=request.url.path,
        method=request.method,
        error=str(exc),
    )

    return JSONResponse(
        status_code=500,
        content={
            "code": "INTERNAL_ERROR",
            "message": "服务器内部错误" if not settings.APP_DEBUG else str(exc),
        },
    )


# 注册路由
app.include_router(tasks.router, prefix="/api/v1", tags=["tasks"])
app.include_router(upload.router, prefix="/api/v1", tags=["upload"])
app.include_router(admin.router, prefix="/admin", tags=["admin"])
app.include_router(system.router, prefix="/api/v1", tags=["system"])


# 健康检查
@app.get("/health")
async def health_check():
    """健康检查端点"""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "env": settings.APP_ENV,
    }


@app.get("/")
async def root():
    """根路径"""
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "message": "PDFShift API is running",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.APP_DEBUG,
    )
