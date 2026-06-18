# 局域网互传设计文档

## 概述

为 Sticker App 实现 LocalSend 风格的局域网表情包互传功能，支持 Android ↔ Android、Android ↔ PC 在同一 WiFi 下直接传输，不经过外部服务器。

## 技术选型

- **发现协议**: UDP 多播（Multicast）
- **传输协议**: HTTP REST API
- **实现语言**: 纯 Dart，跨平台共享

## 1. 发现层（Discovery Layer）

### 多播配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 多播组 | 239.0.0.170 | 与 LocalSend (239.0.0.169) 隔离 |
| 端口 | 53319 | 与 LocalSend (53317) 隔离 |
| 广播间隔 | 3 秒 | 心跳频率 |
| 超时时间 | 15 秒 | 无心跳则从列表移除 |

### 广播报文格式

```json
{
  "alias": "用户自定义设备名",
  "deviceModel": "Pixel 7 / Windows PC",
  "deviceType": "mobile | desktop",
  "fingerprint": "设备唯一UUID",
  "port": 53319,
  "appName": "StickerApp",
  "version": "1.0"
}
```

### 发现流程

1. 启动时生成设备 fingerprint（首次生成后持久化存储）
2. 创建 UDP socket，绑定 53319 端口，加入多播组 239.0.0.170
3. 每 3 秒广播自身信息
4. 监听多播组消息，收到后更新设备列表
5. 过滤 `appName != "StickerApp"` 的消息，避免与其他应用冲突
6. 忽略自身 fingerprint 的消息
7. 15 秒未收到某设备心跳 → 从列表移除

## 2. 传输层（Transfer Layer）

### HTTP 服务

每个设备启动时同时运行一个 HTTP 服务，监听 `0.0.0.0:53319`（与 UDP 同端口，TCP/UDP 不冲突）。

### API 接口

#### `POST /api/sticker/send` — 发起发送请求

**请求方 → 接收方**

```json
// Request Body
{
  "packName": "猫咪合集",
  "packId": "abc123",
  "stickerCount": 15,
  "totalSizeBytes": 2048000,
  "senderName": "Pixel 7",
  "senderFingerprint": "xxx-xxx"
}
```

**接收方响应：**
- `200 OK` — 接受传输
- `403 Forbidden` — 用户拒绝
- `409 Conflict` — 已有进行中的传输

#### `POST /api/sticker/upload` — 上传文件

```json
// Content-Type: multipart/form-data
// 字段:
//   packName: string
//   packId: string
//   file_0: binary (sticker 1)
//   file_1: binary (sticker 2)
//   ...
```

**接收方响应：**

```json
{
  "success": true,
  "receivedCount": 15,
  "failedCount": 0
}
```

#### `GET /api/sticker/ping` — 健康检查

返回 `200 OK`，用于检测设备是否在线。

### 传输流程

```
发送方                          接收方
  |                               |
  |-- POST /api/sticker/send ---->|
  |                               | 弹窗: "XX 想发送 15 个表情"
  |<------- 200 accept -----------| 用户点击"接受"
  |                               |
  |-- POST /api/sticker/upload -->|
  |   (multipart, streaming)      | 保存到本地文件系统
  |<------- 200 success ----------| 写入数据库
  |                               |
  |  完成通知                     | 完成通知
```

### 超时与错误处理

| 场景 | 处理 |
|------|------|
| 接收方 30 秒未确认 | 自动取消 |
| 上传中断 | 提示重试 |
| 单文件失败 | 跳过继续，最后报告失败数 |
| 接收方磁盘满 | 返回 507，发送方提示 |

## 3. UI 设计

### 发现页面（新页面）

**入口：**
- Android: 首页底部导航新增"发现"Tab
- PC: 侧边栏新增"局域网"菜单项

**页面布局：**

