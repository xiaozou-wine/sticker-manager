# VPS 表情包分享服务设计

日期: 2026-06-08
状态: 草案

## 概述

为 Sticker Manager 添加基于 VPS 自部署的表情包分享功能。用户在自己的 VPS 上 Docker 一键部署轻量服务，通过 App 端到端加密上传表情包，生成分享链接给其他人导入。

## 设计目标

- **轻量**: 单个 Go 二进制 + SQLite，Docker 镜像 < 20MB
- **端到端加密**: VPS 主人看不到分享的表情包内容
- **零配置**: `docker-compose up -d` 即可使用
- **不暴露 IP**: 分享链接不直接显示 VPS 地址（通过编码隐藏）

## 分享链接格式

```
sticker://share/{base64url(server_addr + "|" + pack_id)}#{base64url(aes_key)}
```

示例:
```
sticker://share/aHR0cDovLzEyNy4wLjAuMTo4MDgwfDEyMzRhYmNk#dGhpcy1pcy1hLXRlc3Qta2V5
```

解析逻辑:
1. 去掉 `sticker://share/` 前缀
2. `#` 之前部分 base64url 解码 → 得到 `server_addr|pack_id`
3. `#` 之后部分 base64url 解码 → 得到 AES-256 密钥（32 字节）

好处:
- 链接不直接暴露 IP 地址（base64 编码）
- `#` 后面的密钥不会发送到服务器（HTTP 标准行为）
- 自定义 scheme `sticker://` 让 App 可以直接拦截打开

## 加密方案

算法: AES-256-GCM

```
加密:
  key = 32 字节随机密钥
  对每个文件:
    nonce = 12 字节随机数
    ciphertext, tag = AES-256-GCM(key, nonce, plaintext)
    输出 = nonce(12) + tag(16) + ciphertext

解密:
  从文件读取前 12 字节 → nonce
  接下来 16 字节 → tag
  剩余字节 → ciphertext
  plaintext = AES-256-GCM-Decrypt(key, nonce, ciphertext, tag)
```

加密在 App 端完成，服务器只存储加密后的 blob。

## VPS 服务端设计

### 目录结构

```
vps-server/
  main.go           — 入口 + 路由 + 认证中间件
  crypto.go         — ID 生成工具
  store.go          — SQLite 数据访问（复用现有逻辑）
  Dockerfile        — 多阶段构建
  docker-compose.yml
  .env.example
  go.mod            — 独立模块
```

### 文件职责

**main.go** (~150 行):
- 环境变量读取: `PASSWORD`(必填), `PORT`(默认 8080), `DATA_DIR`(默认 /data)
- 认证中间件: 写操作需要 `X-Auth-Token` header 匹配密码
- 路由注册:
  - `POST /api/packs` — 上传表情包（需密码）
  - `GET /api/packs/:code` — 查看包信息（无需密码）
  - `GET /api/packs/:code/stickers` — 获取表情列表（无需密码）
  - `GET /api/stickers/:id/file` — 下载表情文件（无需密码）
  - `DELETE /api/packs/:code` — 删除包（需密码）
  - `GET /health` — 健康检查
- CORS 中间件
- 请求体大小限制 (50MB)

**store.go** (~120 行):
- `NewDB(path)`: 打开 SQLite，执行 migration
- `CreatePack`, `GetPackByShareCode`, `GetPackByID`, `DeletePack`
- `CreateSticker`, `GetStickersByPackID`, `GetStickerByID`
- `UpdatePackCover`, `IncrementPackCount`
- migration SQL（与现有服务器相同的 schema）

**crypto.go** (~20 行):
- `generateID() string` — 16 字节随机 hex
- `generateShareCode() string` — 8 字节随机 hex

### API 详细设计

#### POST /api/packs（需密码）

Request: multipart/form-data
- `name`: string (必填)
- `description`: string (可选)
- `stickers[]`: 文件数组 (最多 50 个)
- Header: `X-Auth-Token: {password}`

Response 201:
```json
{
  "pack": {
    "id": "abc123",
    "name": "表情包名称",
    "share_code": "def456",
    "sticker_count": 3
  },
  "stickers": [
    {"id": "abc123_0", "type": "image", "file_url": "/api/stickers/abc123_0/file"}
  ]
}
```

处理逻辑:
1. 验证密码
2. 生成 pack ID 和 share_code
3. 保存文件到 `{DATA_DIR}/stickers/{pack_id}/`
4. 记录元数据到 SQLite（不做图片尺寸检测，因为是加密 blob）
5. 返回包信息

