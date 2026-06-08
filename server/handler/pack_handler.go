package handler

import (
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

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
	name := c.PostForm("name")
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}
	description := c.PostForm("description")

	pack, err := h.packSvc.CreatePack(name, description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create storage dir"})
		return
	}

	var uploaded []map[string]interface{}
	for i, file := range files {
		ext := strings.ToLower(filepath.Ext(file.Filename))
		if !isValidImageExt(ext) {
			continue
		}

		// Save file
		stickerID := fmt.Sprintf("%s_%d", pack.ID, i)
		savePath := filepath.Join(packDir, stickerID+ext)
		if err := c.SaveUploadedFile(file, savePath); err != nil {
			continue
		}

		// Detect image dimensions
		width, height := detectImageSize(savePath)
		fileType := "image"
		if ext == ".gif" {
			fileType = "gif"
		}

		// Record in DB
		err := h.packSvc.AddSticker(pack.ID, stickerID, fileType, ext, width, height, file.Size)
		if err != nil {
			continue
		}

		// Set first image as cover
		if i == 0 {
			h.packSvc.SetPackCover(pack.ID, stickerID, ext)
		}

		uploaded = append(uploaded, map[string]interface{}{
			"id":        stickerID,
			"type":      fileType,
			"width":     width,
			"height":    height,
			"file_url":  "/api/stickers/" + stickerID + "/file",
		})
	}

	// Refresh pack info
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	baseURL := h.packSvc.GetBaseURL()
	type stickerResp struct {
		ID       string `json:"id"`
		Type     string `json:"type"`
		FileURL  string `json:"file_url"`
		Width    int    `json:"width"`
		Height   int    `json:"height"`
		SizeBytes int64 `json:"size_bytes"`
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
	sticker, err := h.packSvc.GetStickerByID(id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "sticker not found"})
		return
	}

	// Find the file - try different paths
	parts := strings.SplitN(id, "_", 2)
	if len(parts) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid sticker id"})
		return
	}
	packID := parts[0]

	filePath := filepath.Join(h.staticDir, "stickers", packID, id+sticker.Extension)
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

	// Delete from DB (cascades to stickers)
	if err := h.packSvc.DeletePack(pack.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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

func detectImageSize(path string) (int, int) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0
	}
	defer f.Close()

	// Limit read to header only
	r := io.LimitReader(f, 1024*1024) // 1MB should be enough for header
	cfg, _, err := image.DecodeConfig(r)
	if err != nil {
		return 0, 0
	}
	return cfg.Width, cfg.Height
}
