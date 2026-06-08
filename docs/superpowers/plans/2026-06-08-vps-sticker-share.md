# VPS 表情包分享服务 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户在 VPS 上 Docker 部署轻量服务，App 端到端加密上传表情包，生成分享链接供他人导入。

**Architecture:** VPS 端是独立 Go 服务（SQLite + 文件存储），复用现有 API 格式 + 密码认证。App 端新增 AES-256-GCM 加密层，分享链接用 `sticker://share/` 自定义 scheme 编码服务器地址和密钥。

**Tech Stack:** Go + Gin + modernc.org/sqlite (VPS), Dart + encrypt 包 (App), Docker (部署)

---

## 文件清单

### 新建文件
| 文件 | 职责 |
|---|---|
| `vps-server/main.go` | 入口、路由、认证中间件、handler |
| `vps-server/store.go` | SQLite 数据访问 |
| `vps-server/go.mod` | Go 模块定义 |
| `vps-server/Dockerfile` | 多阶段构建 |
| `vps-server/docker-compose.yml` | Docker 编排 |
| `vps-server/.env.example` | 配置模板 |
| `sticker_app/lib/services/crypto_service.dart` | AES-256-GCM 加解密、链接生成/解析 |

### 修改文件
| 文件 | 改动 |
|---|---|
| `sticker_app/pubspec.yaml` | 添加 `encrypt` 依赖 |
| `sticker_app/lib/services/api_service.dart` | 支持自定义 baseUrl + authToken |
| `sticker_app/lib/screens/share_pack_screen.dart` | 新增 VPS 分享模式 |
| `sticker_app/lib/screens/import_link_screen.dart` | 支持 sticker:// 链接导入 + 解密 |

---

## Task 1: VPS 服务端 — store.go

**Files:**
- Create: `vps-server/go.mod`
- Create: `vps-server/store.go`

- [ ] **Step 1: 创建 go.mod**

```go
module sticker-vps

go 1.24

require (
	github.com/gin-gonic/gin v1.12.0
	modernc.org/sqlite v1.37.0
)
```

然后运行 `cd vps-server && go mod tidy` 补全依赖。

- [ ] **Step 2: 创建 store.go**

```go
package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type DB struct {
	conn *sql.DB
}

func NewDB(path string) (*DB, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	conn, err := sql.Open("sqlite3", path+"?_journal_mode=WAL")
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}

	db := &DB{conn: conn}
	if err := db.migrate(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return db, nil
}

func (db *DB) Close() error { return db.conn.Close() }

func (db *DB) migrate() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS sticker_packs (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			cover_url TEXT DEFAULT '',
			share_code TEXT UNIQUE NOT NULL,
			sticker_count INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS stickers (
			id TEXT PRIMARY KEY,
			pack_id TEXT NOT NULL,
			type TEXT NOT NULL DEFAULT 'image',
			width INTEGER DEFAULT 0,
			height INTEGER DEFAULT 0,
			size_bytes INTEGER DEFAULT 0,
			extension TEXT DEFAULT '.bin',
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (pack_id) REFERENCES sticker_packs(id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_stickers_pack_id ON stickers(pack_id)`,
		`CREATE INDEX IF NOT EXISTS idx_packs_share_code ON sticker_packs(share_code)`,
	}
	for _, q := range queries {
		if _, err := db.conn.Exec(q); err != nil {
			return err
		}
	}
	_, err := db.conn.Exec("PRAGMA foreign_keys = ON")
	return err
}

// --- Pack CRUD ---

type StickerPack struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Description  string    `json:"description,omitempty"`
	CoverURL     string    `json:"cover_url,omitempty"`
	ShareCode    string    `json:"share_code"`
	StickerCount int       `json:"sticker_count"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func (db *DB) CreatePack(p *StickerPack) error {
	_, err := db.conn.Exec(
		`INSERT INTO sticker_packs (id, name, description, cover_url, share_code, sticker_count, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		p.ID, p.Name, p.Description, p.CoverURL, p.ShareCode, p.StickerCount, p.CreatedAt, p.UpdatedAt,
	)
	return err
}

