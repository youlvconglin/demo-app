"""
API 测试
"""
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_check():
    """测试健康检查"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_root():
    """测试根路径"""
    response = client.get("/")
    assert response.status_code == 200
    assert "PDFShift" in response.json()["app"]


def test_upload_policy():
    """测试获取上传凭证"""
    response = client.post(
        "/api/v1/upload/policy", json={"filename": "test.pdf", "size": 1024000}
    )
    assert response.status_code == 200
    assert "access_key_id" in response.json()
    assert "policy" in response.json()


def test_upload_policy_file_too_large():
    """测试文件过大"""
    response = client.post(
        "/api/v1/upload/policy", json={"filename": "test.pdf", "size": 600 * 1024 * 1024}  # 600MB
    )
    assert response.status_code == 400


def test_admin_login():
    """测试管理员登录"""
    # 使用错误密码
    response = client.post("/admin/login", json={"username": "admin", "password": "wrong"})
    assert response.status_code == 401

    # 使用正确密码（需要配置环境变量）
    # response = client.post("/admin/login", json={
    #     "username": "admin",
    #     "password": "correct_password"
    # })
    # assert response.status_code == 200
    # assert "access_token" in response.json()
