# Sticker Manager PC

Windows 桌面端表情管理器。点击表情自动复制到剪贴板，`Ctrl+V` 粘贴到 QQ/微信。

## 功能

- 全局热键唤出/隐藏窗口（默认 `Ctrl+Shift+S`，可自定义）
- 点击表情 → 复制到剪贴板（静态图为位图，GIF 为文件路径）
- 系统托盘后台常驻
- 从本地文件批量导入表情包
- 从分享码 / 端到端加密链接导入
- 导出表情包到指定文件夹
- 响应式网格布局，自适应窗口大小

## 构建

```bash
flutter pub get
flutter build windows
```

产物在 `build/windows/x64/runner/Release/`，整个文件夹可直接分发运行。

## 技术栈

| 组件 | 技术 |
|------|------|
| 数据库 | SQLite (sqflite_common_ffi) |
| 图片剪贴板 | Win32 API (dart:ffi) |
| 全局热键 | hotkey_manager |
| 系统托盘 | tray_manager |
| 窗口管理 | window_manager |
| 文件选择 | file_picker |
| 加密 | pointycastle (AES-256-GCM) |
| HTTP | dio |

## 与 sticker_app 的关系

完全独立的项目，共享同一个 Go 后端，不修改 sticker_app 任何文件。
