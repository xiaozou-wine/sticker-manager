# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Sticker Manager — 表情包管理应用（Flutter + Go），解决 QQ/微信批量添加表情包的问题。支持创建表情包集、VPS 端到端加密分享、保存到手机相册。

## 项目结构

```
server/           — Go 后端（Gin + SQLite WAL 模式）
  main.go         — 入口，flag 参数解析，路由注册
  handler/        — HTTP handlers
  service/        — 业务逻辑（分享码生成、文件管理）
  store/          — SQLite CRUD（modernc.org/sqlite 纯 Go 驱动）
  model/          — StickerPack、Sticker

sticker_app/      — Flutter 客户端（Android 为主）
  lib/
    main.dart     — 入口，Provider 注册，深链接处理
    config.dart   — API_BASE_URL 编译时配置
    models/       — 双序列化：fromMap（本地 DB）/ fromApiMap（API）
    providers/    — PackProvider、StickerProvider
    services/
      api_service.dart       — Dio HTTP 客户端（含 VPS 支持、Dio 缓存）
      storage_service.dart   — sqflite 本地存储
      crypto_service.dart    — AES-256-GCM 加解密 + sticker:// 链接
      gallery_save_service.dart — 保存到系统相册（gal 包）
      download_service.dart  — 远程包下载
    screens/
      home_screen.dart       — 表情包集列表
      pack_detail_screen.dart — 详情 + 保存到相册
      import_link_screen.dart — 导入（分享码 / 加密链接）
      share_pack_screen.dart  — 分享（服务器码 / VPS 加密）
      accessibility_settings_screen.dart — 无障碍设置

  android/.../kotlin/
    StickerAccessibilityService.kt — 无障碍服务
    OverlayManager.kt              — 悬浮窗（TYPE_ACCESSIBILITY_OVERLAY）
    TriggerButton.kt               — 悬浮触发按钮
    StickerKeyboardService.kt      — 自定义键盘（commitContent API）
    StickerDataHelper.kt           — Kotlin 直读 Flutter sqflite
    KeepAliveService.kt            — 前台服务保活
    BootReceiver.kt                — 开机自启
    MainActivity.kt                — MethodChannel + 电池优化
```

## 常用命令

```bash
# Go 后端
cd server && go build -o sticker-server . && ./sticker-server --port 8080

# Flutter 客户端
cd sticker_app
flutter run --dart-define=API_BASE_URL=http://your-server:8080
flutter build apk
flutter test
flutter analyze
```

## 关键技术决策

- **表情发送方案**：保存到系统相册（gal 包）→ QQ/微信原生相册选发。悬浮窗/键盘方案代码保留但非主力。
- **VPS 加密分享**：AES-256-GCM，密钥在 `sticker://share/...#key` 的 `#` 后，不上传服务器。
- **保活**：KeepAliveService 前台服务 + 请求忽略电池优化 + 开机自启。
- **数据库**：Go 用 modernc.org/sqlite（纯 Go），Flutter 用 sqflite，Kotlin 侧直接读 sqflite DB 文件。
- **悬浮窗类型**：`TYPE_ACCESSIBILITY_OVERLAY`（无需 SYSTEM_ALERT_WINDOW 权限，更省电）。

## 注意事项

- `accessibility_service_config.xml` 中 `canRetrieveWindowContent` 必须为 `true`，否则 `rootInActiveWindow` 返回 null
- 悬浮窗显示时 `rootInActiveWindow` 指向悬浮窗而非目标 App，发送前必须先隐藏
- 不要监听 `TYPE_WINDOW_CONTENT_CHANGED`，频率过高导致严重耗电
- StickerDataHelper 的 DB 操作必须用 try-finally 确保 close