#### GET /api/packs/:code（无需密码）

Response 200:
```json
{
  "pack": {
    "id": "abc123",
    "name": "表情包名称",
    "share_code": "def456",
    "sticker_count": 3,
    "cover_url": "http://server/api/stickers/abc123_0/file"
  }
}
```

#### GET /api/packs/:code/stickers（无需密码）

Response 200:
```json
{
  "pack_id": "abc123",
  "stickers": [
    {
      "id": "abc123_0",
      "type": "image",
      "file_url": "http://server/api/stickers/abc123_0/file",
      "size_bytes": 12345
    }
  ]
}
```

#### GET /api/stickers/:id/file（无需密码）

Response: 文件内容（加密 blob），Content-Type: application/octet-stream

安全措施:
- ID 格式验证（字母数字下划线连字符，最长 128）
- 绝对路径前缀校验防止路径遍历

#### DELETE /api/packs/:code（需密码）

Response 200: `{"message": "deleted"}`

### Docker 部署

**Dockerfile**:
```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o sticker-vps .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/sticker-vps /usr/local/bin/
EXPOSE 8080
ENTRYPOINT ["sticker-vps"]
```

**docker-compose.yml**:
```yaml
services:
  sticker-vps:
    build: .
    ports:
      - "${PORT:-8080}:8080"
    environment:
      - PASSWORD=${PASSWORD}
      - PORT=8080
      - DATA_DIR=/data
    volumes:
      - ./data:/data
    restart: unless-stopped
```

**.env.example**:
```
PASSWORD=your-secret-password-here
PORT=8080
```

## App 端改动

### 新增文件

**lib/services/crypto_service.dart** (~60 行):
```dart
class CryptoService {
  // 生成 32 字节随机 AES 密钥
  static Uint8List generateKey();

  // AES-256-GCM 加密
  // 输入: plaintext, key
  // 输出: nonce(12) + tag(16) + ciphertext
  static Uint8List encrypt(Uint8List plaintext, Uint8List key);

  // AES-256-GCM 解密
  // 输入: nonce(12) + tag(16) + ciphertext, key
  // 输出: plaintext
  static Uint8List decrypt(Uint8List data, Uint8List key);

  // 生成分享链接
  static String buildShareLink(String serverAddr, String packId, Uint8List key);

  // 解析分享链接
  static ShareLinkInfo parseShareLink(String link);
}
```

### 修改文件

**lib/services/api_service.dart**:
- `uploadPack` 方法增加 `authToken` 可选参数
- `downloadSticker` 方法不变（下载不需要密码）
- 新增 `uploadToVPS` 方法，支持自定义 baseUrl + authToken

**lib/screens/share_pack_screen.dart**:
改造为两步流程:
1. 选择分享方式（现有分享码 / VPS 分享）
2. VPS 分享时:
   - 输入 VPS 地址和密码
   - 本地加密所有表情文件
   - 上传到 VPS
   - 生成并显示分享链接（可复制）

**lib/screens/import_link_screen.dart**:
改造导入逻辑:
1. 支持粘贴 `sticker://share/...` 链接
2. 解析出服务器地址、pack_id、密钥
3. 从服务器下载加密文件
4. 本地解密后保存
5. 向后兼容：仍然支持输入现有分享码

### 依赖新增

```yaml
# pubspec.yaml
dependencies:
  encrypt: ^5.0.3          # AES-256-GCM 加解密
  # 或者用 pointycastle + 原生实现
```

## 实现计划

### Phase 1: VPS 服务端（Go）
1. 创建 `vps-server/` 目录和 `go.mod`
2. 实现 `store.go`（SQLite 数据访问）
3. 实现 `crypto.go`（ID 生成）
4. 实现 `main.go`（路由 + 认证 + handler）
5. 创建 `Dockerfile` 和 `docker-compose.yml`
6. 本地测试

### Phase 2: App 端加密服务（Dart）
1. 添加 encrypt 依赖
2. 实现 `crypto_service.dart`
3. 实现分享链接生成/解析

### Phase 3: App 端 UI 改造
1. 改造 `share_pack_screen.dart`（VPS 分享流程）
2. 改造 `import_link_screen.dart`（链接导入流程）
3. 测试端到端流程

### Phase 4: 集成测试
1. Docker 部署 VPS 服务
2. App 端上传 + 加密测试
3. 分享链接导入测试
4. 向后兼容测试（现有分享码仍可用）