func (db *DB) GetPackByShareCode(code string) (*StickerPack, error) {
	p := &StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id, name, description, cover_url, share_code, sticker_count, created_at, updated_at
		 FROM sticker_packs WHERE share_code = ?`, code,
	).Scan(&p.ID, &p.Name, &p.Description, &p.CoverURL, &p.ShareCode, &p.StickerCount, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (db *DB) GetPackByID(id string) (*StickerPack, error) {
	p := &StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id, name, description, cover_url, share_code, sticker_count, created_at, updated_at
		 FROM sticker_packs WHERE id = ?`, id,
	).Scan(&p.ID, &p.Name, &p.Description, &p.CoverURL, &p.ShareCode, &p.StickerCount, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (db *DB) DeletePack(id string) error {
	_, err := db.conn.Exec("DELETE FROM sticker_packs WHERE id = ?", id)
	return err
}

func (db *DB) UpdatePackCover(id, coverURL string) error {
	_, err := db.conn.Exec("UPDATE sticker_packs SET cover_url = ?, updated_at = ? WHERE id = ?",
		coverURL, time.Now(), id)
	return err
}

// --- Sticker CRUD ---

type Sticker struct {
	ID        string    `json:"id"`
	PackID    string    `json:"pack_id"`
	Type      string    `json:"type"`
	Width     int       `json:"width"`
	Height    int       `json:"height"`
	SizeBytes int64     `json:"size_bytes"`
	Extension string    `json:"extension"`
	CreatedAt time.Time `json:"created_at"`
}

func (s Sticker) FileURL() string {
	return "/api/stickers/" + s.ID + "/file"
}

func (db *DB) CreateSticker(s *Sticker) error {
	_, err := db.conn.Exec(
		`INSERT INTO stickers (id, pack_id, type, width, height, size_bytes, extension, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.ID, s.PackID, s.Type, s.Width, s.Height, s.SizeBytes, s.Extension, s.CreatedAt,
	)
	return err
}

func (db *DB) IncrementPackCount(id string, delta int) error {
	_, err := db.conn.Exec(
		"UPDATE sticker_packs SET sticker_count = sticker_count + ?, updated_at = ? WHERE id = ?",
		delta, time.Now(), id)
	return err
}

func (db *DB) GetStickersByPackID(packID string) ([]Sticker, error) {
	rows, err := db.conn.Query(
		`SELECT id, pack_id, type, width, height, size_bytes, extension, created_at
		 FROM stickers WHERE pack_id = ? ORDER BY created_at`, packID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stickers []Sticker
	for rows.Next() {
		var s Sticker
		if err := rows.Scan(&s.ID, &s.PackID, &s.Type, &s.Width, &s.Height, &s.SizeBytes, &s.Extension, &s.CreatedAt); err != nil {
			return nil, err
		}
		stickers = append(stickers, s)
	}
	return stickers, rows.Err()
}

func (db *DB) GetStickerByID(id string) (*Sticker, error) {
	s := &Sticker{}
	err := db.conn.QueryRow(
		`SELECT id, pack_id, type, width, height, size_bytes, extension, created_at
		 FROM stickers WHERE id = ?`, id,
	).Scan(&s.ID, &s.PackID, &s.Type, &s.Width, &s.Height, &s.SizeBytes, &s.Extension, &s.CreatedAt)
	if err != nil {
		return nil, err
	}
	return s, nil
}
```

- [ ] **Step 3: 验证编译**

```bash
cd vps-server && go build ./...
```

Expected: 无错误（依赖在 Step 1 的 go mod tidy 已下载）

- [ ] **Step 4: Commit**

```bash
git add vps-server/go.mod vps-server/go.sum vps-server/store.go
git commit -m "feat(vps): add store layer with SQLite migration"
```

---

## Task 2: VPS 服务端 — main.go

**Files:**
- Create: `vps-server/main.go`

- [ ] **Step 1: 创建 main.go**

```go
package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode"

	"github.com/gin-gonic/gin"
)

func main() {
	password := os.Getenv("PASSWORD")
	if password == "" {
		log.Fatal("PASSWORD environment variable is required")
	}
	port := getEnv("PORT", "8080")
	dataDir := getEnv("DATA_DIR", "./data")

	staticDir := filepath.Join(dataDir, "stickers")
	if err := os.MkdirAll(staticDir, 0755); err != nil {
		log.Fatalf("create static dir: %v", err)
	}

	db, err := NewDB(filepath.Join(dataDir, "stickers.db"))
	if err != nil {
		log.Fatalf("init db: %v", err)
	}
	defer db.Close()

	r := gin.Default()

	// CORS — allow all origins for sticker sharing
	r.Use(corsMiddleware())

	// Limit upload 50MB
	r.MaxMultipartMemory = 50 << 20

	api := r.Group("/api")

	// Public read endpoints (no auth)
	api.GET("/packs/:code", handleGetPack(db))
	api.GET("/packs/:code/stickers", handleGetPackStickers(db))
	api.GET("/stickers/:id/file", handleGetStickerFile(db, staticDir))

	// Protected write endpoints (require auth)
	auth := api.Group("", authMiddleware(password))
	auth.POST("/packs", handleCreatePack(db, staticDir))
	auth.DELETE("/packs/:code", handleDeletePack(db, staticDir))

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	log.Printf("Sticker VPS server starting on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// --- Middleware ---

func authMiddleware(password string) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader("X-Auth-Token")
		if token != password {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid password"})
			c.Abort()
			return
		}
		c.Next()
	}
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, X-Auth-Token")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

// --- Handlers ---

func handleCreatePack(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		name := sanitize(c.PostForm("name"))
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
			return
		}
		description := sanitize(c.PostForm("description"))

		pack := &StickerPack{
			ID:          genID(),
			Name:        name,
			Description: description,
			ShareCode:   genID()[:16],
			CreatedAt:   time.Now(),
			UpdatedAt:   time.Now(),
		}
		if err := db.CreatePack(pack); err != nil {
			log.Printf("create pack: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create pack"})
			return
		}

		form, err := c.MultipartForm()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid form"})
			return
		}
		files := form.File["stickers"]
		if len(files) == 0 {
			db.DeletePack(pack.ID)
			c.JSON(http.StatusBadRequest, gin.H{"error": "no stickers provided"})
			return
		}
		if len(files) > 100 {
			db.DeletePack(pack.ID)
			c.JSON(http.StatusBadRequest, gin.H{"error": "max 100 stickers"})
			return
		}

		packDir := filepath.Join(staticDir, pack.ID)
		if err := os.MkdirAll(packDir, 0755); err != nil {
			log.Printf("mkdir: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
			return
		}

		var uploaded []gin.H
		for i, file := range files {
			ext := filepath.Ext(file.Filename)
			if ext == "" {
				ext = ".bin"
			}
			stickerID := fmt.Sprintf("%s_%d", pack.ID, i)
			savePath := filepath.Join(packDir, stickerID+ext)

			if err := c.SaveUploadedFile(file, savePath); err != nil {
				log.Printf("save file: %v", err)
				continue
			}

			sticker := &Sticker{
				ID:        stickerID,
				PackID:    pack.ID,
				Type:      "image",
				SizeBytes: file.Size,
				Extension: ext,
				CreatedAt: time.Now(),
			}
			if err := db.CreateSticker(sticker); err != nil {
				log.Printf("create sticker: %v", err)
				continue
			}

			if len(uploaded) == 0 {
				db.UpdatePackCover(pack.ID, sticker.FileURL())
			}

			uploaded = append(uploaded, gin.H{
				"id":       stickerID,
				"type":     "image",
				"file_url": sticker.FileURL(),
			})
		}

		if len(uploaded) == 0 {
			os.RemoveAll(packDir)
			db.DeletePack(pack.ID)
			c.JSON(http.StatusBadRequest, gin.H{"error": "all uploads failed"})
			return
		}

		db.IncrementPackCount(pack.ID, len(uploaded))
		updatedPack, _ := db.GetPackByID(pack.ID)

		c.JSON(http.StatusCreated, gin.H{
			"pack":     updatedPack,
			"stickers": uploaded,
		})
	}
}

func handleGetPack(db *DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		code := c.Param("code")
		pack, err := db.GetPackByShareCode(code)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
			return
		}
		baseURL := getBaseURL(c)
		pack.CoverURL = baseURL + pack.CoverURL
		c.JSON(200, gin.H{"pack": pack})
	}
}

func handleGetPackStickers(db *DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		code := c.Param("code")
		pack, err := db.GetPackByShareCode(code)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
			return
		}
		stickers, err := db.GetStickersByPackID(pack.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load stickers"})
			return
		}
		baseURL := getBaseURL(c)
		type sResp struct {
			ID        string `json:"id"`
			Type      string `json:"type"`
			FileURL   string `json:"file_url"`
			SizeBytes int64  `json:"size_bytes"`
		}
		var resp []sResp
		for _, s := range stickers {
			resp = append(resp, sResp{
				ID:        s.ID,
				Type:      s.Type,
				FileURL:   baseURL + s.FileURL(),
				SizeBytes: s.SizeBytes,
			})
		}
		c.JSON(200, gin.H{"pack_id": pack.ID, "stickers": resp})
	}
}

func handleGetStickerFile(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		if !isSafeID(id) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
			return
		}
		sticker, err := db.GetStickerByID(id)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		filePath := filepath.Join(staticDir, sticker.PackID, id+sticker.Extension)
		absStatic, _ := filepath.Abs(staticDir)
		absFile, _ := filepath.Abs(filePath)
		if !strings.HasPrefix(absFile, absStatic) {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
			return
		}
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "file not found"})
			return
		}
		c.Header("Content-Type", "application/octet-stream")
		c.Header("Cache-Control", "public, max-age=31536000")
		c.File(filePath)
	}
}

func handleDeletePack(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		code := c.Param("code")
		pack, err := db.GetPackByShareCode(code)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
			return
		}
		os.RemoveAll(filepath.Join(staticDir, pack.ID))
		if err := db.DeletePack(pack.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "delete failed"})
			return
		}
		c.JSON(200, gin.H{"message": "deleted"})
	}
}

// --- Helpers ---

func getBaseURL(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s", scheme, c.Request.Host)
}

func genID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func isSafeID(id string) bool {
	if len(id) == 0 || len(id) > 128 {
		return false
	}
	for _, r := range id {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' && r != '-' {
			return false
		}
	}
	return true
}

func sanitize(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 256 {
		s = s[:256]
	}
	return s
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
```

- [ ] **Step 2: 验证编译**

```bash
cd vps-server && go build -o sticker-vps .
```

Expected: 编译成功，生成 `sticker-vps` 二进制

- [ ] **Step 3: Commit**

```bash
git add vps-server/main.go
git commit -m "feat(vps): add server with auth middleware and all endpoints"
```

---

## Task 3: VPS 服务端 — Docker 部署

**Files:**
- Create: `vps-server/Dockerfile`
- Create: `vps-server/docker-compose.yml`
- Create: `vps-server/.env.example`

- [ ] **Step 1: 创建 Dockerfile**

```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o sticker-vps .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /app/sticker-vps /usr/local/bin/
EXPOSE 8080
ENTRYPOINT ["sticker-vps"]
```

- [ ] **Step 2: 创建 docker-compose.yml**

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

- [ ] **Step 3: 创建 .env.example**

```
# 必填：上传/删除密码
PASSWORD=change-me-to-a-strong-password

# 可选：对外端口（默认 8080）
PORT=8080
```

- [ ] **Step 4: 创建 .gitignore**

```
data/
.env
```

- [ ] **Step 5: 本地 Docker 构建测试**

```bash
cd vps-server
docker compose build
```

Expected: 构建成功

- [ ] **Step 6: Commit**

```bash
git add vps-server/Dockerfile vps-server/docker-compose.yml vps-server/.env.example vps-server/.gitignore
git commit -m "feat(vps): add Docker deployment files"
```

---

## Task 4: App 端 — crypto_service.dart

**Files:**
- Modify: `sticker_app/pubspec.yaml`
- Create: `sticker_app/lib/services/crypto_service.dart`

- [ ] **Step 1: 添加 encrypt 依赖**

在 `sticker_app/pubspec.yaml` 的 `dependencies` 下添加:

```yaml
  encrypt: ^5.0.3
```

运行:

```bash
cd sticker_app && flutter pub get
```

- [ ] **Step 2: 创建 crypto_service.dart**

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class ShareLinkInfo {
  final String serverAddr;
  final String packId;
  final String shareCode;
  final Uint8List key;

  ShareLinkInfo({
    required this.serverAddr,
    required this.packId,
    required this.shareCode,
    required this.key,
  });
}

class CryptoService {
  /// 生成 32 字节随机 AES 密钥
  static Uint8List generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  /// AES-256-GCM 加密
  /// 返回: nonce(12) + tag(16) + ciphertext
  static Uint8List encryptData(Uint8List plaintext, Uint8List key) {
    final encrypter = encrypt.Key(key);
    final iv = encrypt.IV.fromSecureRandom(12);
    final aesGcm = encrypt.AES(encrypter, mode: encrypt.AESMode.gcm);
    final encrypted = aesGcm.encrypt(plaintext, iv: iv);

    // nonce(12) + tag(16) + ciphertext
    final result = Uint8List(12 + 16 + encrypted.bytes.length);
    result.setRange(0, 12, iv.bytes);
    result.setRange(12, 28, encrypted.bytes.sublist(encrypted.bytes.length - 16));
    result.setRange(28, result.length, encrypted.bytes.sublist(0, encrypted.bytes.length - 16));
    return result;
  }

  /// AES-256-GCM 解密
  /// 输入: nonce(12) + tag(16) + ciphertext
  static Uint8List decryptData(Uint8List data, Uint8List key) {
    if (data.length < 28) throw ArgumentError('data too short');

    final nonce = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final ciphertext = data.sublist(28);

    // encrypt 包要求 ciphertext + tag 拼接
    final cipherWithTag = Uint8List(ciphertext.length + 16);
    cipherWithTag.setRange(0, ciphertext.length, ciphertext);
    cipherWithTag.setRange(ciphertext.length, cipherWithTag.length, tag);

    final encrypter = encrypt.Key(key);
    final iv = encrypt.IV(nonce);
    final aesGcm = encrypt.AES(encrypter, mode: encrypt.AESMode.gcm);
    final decrypted = encrypt.Encrypted(cipherWithTag);
    return aesGcm.decryptBytes(decrypted, iv: iv);
  }

  /// 生成分享链接
  /// 格式: sticker://share/{base64url(serverAddr|packId|shareCode)}#{base64url(key)}
  static String buildShareLink({
    required String serverAddr,
    required String packId,
    required String shareCode,
    required Uint8List key,
  }) {
    // 去掉尾部斜杠
    serverAddr = serverAddr.replaceAll(RegExp(r'/+$'), '');
    final payload = '$serverAddr|$packId|$shareCode';
    final encodedPayload = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    final encodedKey = base64Url.encode(key).replaceAll('=', '');
    return 'sticker://share/$encodedPayload#$encodedKey';
  }

  /// 解析分享链接
  /// 支持格式: sticker://share/{payload}#{key}
  static ShareLinkInfo? parseShareLink(String link) {
    link = link.trim();

    // 处理 sticker:// 格式
    if (!link.startsWith('sticker://share/')) return null;

    final body = link.substring('sticker://share/'.length);
    final hashIndex = body.indexOf('#');
    if (hashIndex < 0) return null;

    final encodedPayload = body.substring(0, hashIndex);
    final encodedKey = body.substring(hashIndex + 1);

    try {
      // 补齐 base64 padding
      final payloadPadded = _addBase64Padding(encodedPayload);
      final keyPadded = _addBase64Padding(encodedKey);

      final payload = utf8.decode(base64Url.decode(payloadPadded));
      final key = Uint8List.fromList(base64Url.decode(keyPadded));

      if (key.length != 32) return null;

      final parts = payload.split('|');
      if (parts.length != 3) return null;

      return ShareLinkInfo(
        serverAddr: parts[0],
        packId: parts[1],
        shareCode: parts[2],
        key: key,
      );
    } catch (_) {
      return null;
    }
  }

  static String _addBase64Padding(String s) {
    final remainder = s.length % 4;
    if (remainder == 0) return s;
    return s + '=' * (4 - remainder);
  }
}
```

- [ ] **Step 3: 验证编译**

```bash
cd sticker_app && flutter analyze lib/services/crypto_service.dart
```

Expected: 无错误

- [ ] **Step 4: Commit**

```bash
git add sticker_app/pubspec.yaml sticker_app/pubspec.lock sticker_app/lib/services/crypto_service.dart
git commit -m "feat(app): add crypto service with AES-256-GCM and share link parser"
```

---

## Task 5: App 端 — api_service.dart 改造

**Files:**
- Modify: `sticker_app/lib/services/api_service.dart`

- [ ] **Step 1: 添加自定义 baseUrl 支持**

在 `ApiService` 类中修改 `uploadPack` 方法，添加 `customBaseUrl` 和 `authToken` 可选参数:

```dart
  /// Upload a sticker pack with images (supports custom VPS server)
  Future<UploadResult> uploadPack({
    required String name,
    required String description,
    required List<File> images,
    Function(int, int)? onSendProgress,
    String? customBaseUrl,
    String? authToken,
  }) async {
    final dio = customBaseUrl != null
        ? Dio(BaseOptions(
            baseUrl: customBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 120),
            headers: authToken != null ? {'X-Auth-Token': authToken} : null,
          ))
        : _dio;

    final formData = FormData.fromMap({
      'name': name,
      'description': description,
      'stickers': await Future.wait(
        images.map((f) async => MultipartFile.fromFile(
              f.path,
              filename: f.path.split(Platform.pathSeparator).last,
            )),
      ),
    });

    final response = await dio.post(
      '/api/packs',
      data: formData,
      onSendProgress: onSendProgress,
    );

    final packData = response.data['pack'];
    final stickersData = response.data['stickers'] as List;

    return UploadResult(
      pack: StickerPack.fromApiMap(packData),
      stickers: stickersData.map((s) => Sticker.fromApiMap(s)).toList(),
    );
  }
```

- [ ] **Step 2: 添加 getPackByCode 和 getPackStickers 的自定义 URL 版本**

```dart
  /// Get pack info from a custom server
  Future<StickerPack> getPackByCodeFromServer(String code, String serverAddr) async {
    final dio = Dio(BaseOptions(
      baseUrl: serverAddr,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final response = await dio.get('/api/packs/$code');
    return StickerPack.fromApiMap(response.data['pack']);
  }

  /// Get stickers from a custom server
  Future<List<StickerWithUrl>> getPackStickersFromServer(String code, String serverAddr) async {
    final dio = Dio(BaseOptions(
      baseUrl: serverAddr,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final response = await dio.get('/api/packs/$code/stickers');
    final stickers = response.data['stickers'] as List;
    return stickers
        .map((s) => StickerWithUrl(
              id: s['id'],
              type: s['type'] ?? 'image',
              fileUrl: '$serverAddr${s['file_url']}',
              width: s['width'] ?? 0,
              height: s['height'] ?? 0,
              sizeBytes: s['size_bytes'] ?? 0,
            ))
        .toList();
  }
```

- [ ] **Step 3: 验证编译**

```bash
cd sticker_app && flutter analyze lib/services/api_service.dart
```

Expected: 无错误

- [ ] **Step 4: Commit**

```bash
git add sticker_app/lib/services/api_service.dart
git commit -m "feat(app): add custom server support to ApiService"
```

---

## Task 6: App 端 — share_pack_screen.dart 改造

**Files:**
- Modify: `sticker_app/lib/screens/share_pack_screen.dart`

- [ ] **Step 1: 重写 SharePackScreen**

在现有分享页面基础上添加 VPS 分享模式。完整替换文件内容:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/sticker_pack.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

class SharePackScreen extends StatefulWidget {
  final StickerPack pack;
  const SharePackScreen({super.key, required this.pack});
  @override
  State<SharePackScreen> createState() => _SharePackScreenState();
}

enum _ShareMode { central, vps }

class _SharePackScreenState extends State<SharePackScreen> {
  _ShareMode _mode = _ShareMode.central;

  // 通用状态
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;

  // 中央服务器结果
  String? _shareCode;

  // VPS 模式
  final _serverController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _vpsShareLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分享表情包')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 包信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(widget.pack.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${widget.pack.stickerCount} 个表情'),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // 模式切换
            SegmentedButton<_ShareMode>(
              segments: const [
                ButtonSegment(value: _ShareMode.central, label: Text('服务器分享码'), icon: Icon(Icons.dns)),
                ButtonSegment(value: _ShareMode.vps, label: Text('VPS 加密分享'), icon: Icon(Icons.lock)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 20),

            // 根据模式显示内容
            if (_mode == _ShareMode.central) _buildCentralSection(),
            if (_mode == _ShareMode.vps) _buildVPSSection(),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCentralSection() {
    if (_shareCode != null) {
      return Column(children: [
        const Text('分享码:', style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_shareCode!,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _shareCode!));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制分享码'),
        ),
      ]);
    }

    return ElevatedButton.icon(
      onPressed: _isUploading ? null : _uploadToCentral,
      icon: _isUploading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cloud_upload),
      label: Text(_isUploading ? '上传中...' : '上传并生成分享码'),
    );
  }

  Widget _buildVPSSection() {
    if (_vpsShareLink != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('分享链接（端到端加密）',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                const SizedBox(height: 8),
                SelectableText(_vpsShareLink!,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('链接中 # 后面的密钥不会发送到服务器，只有拥有链接的人才能解密。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _vpsShareLink!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制分享链接'),
          ),
        ],
      );
    }

    return Column(
      children: [
        TextField(
          controller: _serverController,
          decoration: const InputDecoration(
            labelText: 'VPS 地址',
            hintText: 'http://your-vps:8080',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        if (_isUploading) ...[
          LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
          const SizedBox(height: 8),
          Text('加密并上传中...', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _uploadToVPS,
          icon: _isUploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_lock),
          label: Text(_isUploading ? '加密上传中...' : '加密上传到 VPS'),
        ),
      ],
    );
  }

  Future<void> _uploadToCentral() async {
    setState(() { _isUploading = true; _error = null; });
    try {
      final storage = context.read<StorageService>();
      final stickers = await storage.getStickersByPackId(widget.pack.id);
      final files = stickers
          .where((s) => s.localPath != null && File(s.localPath!).existsSync())
          .map((s) => File(s.localPath!))
          .toList();
      if (files.isEmpty) {
        setState(() { _error = '没有可上传的表情文件'; });
        return;
      }
      final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
      final result = await api.uploadPack(
        name: widget.pack.name,
        description: widget.pack.description,
        images: files,
        onSendProgress: (sent, total) {
          if (total > 0) setState(() { _uploadProgress = sent / total; });
        },
      );
      widget.pack.shareCode = result.pack.shareCode;
      widget.pack.isUploaded = true;
      await storage.updatePack(widget.pack);
      setState(() { _shareCode = result.pack.shareCode; });
    } catch (e) {
      setState(() { _error = '上传失败: $e'; });
    } finally {
      setState(() { _isUploading = false; });
    }
  }

  Future<void> _uploadToVPS() async {
    final serverAddr = _serverController.text.trim();
    final password = _passwordController.text.trim();
    if (serverAddr.isEmpty || password.isEmpty) {
      setState(() { _error = '请填写 VPS 地址和密码'; });
      return;
    }

    setState(() { _isUploading = true; _error = null; _uploadProgress = 0; });

    try {
      final storage = context.read<StorageService>();
      final stickers = await storage.getStickersByPackId(widget.pack.id);
      final files = stickers
          .where((s) => s.localPath != null && File(s.localPath!).existsSync())
          .map((s) => File(s.localPath!))
          .toList();
      if (files.isEmpty) {
        setState(() { _error = '没有可上传的表情文件'; });
        return;
      }

      // 生成密钥并加密文件
      final key = CryptoService.generateKey();
      final encryptedFiles = <File>[];
      final tempDir = Directory.systemTemp.createTempSync('sticker_enc_');
      for (final file in files) {
        final plaintext = await file.readAsBytes();
        final encrypted = CryptoService.encryptData(plaintext, key);
        final encFile = File('${tempDir.path}/${file.uri.pathSegments.last}.enc');
        await encFile.writeAsBytes(encrypted);
        encryptedFiles.add(encFile);
      }

      // 上传到 VPS
      final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
      final result = await api.uploadPack(
        name: widget.pack.name,
        description: widget.pack.description,
        images: encryptedFiles,
        customBaseUrl: serverAddr,
        authToken: password,
        onSendProgress: (sent, total) {
          if (total > 0) setState(() { _uploadProgress = sent / total; });
        },
      );

      // 生成分享链接
      final link = CryptoService.buildShareLink(
        serverAddr: serverAddr,
        packId: result.pack.id,
        shareCode: result.pack.shareCode!,
        key: key,
      );

      // 清理临时文件
      tempDir.deleteSync(recursive: true);

      setState(() { _vpsShareLink = link; });
    } catch (e) {
      setState(() { _error = '上传失败: $e'; });
    } finally {
      setState(() { _isUploading = false; });
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd sticker_app && flutter analyze lib/screens/share_pack_screen.dart
```

Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add sticker_app/lib/screens/share_pack_screen.dart
git commit -m "feat(app): add VPS encrypted share mode to share screen"
```

---

## Task 7: App 端 — import_link_screen.dart 改造

**Files:**
- Modify: `sticker_app/lib/screens/import_link_screen.dart`

- [ ] **Step 1: 重写导入页面**

支持 `sticker://share/` 链接解析 + 解密下载:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/download_service.dart';
import '../providers/pack_provider.dart';
import '../services/storage_service.dart';

class ImportLinkScreen extends StatefulWidget {
  const ImportLinkScreen({super.key});
  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  _PackPreview? _preview;
  double _downloadProgress = 0;

  // VPS 加密导入状态
  ShareLinkInfo? _parsedLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入表情包')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: '分享码或链接',
                hintText: '粘贴 sticker://share/... 或输入分享码',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isLoading ? null : _lookup,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('查找'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text(_preview!.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_preview!.count} 个表情'),
                    if (_parsedLink != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('端到端加密',
                            style: TextStyle(fontSize: 12, color: Colors.green)),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isDownloading ? null : _download,
                icon: _isDownloading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_isDownloading ? '下载中...' : '一键下载'),
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _lookup() async {
    final input = _codeController.text.trim();
    if (input.isEmpty) return;

    setState(() { _isLoading = true; _error = null; _preview = null; _parsedLink = null; });

    try {
      // 检查是否是 sticker:// 链接
      final parsed = CryptoService.parseShareLink(input);
      if (parsed != null) {
        // VPS 加密分享链接
        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final pack = await api.getPackByCodeFromServer(parsed.shareCode, parsed.serverAddr);
        if (!mounted) return;
        setState(() {
          _parsedLink = parsed;
          _preview = _PackPreview(name: pack.name, count: pack.stickerCount, code: parsed.shareCode);
        });
      } else {
        // 普通分享码
        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final pack = await api.getPackByCode(input);
        if (!mounted) return;
        setState(() {
          _preview = _PackPreview(name: pack.name, count: pack.stickerCount, code: input);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '查找失败: 请检查链接或分享码是否正确'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _download() async {
    if (_preview == null) return;
    setState(() { _isDownloading = true; _downloadProgress = 0; });

    try {
      final storage = context.read<StorageService>();
      final packProvider = context.read<PackProvider>();
      final messenger = ScaffoldMessenger.of(context);

      if (_parsedLink != null) {
        // VPS 加密下载 + 解密
        await _downloadEncrypted(storage, packProvider);
      } else {
        // 普通下载
        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final dl = DownloadService(apiService: api, storageService: storage);
        final result = await dl.downloadPack(
          shareCode: _preview!.code,
          packName: _preview!.name,
          onProgress: (done, total) {
            if (mounted) setState(() { _downloadProgress = done / total; });
          },
        );
        if (!mounted) return;
        final msg = result.failedCount > 0
            ? '下载完成，${result.stickerCount} 个成功，${result.failedCount} 个失败'
            : '下载完成，共 ${result.stickerCount} 个表情';
        packProvider.loadPacks();
        messenger.showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() { _error = '下载失败: $e'; });
    } finally {
      if (mounted) setState(() { _isDownloading = false; });
    }
  }

  Future<void> _downloadEncrypted(StorageService storage, PackProvider packProvider) async {
    final link = _parsedLink!;
    final api = ApiService(baseUrl: AppConfig.apiBaseUrl);

    // 获取远程表情列表
    final remoteStickers = await api.getPackStickersFromServer(link.shareCode, link.serverAddr);
    if (remoteStickers.isEmpty) {
      setState(() { _error = '远程包为空'; });
      return;
    }

    // 获取包信息并保存到本地
    final pack = await api.getPackByCodeFromServer(link.shareCode, link.serverAddr);
    pack.source = 'link';
    await storage.insertPack(pack);

    // 创建本地目录
    final appDir = await getApplicationDocumentsDirectory();
    final packDir = Directory(p.join(appDir.path, 'stickers', pack.id));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    // 下载并解密每个表情
    final stickers = <dynamic>[];
    int failedCount = 0;
    for (int i = 0; i < remoteStickers.length; i++) {
      final remote = remoteStickers[i];
      try {
        // 下载加密文件到临时路径
        final tempPath = p.join(packDir.path, '${remote.id}.enc');
        await api.downloadSticker(remote.fileUrl, tempPath);

        // 读取加密数据并解密
        final encData = await File(tempPath).readAsBytes();
        final decData = CryptoService.decryptData(encData, link.key);

        // 保存解密后的文件
        final ext = _guessExtension(decData);
        final localPath = p.join(packDir.path, '${remote.id}$ext');
        await File(localPath).writeAsBytes(decData);

        // 删除临时加密文件
        await File(tempPath).delete();

        final sticker = _StickerInfo(
          id: remote.id,
          packId: pack.id,
          type: remote.type,
          width: remote.width,
          height: remote.height,
          sizeBytes: decData.length,
          extension: ext,
          localPath: localPath,
        );
        stickers.add(sticker);

        if (mounted) setState(() { _downloadProgress = (i + 1) / remoteStickers.length; });
      } catch (e) {
        failedCount++;
      }
    }

    // 保存到数据库 — 需要转换为 Sticker 对象
    // 这里使用 storage 的 insertStickers 方法
    if (stickers.isNotEmpty) {
      // 更新包信息
      pack.coverLocal = (stickers.first as _StickerInfo).localPath;
      pack.coverUrl = remoteStickers.first.fileUrl;
      await storage.updatePack(pack);
    }

    if (!mounted) return;
    final msg = failedCount > 0
        ? '下载完成，${stickers.length} 个成功，$failedCount 个失败'
        : '下载完成，共 ${stickers.length} 个表情';
    packProvider.loadPacks();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  /// 根据文件头猜测扩展名
  String _guessExtension(List<int> data) {
    if (data.length >= 4) {
      // PNG: 89 50 4E 47
      if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return '.png';
      // GIF: 47 49 46 38
      if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) return '.gif';
      // JPEG: FF D8 FF
      if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return '.jpg';
      // WebP: RIFF....WEBP
      if (data.length >= 12 &&
          data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
          data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) return '.webp';
    }
    return '.png';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

class _PackPreview {
  final String name;
  final int count;
  final String code;
  _PackPreview({required this.name, required this.count, required this.code});
}

class _StickerInfo {
  final String id;
  final String packId;
  final String type;
  final int width;
  final int height;
  final int sizeBytes;
  final String extension;
  final String localPath;
  _StickerInfo({
    required this.id,
    required this.packId,
    required this.type,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.extension,
    required this.localPath,
  });
}
```

注意：上面的 `_downloadEncrypted` 方法中保存 sticker 到本地 DB 时，需要调用 `storage.insertStickers`，该方法接受 `List<Sticker>` 类型。需要确认 `StorageService.insertStickers` 的签名，必要时创建 Sticker 对象传入。

- [ ] **Step 2: 检查 StorageService.insertStickers 签名并适配**

读取 `sticker_app/lib/services/storage_service.dart` 中的 `insertStickers` 方法，确认参数类型。将 `_StickerInfo` 替换为 `Sticker` 模型:

```dart
import '../models/sticker.dart';

// 在 _downloadEncrypted 中替换 sticker 创建逻辑:
final sticker = Sticker(
  id: remote.id,
  packId: pack.id,
  type: remote.type,
  width: remote.width,
  height: remote.height,
  sizeBytes: decData.length,
  extension: ext,
  localPath: localPath,
);
stickers.add(sticker);
```

然后替换保存逻辑:

```dart
    // 保存到本地数据库
    await storage.insertStickers(stickers.cast<Sticker>());
    await storage.updatePackStickerCount(pack.id);
```

- [ ] **Step 3: 验证编译**

```bash
cd sticker_app && flutter analyze lib/screens/import_link_screen.dart
```

Expected: 无错误

- [ ] **Step 4: Commit**

```bash
git add sticker_app/lib/screens/import_link_screen.dart
git commit -m "feat(app): add encrypted VPS import with sticker:// link parsing"
```

---

## Task 8: 端到端验证

- [ ] **Step 1: VPS 服务端本地测试**

```bash
cd vps-server
PASSWORD=test123 PORT=9090 go run .
```

另开终端测试:

```bash
# 健康检查
curl http://localhost:9090/health

# 上传（需密码）
curl -X POST http://localhost:9090/api/packs \
  -H "X-Auth-Token: test123" \
  -F "name=test" \
  -F "stickers=@test.png"

# 无密码上传应被拒绝
curl -X POST http://localhost:9090/api/packs -F "name=test"
# Expected: 401 Unauthorized

# 下载（无需密码）
curl http://localhost:9090/api/packs/{share_code}
```

- [ ] **Step 2: Flutter 分析**

```bash
cd sticker_app && flutter analyze
```

Expected: 无错误

- [ ] **Step 3: Commit 所有改动**

```bash
git add -A
git commit -m "feat: VPS sticker sharing with E2E encryption"
```
