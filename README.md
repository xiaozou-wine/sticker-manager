# Sticker Manager

表情包管理应用（Flutter + Go），批量管理表情包并发送到 QQ/微信。

## 项目结构

```
server/        — Go 后端（Gin + SQLite）
sticker_app/   — Flutter Android 客户端
sticker_pc/    — Flutter Windows 桌面端
vps-server/    — VPS 分享服务（端到端加密，单二进制部署）
```

## 功能

**Android 端（sticker_app）：**
- 从相册批量导入表情（最多 200 张，原图不压缩）
- 无障碍服务直接在 QQ/微信聊天窗口注入表情
- 保存到手机相册，通过 QQ/微信相册发送
- 服务器分享码 / VPS 端到端加密分享
- `sticker://` 深度链接，点击直接导入

**PC 端（sticker_pc）：**
- 全局热键唤出窗口（`Ctrl+Shift+S`，可自定义）
- 点击表情复制到剪贴板，`Ctrl+V` 粘贴到 QQ/微信
- 系统托盘后台常驻
- 从本地文件批量导入
- 分享码 / 加密链接导入
- 导出表情包到指定文件夹

## 快速开始

**Go 后端：**
```bash
cd server && go build -o sticker-server . && ./sticker-server --port 8080
```

**Android 客户端：**
```bash
cd sticker_app && flutter run
```

**PC 桌面端：**
```bash
cd sticker_pc && flutter build windows
```

**VPS 分享服务：**
```bash
cd vps-server
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o sticker-vps .
```
详见 [vps-server/SETUP_GUIDE.md](vps-server/SETUP_GUIDE.md)
