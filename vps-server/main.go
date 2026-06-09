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
	port := envOr("PORT", "28749")
	dataDir := envOr("DATA_DIR", "./data")
	staticDir := filepath.Join(dataDir, "stickers")
	os.MkdirAll(staticDir, 0755)

	db, err := NewDB(filepath.Join(dataDir, "stickers.db"))
	if err != nil {
		log.Fatalf("init db: %v", err)
	}
	defer db.Close()

	r := gin.Default()
	r.Use(cors())
	r.MaxMultipartMemory = 50 << 20

	api := r.Group("/api")
	api.GET("/packs/:code", getPack(db))
	api.GET("/packs/:code/stickers", getPackStickers(db))
	api.GET("/stickers/:id/file", getStickerFile(db, staticDir))

	auth := api.Group("", authMW(password))
	auth.POST("/packs", createPack(db, staticDir))
	auth.DELETE("/packs/:code", deletePack(db, staticDir))

	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })

	log.Printf("Sticker VPS server on :%s", port)
	r.Run(":" + port)
}

// --- Middleware ---

func authMW(password string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("X-Auth-Token") != password {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			c.Abort()
			return
		}
		c.Next()
	}
}

func cors() gin.HandlerFunc {
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

func createPack(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		name := sanitize(c.PostForm("name"))
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name required"})
			return
		}
		pack := &StickerPack{
			ID: genID(), Name: name, Description: sanitize(c.PostForm("description")),
			ShareCode: genID()[:16], CreatedAt: time.Now(), UpdatedAt: time.Now(),
		}
		if err := db.CreatePack(pack); err != nil {
			c.JSON(500, gin.H{"error": "create pack failed"})
			return
		}

		form, err := c.MultipartForm()
		if err != nil {
			db.DeletePack(pack.ID)
			c.JSON(400, gin.H{"error": "invalid form"})
			return
		}
		files := form.File["stickers"]
		if len(files) == 0 {
			db.DeletePack(pack.ID)
			c.JSON(400, gin.H{"error": "no stickers"})
			return
		}

		packDir := filepath.Join(staticDir, pack.ID)
		os.MkdirAll(packDir, 0755)

		var uploaded []gin.H
		for i, file := range files {
			ext := filepath.Ext(file.Filename)
			if ext == "" {
				ext = ".bin"
			}
			sid := fmt.Sprintf("%s_%d", pack.ID, i)
			savePath := filepath.Join(packDir, sid+ext)
			if err := c.SaveUploadedFile(file, savePath); err != nil {
				continue
			}
			st := &Sticker{
				ID: sid, PackID: pack.ID, Type: "image",
				SizeBytes: file.Size, Extension: ext, CreatedAt: time.Now(),
			}
			if err := db.CreateSticker(st); err != nil {
				continue
			}
			if len(uploaded) == 0 {
				db.UpdatePackCover(pack.ID, st.FileURL())
			}
			uploaded = append(uploaded, gin.H{"id": sid, "type": "image", "file_url": st.FileURL()})
		}

		if len(uploaded) == 0 {
			os.RemoveAll(packDir)
			db.DeletePack(pack.ID)
			c.JSON(400, gin.H{"error": "all uploads failed"})
			return
		}
		db.IncrementPackCount(pack.ID, len(uploaded))
		updatedPack, _ := db.GetPackByID(pack.ID)
		c.JSON(201, gin.H{"pack": updatedPack, "stickers": uploaded})
	}
}

func getPack(db *DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		pack, err := db.GetPackByShareCode(c.Param("code"))
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		pack.CoverURL = baseURL(c) + pack.CoverURL
		c.JSON(200, gin.H{"pack": pack})
	}
}

func getPackStickers(db *DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		pack, err := db.GetPackByShareCode(c.Param("code"))
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		stickers, err := db.GetStickersByPackID(pack.ID)
		if err != nil {
			c.JSON(500, gin.H{"error": "load stickers failed"})
			return
		}
		base := baseURL(c)
		type sr struct {
			ID        string `json:"id"`
			Type      string `json:"type"`
			FileURL   string `json:"file_url"`
			SizeBytes int64  `json:"size_bytes"`
		}
		var resp []sr
		for _, s := range stickers {
			resp = append(resp, sr{s.ID, s.Type, base + s.FileURL(), s.SizeBytes})
		}
		c.JSON(200, gin.H{"pack_id": pack.ID, "stickers": resp})
	}
}

func getStickerFile(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		if !isSafeID(id) {
			c.JSON(400, gin.H{"error": "invalid id"})
			return
		}
		st, err := db.GetStickerByID(id)
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		fp := filepath.Join(staticDir, st.PackID, id+st.Extension)
		absS, _ := filepath.Abs(staticDir)
		absF, _ := filepath.Abs(fp)
		if !strings.HasPrefix(absF, absS) {
			c.JSON(403, gin.H{"error": "forbidden"})
			return
		}
		if _, err := os.Stat(fp); os.IsNotExist(err) {
			c.JSON(404, gin.H{"error": "file not found"})
			return
		}
		c.Header("Content-Type", "application/octet-stream")
		c.Header("Cache-Control", "public, max-age=31536000")
		c.File(fp)
	}
}

func deletePack(db *DB, staticDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		pack, err := db.GetPackByShareCode(c.Param("code"))
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		os.RemoveAll(filepath.Join(staticDir, pack.ID))
		db.DeletePack(pack.ID)
		c.JSON(200, gin.H{"message": "deleted"})
	}
}

// --- Helpers ---

func baseURL(c *gin.Context) string {
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

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
