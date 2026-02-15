# 部署到 ECS 指南

本项目使用 GitHub Actions 自动部署到阿里云 ECS。

## 前置要求

1. 一台阿里云 ECS 服务器
2. 在 ECS 上安装 Nginx 或其他 Web 服务器
3. 配置 SSH 密钥认证

## 配置步骤

### 1. ECS 服务器配置

在你的 ECS 服务器上执行以下操作：

```bash
# 安装 Nginx
sudo yum install nginx -y  # CentOS/AliyunOS
# 或
sudo apt install nginx -y  # Ubuntu/Debian

# 启动 Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 创建部署目录
sudo mkdir -p /var/www/demo-app
sudo chown -R $USER:$USER /var/www/demo-app
```

### 2. Nginx 配置

创建 Nginx 配置文件 `/etc/nginx/conf.d/demo-app.conf`:

```nginx
server {
    listen 80;
    server_name your-domain.com;  # 替换为你的域名或使用 ECS 公网 IP

    root /var/www/demo-app;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # 启用 gzip 压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
```

重新加载 Nginx：
```bash
sudo nginx -t  # 测试配置
sudo systemctl reload nginx
```

### 3. 配置 GitHub Secrets

在 GitHub 仓库中设置以下 Secrets (Settings → Secrets and variables → Actions → New repository secret):

| Secret 名称 | 说明 | 示例 |
|------------|------|------|
| `ECS_HOST` | ECS 服务器 IP 地址 | `47.100.xxx.xxx` |
| `ECS_USERNAME` | SSH 登录用户名 | `root` 或 `ubuntu` |
| `ECS_SSH_KEY` | SSH 私钥内容 | 完整的私钥文件内容 |
| `ECS_PORT` | SSH 端口 | `22` |
| `ECS_TARGET_DIR` | 部署目标目录 | `/var/www/demo-app` |

### 4. 生成 SSH 密钥

如果你还没有 SSH 密钥，在本地执行：

```bash
# 生成新的 SSH 密钥对
ssh-keygen -t rsa -b 4096 -C "github-actions" -f ~/.ssh/ecs_deploy

# 将公钥添加到 ECS 服务器
ssh-copy-id -i ~/.ssh/ecs_deploy.pub your-username@your-ecs-ip

# 复制私钥内容到 GitHub Secrets
cat ~/.ssh/ecs_deploy
```

将私钥的完整内容（包括 `-----BEGIN OPENSSH PRIVATE KEY-----` 和 `-----END OPENSSH PRIVATE KEY-----`）复制到 GitHub Secrets 的 `ECS_SSH_KEY` 中。

### 5. 配置 ECS 安全组

确保 ECS 安全组开放了以下端口：
- 22 (SSH) - 用于部署
- 80 (HTTP) - 用于访问网站
- 443 (HTTPS) - 如果使用 SSL

## 部署流程

1. 提交代码到 GitHub:
   ```bash
   git add .
   git commit -m "Update: your message"
   git push origin master
   ```

2. GitHub Actions 会自动：
   - 检出代码
   - 安装依赖
   - 构建项目
   - 通过 SSH 将构建产物传输到 ECS
   - 可选：重启 Web 服务器

3. 访问你的网站：
   ```
   http://your-ecs-ip
   或
   http://your-domain.com
   ```

## 查看部署状态

在 GitHub 仓库页面：
- Actions 标签页可以查看部署进度
- 点击具体的 workflow 运行查看详细日志

## 故障排查

### 部署失败

1. 检查 GitHub Actions 日志
2. 确认所有 Secrets 配置正确
3. 检查 ECS 安全组规则
4. 测试 SSH 连接：`ssh -i your-key your-username@your-ecs-ip`

### 网站无法访问

1. 检查 Nginx 状态：`sudo systemctl status nginx`
2. 检查 Nginx 配置：`sudo nginx -t`
3. 查看 Nginx 错误日志：`sudo tail -f /var/log/nginx/error.log`
4. 确认文件已正确部署：`ls -la /var/www/demo-app`

## 本地测试

在本地运行开发服务器：
```bash
npm run dev
```

在本地构建生产版本：
```bash
npm run build
npm run preview
```

## 进阶配置

### 使用 HTTPS (推荐)

安装并配置 Let's Encrypt SSL 证书：

```bash
# 安装 certbot
sudo yum install certbot python3-certbot-nginx -y

# 获取证书
sudo certbot --nginx -d your-domain.com

# 自动续期
sudo systemctl enable certbot-renew.timer
```

### 自定义域名

1. 在域名服务商添加 A 记录指向 ECS IP
2. 更新 Nginx 配置中的 `server_name`
3. 重新加载 Nginx

### CDN 加速

考虑使用阿里云 CDN 加速静态资源访问。
