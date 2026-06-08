package handler

import (
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"github.com/gin-gonic/gin"
	"sticker-server/service"
)

type PackHandler struct {
	packSvc   *service.PackService
	staticDir string
}

func NewPackHandler(packSvc *service.PackService, staticDir string) *PackHandler {
	return &PackHandler{packSvc: packSvc, staticDir: staticDir}
}

// CreatePack handles POST /api/packs
func (h *PackHandler) CreatePack(c *gin.Context) {
	name := sanitizeInput(c.PostForm("name"))
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}
	description := sanitizeInput(c.PostForm("description"))

	pack, err := h.packSvc.CreatePack(name, description)
	if err != nil {
		log.Printf("CreatePack error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create pack"})
		return
	}

	// Handle multipart file uploads
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid multipart form"})
		return
	}

	files := form.File["stickers"]
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one sticker file required"})
		return
	}
	if len(files) > 50 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "max 50 stickers per upload"})
		return
	}

	packDir := filepath.Join(h.staticDir, "stickers", pack.ID)
	if err := os.MkdirAll(packDir, 0755); err != nil {
		log.Printf("CreatePack mkdir error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create storage dir"})
		return
	}

	var uploaded []map[string]interface{}
	var savedFiles []string // track for rollback
	for i, file := range files {
		ext := strings.ToLower(filepath.Ext(file.Filename))
		if !isValidImageExt(ext) {
			continue
		}

		// Save file
		stickerID := fmt.Sprintf("%s_%d", pack.ID, i)
		savePath := filepath.Join(packDir, stickerID+ext)
		if err := c.SaveUploadedFile(file, savePath); err != nil {
			log.Printf("CreatePack save file error: %v", err)
			continue
		}
		savedFiles = append(savedFiles, savePath)

		// Detect image dimensions
		width, height := detectImageSize(savePath)
		fileType := "image"
		if ext == ".gif" {
			fileType = "gif"
		}

		// Record in DB
		if err := h.packSvc.AddSticker(pack.ID, stickerID, fileType, ext, width, height, file.Size); err != nil {
			log.Printf("CreatePack add sticker error: %v", err)
			continue
		}

		// Set first image as cover
		if len(uploaded) == 0 {
			h.packSvc.SetPackCover(pack.ID, stickerID, ext)
		}

		uploaded = append(uploaded, map[string]interface{}{
			"id":        stickerID,
			"type":      fileType,
			"width":     width,
			"height":    height,
			"size_bytes": file.Size,
			"extension": ext,
			"file_url":  "/api/stickers/" + stickerID + "/file",
		})
	}

	// #5 Rollback: if all uploads failed, delete the empty pack
	if len(uploaded) == 0 {
		os.RemoveAll(packDir)
		h.packSvc.DeletePack(pack.ID)
		c.JSON(http.StatusBadRequest, gin.H{"error": "all sticker uploads failed"})
		return
	}

	updatedPack, _ := h.packSvc.GetPackByID(pack.ID)

	c.JSON(http.StatusCreated, gin.H{
		"pack":     updatedPack,
		"stickers": uploaded,
	})
}

// GetPack handles GET /api/packs/:code
func (h *PackHandler) GetPack(c *gin.Context) {
	code := c.Param("code")
	pack, err := h.packSvc.GetPackByCode(code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
		return
	}

	baseURL := h.packSvc.GetBaseURL()
	pack.CoverURL = baseURL + pack.CoverURL

	c.JSON(http.StatusOK, gin.H{"pack": pack})
}

// GetPackStickers handles GET /api/packs/:code/stickers
func (h *PackHandler) GetPackStickers(c *gin.Context) {
	code := c.Param("code")
	pack, err := h.packSvc.GetPackByCode(code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
		return
	}

	stickers, err := h.packSvc.GetStickersByPackID(pack.ID)
	if err != nil {
		log.Printf("GetPackStickers error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load stickers"})
		return
	}

	baseURL := h.packSvc.GetBaseURL()
	type stickerResp struct {
		ID        string `json:"id"`
		Type      string `json:"type"`
		FileURL   string `json:"file_url"`
		Width     int    `json:"width"`
		Height    int    `json:"height"`
		SizeBytes int64  `json:"size_bytes"`
		Extension string `json:"extension"`
	}

	var resp []stickerResp
	for _, s := range stickers {
		resp = append(resp, stickerResp{
			ID:        s.ID,
			Type:      s.Type,
			FileURL:   baseURL + s.FileURL(),
			Width:     s.Width,
			Height:    s.Height,
			SizeBytes: s.SizeBytes,
			Extension: s.Extension,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"pack_id":  pack.ID,
		"stickers": resp,
	})
}

// GetStickerFile handles GET /api/stickers/:id/file
func (h *PackHandler) GetStickerFile(c *gin.Context) {
	id := c.Param("id")

	// #1 Path traversal: validate ID contains only safe chars
	if !isSafeID(id) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid sticker id"})
		return
	}

	sticker, err := h.packSvc.GetStickerByID(id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "sticker not found"})
		return
	}

	// Build file path using pack ID from sticker record (not from user input)
	packID := sticker.PackID
	filePath := filepath.Join(h.staticDir, "stickers", packID, id+sticker.Extension)

	// #1 Double-check resolved path is within static dir
	absStatic, _ := filepath.Abs(h.staticDir)
	absFile, _ := filepath.Abs(filePath)
	if !strings.HasPrefix(absFile, absStatic) {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "file not found"})
		return
	}

	contentType := "image/png"
	switch sticker.Extension {
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".gif":
		contentType = "image/gif"
	}

	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=31536000")
	c.File(filePath)
}

// DeletePack handles DELETE /api/packs/:code
func (h *PackHandler) DeletePack(c *gin.Context) {
	code := c.Param("code")
	pack, err := h.packSvc.GetPackByCode(code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
		return
	}

	// Delete files
	packDir := filepath.Join(h.staticDir, "stickers", pack.ID)
	os.RemoveAll(packDir)

	if err := h.packSvc.DeletePack(pack.ID); err != nil {
		log.Printf("DeletePack error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete pack"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

func isValidImageExt(ext string) bool {
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif":
		return true
	}
	return false
}

// #1 Path traversal prevention
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

// #15 Sanitize user input
func sanitizeInput(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 256 {
		s = s[:256]
	}
	return s
}

func detectImageSize(path string) (int, int) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0
	}
	defer f.Close()

	// #12 Read only 4KB header instead of 1MB
	r := io.LimitReader(f, 4096)
	cfg, _, err := image.DecodeConfig(r)
	if err != nil {
		return 0, 0
	}
	return cfg.Width, cfg.Height
}
