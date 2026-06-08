# Sticker Manager 使用教程

## 一、基本使用

### 创建表情包集
1. 打开 App → 首页点击 **+** 按钮
2. 从相册选择表情图片（最多 200 张）
3. 输入表情包名称 → 确认创建

### 发送表情到 QQ/微信
1. 打开表情包集 → 点击要发送的表情
2. 点击「保存到相册」
3. 打开 QQ/微信 → 从相册选择发送

### 通过分享码导入
1. 首页 → 点击「导入」
2. 输入对方给的分享码 → 点击「查找」
3. 确认表情包信息 → 点击「一键下载」

---

## 二、VPS 加密分享（进阶）

VPS 分享是**端到端加密**的：服务器只存加密数据，即使 VPS 管理员也看不到你的表情内容。

### 你需要什么
- 一台 VPS（最低配置即可，1 核 1G 足够）
- 本教程使用域名 `sticker.example.com` 作为示例

### 部署 VPS 服务

SSH 登录你的 VPS，执行以下命令：

```bash
# 1. 下载服务端程序（把链接替换为实际的二进制文件地址）
# 或者从本地 scp 上传：
# scp sticker-vps root@你的VPS:/usr/local/bin/sticker-vps

# 2. 创建数据目录和密码
mkdir -p /data/sticker-vps
echo "PASSWORD=$(openssl rand -hex 16)" > /data/sticker-vps/.env
cat /data/sticker-vps/.env
# 记下输出的密码！

# 3. 创建 systemd 服务
cat > /etc/systemd/system/sticker-vps.service << 'EOF'
[Unit]
Description=Sticker VPS Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/data/sticker-vps/.env
Environment=PORT=8080
Environment=DATA_DIR=/data/sticker-vps
ExecStart=/usr/local/bin/sticker-vps
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动
systemctl daemon-reload
systemctl enable --now sticker-vps

# 5. 验证
curl http://localhost:8080/health
# 应该输出: {"status":"ok"}
```

### 绑定域名（可选但推荐）

绑定域名后分享链接不会暴露你的 VPS IP。

**Cloudflare 设置：**
1. 添加 A 记录：`sticker` → 你的 VPS IP
2. 开启橙色云朵（代理模式）
3. SSL/TLS 模式选 **Flexible**

**VPS 安装 Nginx：**
```bash
apt install -y nginx
cat > /etc/nginx/sites-available/sticker << 'NGINX'
server {
    listen 80;
    server_name _;
    client_max_body_size 50M;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/sticker /etc/nginx/sites-enabled/sticker
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
```

验证：`curl https://你的域名/health`

---

### 分享表情包

1. 打开 App → 进入要分享的表情包集
2. 点击「分享」→ 选择 **VPS 加密分享**
3. 填写：
   - **VPS 地址**：`https://你的域名`（或 `http://你的IP:8080`）
   - **密码**：部署时设置的密码
4. 点击「加密上传到 VPS」
5. 上传完成后复制生成的分享链接，发给朋友

链接格式：`sticker://share/xxxxx#密钥`

### 导入表情包

**方式一：点击链接**
- 直接点击收到的链接，App 会自动打开并导入

**方式二：手动粘贴**
1. 打开 App → 导入
2. 粘贴链接（或点击输入框右侧的粘贴按钮）
3. 点击「查找」→ 确认信息 →「一键下载」

---

## 三、常见问题

**Q: 导入时提示"下载失败"？**
- 如果是 VPS 链接，确认 VPS 地址和端口正确
- HTTP 地址需要 App 已安装（Android 需要网络安全配置允许明文）

**Q: VPS 密码忘了？**
- SSH 到 VPS，执行 `cat /data/sticker-vps/.env` 查看

**Q: 分享链接会暴露 IP 吗？**
- 用域名（如 `https://sticker.example.com`）分享不会暴露 IP
- 直接用 `http://IP:8080` 分享会暴露

**Q: VPS 管理员能看到我的表情包吗？**
- 不能。表情包在你的手机上加密后才上传，密钥在链接的 `#` 后面，不会发送到服务器

**Q: 怎么更新服务端？**
```bash
# 上传新的 sticker-vps 二进制
scp sticker-vps root@你的VPS:/usr/local/bin/sticker-vps
# 重启服务
ssh root@你的VPS "systemctl restart sticker-vps"
```
