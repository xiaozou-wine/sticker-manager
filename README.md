# Sticker Manager

表情包管理应用，解决 QQ/微信批量添加表情包的问题。

## 功能

- 创建表情包集，从相册批量导入
- 保存表情到手机相册，通过 QQ/微信原生相册发送
- **服务器分享码**：上传到中央服务器，生成分享码
- **VPS 加密分享**：端到端加密，上传到自己的 VPS，生成 `sticker://share/` 链接
- 无障碍服务集成（QQ/微信悬浮窗）

## 项目结构

```
server/           — Go 后端（Gin + SQLite）
sticker_app/      — Flutter Android 客户端
vps-server/       — VPS 分享服务（独立部署，单二进制）
```

## 快速开始

### VPS 分享服务部署

```bash
cd vps-server
# 交叉编译
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o sticker-vps .

# 上传到 VPS
scp sticker-vps root@your-vps:/usr/local/bin/sticker-vps

# SSH 到 VPS 部署
ssh root@your-vps
mkdir -p /data/sticker-vps
echo "PASSWORD=$(openssl rand -hex 16)" > /data/sticker-vps/.env
# 创建 systemd 服务（详见 vps-server/SETUP_GUIDE.md）
```

### Flutter 客户端

```bash
cd sticker_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://your-server:8080
```

### Go 后端

```bash
cd server
go build -o sticker-server .
./sticker-server --port 8080
```

## 端到端加密

VPS 分享使用 AES-256-GCM 加密：

```
sticker://share/{base64url(server|packId|code)}#{base64url(key)}
```

`#` 后面的密钥不会发送到服务器，VPS 管理员也无法查看表情内容。

## 部署教程

详见 [vps-server/SETUP_GUIDE.md](vps-server/SETUP_GUIDE.md)