```
┌──────────────────────────────┐
│  📡 局域网发现                │
│                              │
│  本机: Pixel 7               │
│  [显示二维码]  [修改设备名]    │
│                              │
│  ── 附近设备 ──               │
│                              │
│  📱 iPhone 15     192.168.1.5 │  ← 点击发送
│  💻 DESKTOP-PC   192.168.1.8 │  ← 点击发送
│  📱 Xiaomi 14    192.168.1.12│  ← 点击发送
│                              │
│  正在搜索附近设备...           │
└──────────────────────────────┘
```

**交互流程：**
1. 点击附近设备 → 弹出"选择表情包"对话框
2. 选择要发送的表情包 → 显示发送进度
3. 完成后提示"发送成功"

### 二维码格式

```
sticker://lan/192.168.1.10:53319
```

接收方扫码后直接连接到发送方的 HTTP 服务。

### 接收确认弹窗

```
┌──────────────────────────────┐
│  收到传输请求                  │
│                              │
│  Pixel 7 想发送给你:          │
│  📦 猫咪合集 (15 个表情)      │
│  大小: 2.0 MB                │
│                              │
│  [拒绝]        [接受]         │
└──────────────────────────────┘
```

## 4. 文件结构

### sticker_app（Android）

```
sticker_app/lib/services/lan/
├── lan_discovery_service.dart   # UDP 多播发现
├── lan_transfer_service.dart    # HTTP 服务 + 文件传输
├── lan_models.dart              # 设备信息、传输请求等数据模型

sticker_app/lib/screens/
├── lan_discover_screen.dart     # 发现页面 UI

sticker_app/lib/widgets/
├── receive_request_dialog.dart  # 接收确认弹窗
```

### sticker_pc（Windows）

复用相同的 `services/lan/` 逻辑代码（复制到 PC 项目，保持同步）。

```
sticker_pc/lib/services/lan/
├── lan_discovery_service.dart   # 与 Android 版本一致
├── lan_transfer_service.dart    # 与 Android 版本一致
├── lan_models.dart              # 与 Android 版本一致

sticker_pc/lib/screens/
├── lan_discover_screen.dart     # PC 端 UI（桌面布局适配）
```

## 5. 依赖包

### 新增依赖

```yaml
dependencies:
  uuid: ^4.0.0          # 生成设备 fingerprint
  # 无需其他第三方包
  # UDP: dart:io RawDatagramSocket
  # HTTP Server: dart:io HttpServer
  # HTTP Client: 现有 dio
```

## 6. 数据模型

### LanDevice

```dart
class LanDevice {
  final String fingerprint;    // 设备唯一 ID
  final String alias;          // 设备显示名
  final String deviceModel;    // 设备型号
  final String deviceType;     // mobile | desktop
  final int port;              // HTTP 端口
  final String ip;             // 设备 IP（从 UDP 包获取）
  final DateTime lastSeen;     // 最后心跳时间
}
```

### LanTransferRequest

```dart
class LanTransferRequest {
  final String packName;
  final String packId;
  final int stickerCount;
  final int totalSizeBytes;
  final String senderName;
  final String senderFingerprint;
}
```

## 7. 安全考虑

### 当前版本（v1）

- 不实现 TLS 加密（局域网内，风险可控）
- 接收方必须手动确认才能接收
- 只传输表情包文件，不传输其他数据

### 后续可选

- 自签名 TLS 证书加密传输
- 设备配对信任机制
- 传输历史记录

## 8. 平台注意事项

### Android

- 需要 `INTERNET` 和 `ACCESS_WIFI_STATE` 权限
- Android 9+ 需要前台服务才能维持后台 HTTP 服务（但表情包传输场景不需要后台）
- WiFi Multicast Lock: 需要在代码中获取 `WifiManager.MulticastLock`，否则收不到多播包

### Windows

- 无需特殊权限
- 防火墙可能拦截首次连接，需提示用户允许

## 9. 与现有功能的关系

- 局域网传输是**独立功能**，不影响现有服务器分享码和 VPS 加密分享
- 传输的表情包直接写入本地数据库，与通过其他方式导入的表情包无区别
- 共享现有的 `StorageService` 和 `StickerPack` / `Sticker` 模型
