# 表情包项目审计问题清单

审计日期: 2026-06-08 | 上次更新: 2026-06-08 (第15轮 - 无障碍子系统移除)

## 项目状态
无障碍/保活子系统已完全移除。项目回归纯表情包管理 + 相册保存。

## Bug 追踪
- [x] **BUG-1~34** 全部已修复（含随代码删除一起清除）
- [ ] **BUG-35 (P2)** `RequestType.common` 允许非图片文件 — `gallery_picker_screen.dart:134` 用 `RequestType.common` 替代 `RequestType.image`，允许用户选择视频/音频文件，`_confirmSelection` 不过滤类型。**修复**: 改回 `RequestType.image`

## 已删除的代码（第15轮）
| 文件 | 行数 | 说明 |
|------|------|------|
| StickerAccessibilityService.kt | -111 | 无障碍服务 |
| StickerDataHelper.kt | -185 | 直接读取 Flutter DB |
| KeepAliveService.kt | -90 | 前台保活服务 |
| BootReceiver.kt | -20 | 开机自启 |
| accessibility_settings_screen.dart | -294 | 设置页面 |
| ui_snapshot_screen.dart | -309 | UI 节点快照 |
| accessibility_service.dart | -70 | MethodChannel 接口 |
| accessibility_service_config.xml | -11 | 服务配置 |
| AndroidManifest.xml | -35 | 权限/服务声明 |
| MainActivity.kt | -123 | 仅保留 saveToGallery |

**合计删除 ~1250 行代码**，零残留引用。

## 保留功能
- 表情包管理（CRUD）
- 分享链接导入（sticker:// deep link + AES-256-GCM 加密）
- VPS 端到端加密分享
- 保存到相册（saveToGallery）
- 桌面支持（window_manager + hotkey + tray）
