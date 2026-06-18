# 局域网互传功能设计

## 概述

在 Sticker Manager 中实现局域网内设备间直接传输表情包集，参考 LocalSend 方案。同一 WiFi 下的设备自动发现、点对点传输，不经过外部服务器。

## 目标

- 同一局域网内所有设备互传表情包集（Android ↔ Android, PC ↔ PC, Android ↔ PC）
- UDP 组播自动发现附近设备
- 接收方需确认后才接收（防陌生人骚扰）
- 双端支持：sticker_app（Android）和 sticker_pc（Windows）

## 非目标

- 不支持任意文件传输，仅限表情包集
- 不支持跨网段/互联网传输
- 不做加密（局域网内明文 HTTP）

## 架构

每个客户端内置三个服务：

```
┌─────────────────────────────────────────────────┐
│              sticker_app / sticker_pc            │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │ Discovery   │  │ LanServer  │  │ Sender   │ │
│  │ Service     │  │ (HTTP)     │  │ Client   │ │
│  │             │  │            │  │          │ │
│  │ UDP 广播     │  │ 接收请求    │  │ 发送请求  │ │
│  │ 53210       │  │ 53211      │  │ HTTP POST │ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
│         ↕               ↕               ↕       │
│  ┌──────────────────────────────────────────┐   │
│  │       Storage / DB (现有 sqflite)         │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

| 服务 | 职责 | 技术 |
|------|------|------|
| DiscoveryService | 广播自身、发现附近设备 | UDP DatagramSocket, port 53210 |
| LanServer | 接收传输请求、保存文件 | dart:io HttpServer, port 53211 |
| SenderClient | 发送表情包到目标设备 | dart:io HttpClient |

## 设备发现协议（UDP）

- 端口：53210（收发共用）
- 广播间隔：1 秒
- 消息格式：JSON

### Announce 消息（每秒广播）

```json
{
  "type": "announce",
  "alias": "我的电脑",
  "deviceType": "pc",
  "port": 53211,
  "fingerprint": "a1b2c3d4e5f6"
}
```

### Response 消息（收到 announce 后回复）

```json
{
  "type": "response",
  "alias": "小米14",
  "deviceType": "android",
  "port": 53211,
  "fingerprint": "d4e5f6a7b8c9"
}
```

### 设备列表维护

- 收到 announce/response → 更新/插入设备，刷新时间戳
- 3 秒未收到 → 标记离线
- 5 秒未收到 → 从列表移除
- fingerprint 为设备唯一标识，首次生成后持久化到本地

## 传输协议（HTTP）

所有端点在 LanServer（port 53211）上。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/lan/send-request` | 发送方→接收方：请求发送 |
| POST | `/api/lan/send-accept` | 接收方→发送方：确认接收 |
| POST | `/api/lan/send-reject` | 接收方→发送方：拒绝 |
| POST | `/api/lan/upload` | 发送方→接收方：推送文件 |
| POST | `/api/lan/upload-done` | 发送方→接收方：传输完成 |

### 传输时序

```
发送方                          接收方
  │                               │
  │── POST send-request ────────→ │  pack 元数据 + 全部缩略图
  │                               │  弹窗确认对话框
  │                               │
  │ ←── POST send-accept ────────│  返回 sessionToken
  │    (sessionToken)             │
  │                               │
  │── POST upload (#1) ─────────→│  multipart: file + metadata
  │── POST upload (#2) ─────────→│
  │── ...                        │
  │── POST upload (#N) ─────────→│
  │                               │
  │── POST upload-done ─────────→│  接收方入库完成
```

### send-request 请求体

```json
{
  "fingerprint": "a1b2c3d4e5f6",
  "alias": "我的电脑",
  "deviceType": "pc",
  "packName": "猫咪合集",
  "packDescription": "可爱的猫咪",
  "fileCount": 15,
  "totalSize": 2048000,
  "previews": [
    {"index": 0, "data": "base64-jpeg..."},
    {"index": 1, "data": "base64-jpeg..."},
    ...全部缩略图...
  ]
}
```

缩略图策略：每张图缩放到 80x80，JPEG 质量 50，单张约 3-5KB。

### send-accept 响应

```json
{
  "sessionToken": "random-uuid",
  "message": "accepted"
}
```

### upload multipart 字段

| 字段 | 说明 |
|------|------|
| sessionToken | 由 send-accept 返回 |
| file | 文件二进制 |
| filename | 原始文件名 |
| index | 文件序号（从 0 开始） |

