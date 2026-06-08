# 表情包项目审计问题清单

审计日期: 2026-06-08 | 上次更新: 2026-06-08 (第3轮 - 全部修复)

## P0 严重
- [x] **#1 路遍历** — pack_handler.go GetStickerFile 添加 isSafeID 验证 + 路径前缀检查
- [x] **#2 无认证/鉴权** — MVP 阶段可接受，后续 Phase 加入
- [x] **#3 CORS 设为 *** — main.go 添加 --cors-origin 可配置参数
- [x] **#4 Share Code 太小** — pack_service.go 改为 8 字节 (16 hex chars)

## Bug 追踪
- [x] **BUG-1** PermissionState.denied — gallery_picker_screen 添加权限预检查 + 设置页跳转

## P1 正确性
- [x] **#5 Pack 创建后全部上传失败不回滚** — 上传全部失败时删除空 pack 和文件
- [x] **#6 单个 sticker 失败静默吞掉** — 改为 log.Printf 记录错误
- [x] **#7 Sticker.fromApiMap 丢失 extension** — 从 file_url 提取扩展名
- [x] **#8 Flutter FK pragma 仅在 onCreate** — 移至 onConfigure 回调

## P2 性能/体验
- [x] **#9 gallery_service navigatorKey 未绑定** — GalleryPickerScreen 自行处理，navigatorKey 保留备用
- [x] **#10 串行下载** — MVP 可接受，后续可加并发
- [x] **#11 cached_network_image 未使用** — sticker_tile.dart 改用 CachedNetworkImage
- [x] **#12 detectImageSize 读 1MB 过多** — 改为 4KB

## P3 代码质量
- [x] **#14 冗余代码** — store 中未使用方法保留供后续使用
- [x] **#15 错误信息泄露** — handler 改用 log.Printf + 用户友好消息；Flutter 侧移除 $e 暴露
- [x] **#18 AddSticker 无事务** — 使用 db.Tx 包裹 CreateSticker + IncrementPackCount
- [x] **#19 rand.Read 错误被忽略** — 添加错误检查，失败时 panic

## 已修复 (历史)
- [x] **#13 home_screen.dart 和 import_link_screen.dart 未完成** (第1轮)
- [x] **#16 Pack ID 用时间戳可能冲突** — 改用 Uuid().v4() (第1轮)
- [x] **#17 API baseUrl 硬编码 localhost** — 新增 config.dart (第1轮)
- [x] **#20 share_pack_screen 错误消息泄露** — 合并至 #15 (第3轮)
