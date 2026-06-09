# Sticker Manager 使用教程

## 一、基本使用

### Android 端

**创建表情包集**
1. 打开 App → 首页点击 **+** 按钮
2. 从相册选择表情图片（最多 200 张，原图不压缩）
3. 输入表情包名称 → 确认创建

**发送表情到 QQ/微信**
1. 打开表情包集 → 点击要发送的表情
2. 点击「保存到相册」
3. 打开 QQ/微信 → 从相册选择发送

### PC 端

**导入表情**
1. 运行 `sticker_pc.exe`
2. 点击「添加」→ 选择本地图片文件
3. 输入名称 → 创建表情包集

**发送表情**
1. 点击表情包集进入详情
2. 点击任意表情 → 自动复制到剪贴板
3. 切到 QQ/微信聊天窗口 → `Ctrl+V` 粘贴发送
4. `Ctrl+Shift+S` 随时唤出/隐藏窗口（可在设置中修改）

**设置服务器地址**
1. 点击右上角齿轮 → 设置
2. 输入服务器地址（如 `http://你的IP:28749`）→ 保存
3. 重启应用生效

---

## 二、通过分享码导入

1. 首页 → 点击「导入」（或「从链接导入」）
2. 输入对方给的分享码 → 点击「查找」
3. 确认表情包信息 → 点击「一键下载」

---

## 三、VPS 加密分享（进阶）

VPS 分享使用**端到端加密**：服务器只存加密数据，即使 VPS 管理员也看不到你的表情内容。

加密算法：AES-256-GCM，密钥在分享链接的 `#` 后面，不会发送到服务器。

### 你需要什么

- 一台 VPS（最低配置即可，1 核 1G 足够，推荐 Ubuntu 22.04）
- SSH 登录权限（root 或 sudo）

### 方式一：直接部署

**1. 编译服务端**

在本地电脑编译（交叉编译为 Linux 二进制）：
```bash
cd vps-server
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o sticker-vps .
```

**2. 上传到 VPS**
```bash
scp sticker-vps root@你的VPS-IP:/usr/local/bin/sticker-vps
```

**3. SSH 登录 VPS 配置服务**
```bash
ssh root@你的VPS-IP

# 创建数据目录
mkdir -p /data/sticker-vps

# 生成随机密码
echo "PASSWORD=$(openssl rand -hex 16)" > /data/sticker-vps/.env
cat /data/sticker-vps/.env
# 记下输出的 PASSWORD=xxx，分享时需要用到
```

**4. 创建 systemd 服务**
```bash
cat > /etc/systemd/system/sticker-vps.service << 'EOF'
[Unit]
Description=Sticker VPS Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/data/sticker-vps/.env
Environment=PORT=28749
Environment=DATA_DIR=/data/sticker-vps
ExecStart=/usr/local/bin/sticker-vps
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sticker-vps
```

**5. 验证服务运行**
```bash
curl http://localhost:28749/health
# 应该输出: {"status":"ok"}
```

**6. 开放防火墙端口**
```bash
# Ubuntu/Debian (ufw)
ufw allow 28749/tcp
ufw reload

# CentOS/RHEL (firewalld)
firewall-cmd --permanent --add-port=28749/tcp
firewall-cmd --reload
```

外网验证：`curl http://你的VPS-IP:28749/health`

### 方式二：Docker 部署

```bash
# 上传项目文件到 VPS
scp -r vps-server/ root@你的VPS-IP:/opt/sticker-vps/

# SSH 登录 VPS
ssh root@你的VPS-IP
cd /opt/sticker-vps

# 生成密码
echo "PASSWORD=$(openssl rand -hex 16)" > .env
cat .env
# 记下密码

# 启动
docker compose up -d

# 验证
curl http://localhost:28749/health
```

### 绑定域名（可选但推荐）

绑定域名后分享链接不会暴露你的 VPS IP。

**方式 A：Cloudflare 代理（最简单）**

1. 修改对外端口为 80（Cloudflare 只代理 80/443）：
   ```bash
   # 直接部署：修改 systemd 服务
   sed -i 's/PORT=28749/PORT=80/' /etc/systemd/system/sticker-vps.service
   systemctl daemon-reload && systemctl restart sticker-vps

   # Docker 部署：修改 .env 文件
   echo "PORT=80" >> .env
   docker compose up -d
   ```
2. Cloudflare 添加 A 记录：`sticker` → 你的 VPS IP
3. 开启橙色云朵（代理模式）
4. SSL/TLS 模式选 **Flexible**
5. 访问 `https://sticker.你的域名/health` 验证

**方式 B：Nginx + Let's Encrypt（自签证书）**

```bash
# 安装 Nginx 和 certbot
apt install -y nginx certbot python3-certbot-nginx

# 先配置 Nginx（拒绝直接 IP 访问，只允许域名访问）
cat > /etc/nginx/sites-available/sticker << 'NGINX'
server {
    listen 80 default_server;
    server_name _;
    return 444;
}

server {
    listen 80;
    server_name sticker.你的域名.com;
    client_max_body_size 500M;

    location / {
        proxy_pass http://127.0.0.1:28749;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/sticker /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# 申请证书
certbot --nginx -d sticker.你的域名.com

# 验证
curl https://sticker.你的域名.com/health
```

> **安全提示**：Nginx 中 `server_name _` + `return 444` 会拒绝所有非域名的直接 IP 访问，防止泄露真实 IP。`default_server` 只需在一个 server 块中设置。

---

### 分享表情包

1. 打开 App → 进入要分享的表情包集
2. 点击「分享」→ 选择 **VPS 加密分享**
3. 填写：
   - **VPS 地址**：`https://sticker.你的域名.com`（或 `http://VPS-IP:28749`）
   - **密码**：部署时生成的密码
4. 点击「加密上传到 VPS」
5. 上传完成后复制生成的分享链接，发给朋友

链接格式：`sticker://share/base64编码#加密密钥`

### 导入表情包

**方式一：点击链接**
- 直接点击收到的链接，App 会自动打开并导入

**方式二：手动粘贴**
1. 打开 App → 导入
2. 粘贴链接（或点击输入框右侧的粘贴按钮）
3. 点击「查找」→ 确认信息 →「一键下载」

---

## 四、常见问题

**Q: 导入时提示"查找失败"？**
- 检查服务器地址是否正确，端口是否开放
- PC 端需要在设置中配置服务器地址

**Q: VPS 密码忘了？**
- SSH 到 VPS，执行 `cat /data/sticker-vps/.env` 查看

**Q: 分享链接会暴露 IP 吗？**
- 用域名分享不会暴露 IP
- 直接用 `http://IP:28749` 分享会暴露

**Q: VPS 管理员能看到我的表情包吗？**
- 不能。表情包在本地加密后才上传，密钥在链接的 `#` 后面，不会发送到服务器

**Q: 怎么更新服务端？**
```bash
# 上传新的二进制
scp sticker-vps root@你的VPS:/usr/local/bin/sticker-vps
# 重启服务
ssh root@你的VPS "systemctl restart sticker-vps"
```
