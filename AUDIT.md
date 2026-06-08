# 表情包项目审计问题清单

审计日期: 2026-06-08 | 上次更新: 2026-06-08 (第2轮)

## ECC 命令速查

| 命令 | 用途 | 覆盖问题 |
|------|------|----------|
| `/go-review` | Go 代码审查（错误处理、并发、安全） | #1 #4 #5 #6 #12 #14 #15 #18 #19 |
| `/flutter-review` | Flutter/Dart 代码审查 | #7 #8 #9 #10 #11 #20 |
| `/security-scan` | 安全扫描（认证、CORS、密钥） | #1 #2 #3 |
| `/go-build` | Go 构建验证 | 修复后验证 |
| `/flutter-build` | Flutter 构建验证 | 修复后验证 |

## P0 严重
- [ ] **#1 路径遍历** — `go-review` `security-scan` — server/handler/pack_handler.go:191 GetStickerFile 未做路径清理
- [ ] **#2 无认证/鉴权** — `security-scan` — server/main.go:63-70 API 完全开放
- [ ] **#3 CORS 设为 *** — `security-scan` — server/main.go:49 生产环境应限制域名
- [ ] **#4 Share Code 太小** — `go-review` — server/service/pack_service.go:87-91 4字节可被暴力枚举

## Bug 追踪
- [ ] **BUG-1** `Bad State: Permission state error with PermissionState.denied` — gallery_picker_screen.dart / wechat_assets_picker 调用时权限被拒绝后未正确处理状态，应用 try-catch 包裹权限请求并引导用户手动开启设置

## P1 正确性
- [ ] **#5 Pack 创建后全部上传失败不回滚** — `go-review` — server/handler/pack_handler.go:37-105
- [ ] **#6 单个 sticker 失败静默吞掉** — `go-review` — server/handler/pack_handler.go:77-91
- [ ] **#7 Sticker.fromApiMap 丢失 extension** — `flutter-review` — sticker_app/lib/models/sticker.dart:52-61
- [ ] **#8 Flutter FK pragma 仅在 onCreate** — `flutter-review` — storage_service.dart:22 PRAGMA 在 onCreate 里，已有数据库不会生效；应用 onConfigure 回调

## P2 性能/体验
- [ ] **#9 gallery_service navigatorKey 未绑定** — `flutter-review` — gallery_service.dart:39 定义了全局 navigatorKey 但未绑定到 MaterialApp，GalleryPickerScreen 已自行处理选图，此 service 实际未被使用
- [ ] **#10 串行下载** — `flutter-review` — download_service.dart:42-65 逐个串行下载，虽有 failedIds 统计但仍无并发
- [ ] **#11 cached_network_image 未使用** — `flutter-review` — pubspec.yaml:18 引入但 sticker_tile.dart:44 用原生 Image.network 无缓存
- [ ] **#12 detectImageSize 读 1MB 过多** — `go-review` — server/handler/pack_handler.go:248 LimitReader 设为 1MB，图片头只需 4KB

## P3 代码质量
- [ ] **#14 冗余代码** — `go-review` — store/sticker_store.go:50-58 DeleteSticker/DeleteStickersByPackID 未被调用
- [ ] **#15 错误信息泄露** — `go-review` `flutter-review` — server pack_handler.go:39,142,224 err.Error() 直接返回；Flutter 侧 gallery_picker_screen.dart:148,174、pack_detail_screen.dart:74、share_pack_screen.dart:114 仍暴露 '$e' 异常细节
- [ ] **#18 AddSticker 无事务** — `go-review` — server/service/pack_service.go:47-62 CreateSticker + IncrementPackCount 两步无事务保护
- [ ] **#19 rand.Read 错误被忽略** — `go-review` — server/service/pack_service.go:83,89

## 已修复
- [x] **#13 home_screen.dart 和 import_link_screen.dart 未完成** — 已有完整实现 (第1轮修复)
- [x] **#16 Pack ID 用时间戳可能冲突** — pack_provider.dart:36 改用 `const Uuid().v4()`
- [x] **#17 API baseUrl 硬编码 localhost** — 新增 config.dart 集中管理 AppConfig.apiBaseUrl，import_link_screen.dart:87,105 和 share_pack_screen.dart:100 已引用
- [x] **#20 share_pack_screen 错误消息泄露** — 合并至 #15 统一跟踪