### upload-done 请求体

```json
{
  "sessionToken": "random-uuid",
  "packName": "猫咪合集",
  "packDescription": "可爱的猫咪"
}
```

接收方收到 upload-done 后，将暂存的文件写入本地数据库，完成入库。

## UI 设计

### 入口

首页底部导航新增「局域网」Tab：

```
[我的表情包]  [导入]  [局域网]
```

### 局域网传输页面

```
┌─────────────────────────────────┐
│  局域网传输              [刷新]  │
├─────────────────────────────────┤
│  在线设备                       │
│                                 │
│  ┌─────────┐  ┌─────────┐      │
│  │ 🖥 我的PC │  │ 📱 小米14│      │
│  │ Windows  │  │ Android │      │
│  └─────────┘  └─────────┘      │
│                                 │
│  点击设备 → 选择表情包集 → 发送  │
└─────────────────────────────────┘
```

### 发送流程

1. 点击在线设备卡片
2. 弹出表情包集选择列表（复用现有 pack 列表数据）
3. 选中一个 pack → 进入确认页（名称、数量、大小、全部缩略图预览）
4. 点「发送」→ 发送 send-request
5. 等待对方响应（显示等待动画）
6. 对方同意后显示进度条
7. 全部发送完成 → 提示「已发送 猫咪合集」

### 接收弹窗

收到 send-request 时，在任意页面弹出确认对话框：

```
┌─────────────────────────────────┐
│  我的电脑 想发送给你              │
│                                  │
│  📦 猫咪合集 (15张, 2.0MB)       │
│                                  │
│  [img1] [img2] [img3] [img4]    │
│  [img5] [img6] [img7] [img8]    │
│  ...全部缩略图网格...             │
│                                  │
│     [ 拒绝 ]     [ 接收 ]        │
└─────────────────────────────────┘
```

- 点「接收」→ 调用 send-accept → 显示接收进度
- 点「拒绝」→ 调用 send-reject
- 接收完成后提示「已接收 猫咪合集」，自动入库

### 两端差异

| 功能 | sticker_app (Android) | sticker_pc (Windows) |
|------|----------------------|---------------------|
| 设备图标 | 📱 | 🖥 |
| 接收弹窗 | AlertDialog | AlertDialog（窗口置顶） |
| 后台保活 | 前台通知（Service + Notification） | 最小化到系统托盘 |
| 发送选择 | 复用现有 pack 列表 | 复用现有 pack 列表 |

## 错误处理

| 场景 | 处理 |
|------|------|
| 对方拒绝 | 提示「对方已拒绝」|
| 对方超时（30 秒无响应）| 提示「对方未响应」|
| 传输中断（网络断开）| 提示「传输中断」，接收方清理临时文件 |
| 端口被占用 | 自动尝试端口 53212-53220，announce 中广播实际端口 |
| UDP 广播被防火墙拦截 | 提示「无法发现设备，请检查防火墙设置」|

## 新增文件清单

### sticker_app/lib/services/

| 文件 | 说明 |
|------|------|
| lan_discovery_service.dart | UDP 发现服务 |
| lan_server_service.dart | HTTP 接收服务器 |
| lan_sender_service.dart | 发送客户端 |

### sticker_app/lib/screens/

| 文件 | 说明 |
|------|------|
| lan_share_screen.dart | 局域网传输主页 |
| lan_send_confirm_screen.dart | 发送确认页（含缩略图预览） |
| lan_receive_dialog.dart | 接收确认弹窗 |

### sticker_pc/lib/services/

同 sticker_app，独立实现（相同协议、各自代码）。

### sticker_pc/lib/screens/

同 sticker_app，适配桌面端 UI。

## 依赖

无新增外部依赖。使用 dart:io 自带的：
- `RawDatagramSocket` — UDP 收发
- `HttpServer` — HTTP 服务器
- `HttpClient` — HTTP 客户端

## 端口规划

| 端口 | 用途 |
|------|------|
| 53210 | UDP 设备发现 |
| 53211 | HTTP 传输服务（默认，冲突时自动递增） |
| 28749 | 现有 Go 后端（不变） |

## 与现有功能的关系

- 局域网传输是**独立功能模块**，不修改现有分享/导入逻辑
- 传输完成后，接收方的 pack 存储方式与通过分享码导入完全一致
- 不依赖 Go 后端或 VPS，纯客户端功能
