# Sticker Manager - 项目目标

## 项目简介

表情包管理 App（Flutter + Go），解决 QQ/微信等应用批量添加表情包繁琐的问题。

## 核心目标

### Phase 1 - MVP（已完成）
- [x] 从手机相册批量选择图片/GIF，创建表情包集
- [x] 表情包集管理（查看、删除、详情）
- [x] Go 后端 REST API（5 个端点）
- [x] SQLite + 本地文件存储
- [x] 上传表情包集到云端，生成分享码
- [x] 通过分享码下载表情包集到本地
- [x] GitHub 仓库 + Release（APK + Server 二进制）

### Phase 2 - 分享体验优化
- [ ] 短链生成 + 深度链接（Deep Link），点击链接直接打开 App
- [ ] App 内直接打开分享链接并预览表情包
- [ ] 图片压缩/转码优化（上传前自动缩放到 500x500）
- [ ] GIF 压缩（超 10MB 自动降色/截帧）
- [ ] 离线缓存管理（清理过期缓存、查看存储占用）
- [ ] 系统分享菜单集成（分享到微信/QQ）
- [ ] 表情包排序（按名称、时间、数量）

### Phase 3 - 高级功能
- [ ] 从 App 直接发送表情包到 QQ/微信聊天
- [ ] 自定义键盘方案（输入法内嵌表情选择器）
- [ ] 表情包标签/分类系统
- [ ] 热门表情包广场（社区分享）
- [ ] 搜索功能（按名称、标签搜索）
- [ ] 表情包收藏夹

### Phase 4 - 平台与体验
- [ ] iOS 适配与测试
- [ ] 深色模式支持
- [ ] 多语言支持
- [ ] 用户账号系统（可选，用于跨设备同步）
- [ ] 表情包自动去重

## 技术架构

```
sticker_app/          Flutter 移动客户端
  lib/
    models/           数据模型（Sticker, StickerPack）
    providers/        状态管理（Provider）
    services/         业务服务（API, 存储, 相册, 下载）
    screens/          页面（首页, 详情, 导入, 分享）
    widgets/          通用组件

server/               Go 后端服务
  handler/            HTTP 处理器
  model/              数据模型
  store/              SQLite 存储层
  service/            业务逻辑层
```

## 约束

- 单张表情最大 500x500px（超出等比缩放）
- 静态图 5MB / GIF 10MB 上限
- 每个表情包集最多 500 张
- 支持格式：JPG、PNG、GIF
- Go 后端单次上传最多 50 张，请求体 50MB

## 链接

- 仓库：https://github.com/xiaozou-wine/sticker-manager
- Release：https://github.com/xiaozou-wine/sticker-manager/releases/tag/v0.1.0
