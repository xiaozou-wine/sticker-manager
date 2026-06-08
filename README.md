# Sticker Manager

表情包管理工具，支持 Android 和 PC 端，解决 QQ/微信批量添加表情包的问题。

## 项目结构

```
server/        — Go 后端（Gin + SQLite）
sticker_app/   — Android 客户端（无障碍服务注入）
sticker_pc/    — Windows 桌面端（剪贴板复制）
vps-server/    — VPS 分享服务（端到端加密）
```

## 下载

- **PC 端**：[Releases](https://github.com/xiaozou-wine/sticker-manager/releases/tag/v1.0.0-pc) 下载 `sticker_pc_v1.0.0.zip`，解压运行 `sticker_pc.exe`
- **Android 端**：[Releases](https://github.com/xiaozou-wine/sticker-manager/releases/tag/v1.0.0-android) 下载 APK 安装

## 体验一下

- [分享链接体验](DEMO.md) — 用 Android 客户端导入加密分享链接

## 使用教程

- [基本使用 + VPS 加密分享部署](vps-server/SETUP_GUIDE.md)

## 从源码构建

```bash
# Go 后端
cd server && go run . --port 8080

# Android
cd sticker_app && flutter run

# PC
cd sticker_pc && flutter build windows

# VPS 分享服务
cd vps-server && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o sticker-vps .
```
