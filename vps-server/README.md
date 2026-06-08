# Sticker VPS 分享服务

轻量级表情包分享服务，支持端到端加密。单二进制 + SQLite，内存占用 ~2MB。

## 快速部署

```bash
# 1. 上传二进制到 VPS
scp sticker-vps root@your-vps:/usr/local/bin/sticker-vps

# 2. SSH 到 VPS，创建数据目录和密码
ssh root@your-vps
chmod +x /usr/local/bin/sticker-vps
mkdir -p /data/sticker-vps
echo "PASSWORD=$(openssl rand -hex 16)" > /data/sticker-vps/.env
cat /data/sticker-vps/.env  # 记住密码

# 3. 创建 systemd 服务
cat > /etc/systemd/system/sticker-vps.service << 'EOF'
[Unit]
Description=Sticker VPS Sharing Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/data/sticker-vps/.env
Environment=PORT=8080
Environment=DATA_DIR=/data/sticker-vps
ExecStart=/usr/local/bin/sticker-vps
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动
systemctl daemon-reload
systemctl enable --now sticker-vps

# 5. 验证
curl http://localhost:8080/health
```

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `PASSWORD` | (必填) | 上传/删除密码 |
| `PORT` | `8080` | 监听端口 |
| `DATA_DIR` | `./data` | 数据目录（SQLite + 表情文件） |

## API

| 端点 | 方法 | 认证 | 说明 |
|---|---|---|---|
| `/api/packs` | POST | 需要 | 上传表情包（multipart） |
| `/api/packs/:code` | GET | 不需要 | 查看包信息 |
| `/api/packs/:code/stickers` | GET | 不需要 | 获取表情列表 |
| `/api/stickers/:id/file` | GET | 不需要 | 下载表情文件 |
| `/api/packs/:code` | DELETE | 需要 | 删除表情包 |
| `/health` | GET | 不需要 | 健康检查 |

认证方式：Header `X-Auth-Token: {password}`

## 内存占用

约 1.7MB（1 核 957MB RAM 的 VPS 上实测）。
