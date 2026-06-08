package service

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"sticker-server/model"
	"sticker-server/store"
	"time"
)

type PackService struct {
	db       *store.DB
	baseURL  string
}

func NewPackService(db *store.DB, baseURL string) *PackService {
	return &PackService{db: db, baseURL: baseURL}
}

func (s *PackService) CreatePack(name, description string) (*model.StickerPack, error) {
	pack := &model.StickerPack{
		ID:          generateID(),
		Name:        name,
		Description: description,
		ShareCode:   generateShareCode(),
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
	if err := s.db.CreatePack(pack); err != nil {
		return nil, err
	}
	return pack, nil
}

func (s *PackService) GetPackByCode(code string) (*model.StickerPack, error) {
	return s.db.GetPackByShareCode(code)
}

func (s *PackService) GetPackByID(id string) (*model.StickerPack, error) {
	return s.db.GetPackByID(id)
}

func (s *PackService) DeletePack(id string) error {
	return s.db.DeletePack(id)
}

func (s *PackService) AddSticker(packID, stickerID, fileType, ext string, width, height int, sizeBytes int64) error {
	sticker := &model.Sticker{
		ID:        stickerID,
		PackID:    packID,
		Type:      fileType,
		Width:     width,
		Height:    height,
		SizeBytes: sizeBytes,
		Extension: ext,
		CreatedAt: time.Now(),
	}
	// #18 Wrap in transaction
	return s.db.Tx(func(tx *sql.Tx) error {
		_, err := tx.Exec(
			`INSERT INTO stickers (id, pack_id, type, width, height, size_bytes, extension, created_at)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			sticker.ID, sticker.PackID, sticker.Type, sticker.Width, sticker.Height, sticker.SizeBytes, sticker.Extension, sticker.CreatedAt,
		)
		if err != nil {
			return err
		}
		_, err = tx.Exec(
			"UPDATE sticker_packs SET sticker_count = sticker_count + 1, updated_at = ? WHERE id = ?",
			time.Now(), packID,
		)
		return err
	})
}

func (s *PackService) GetStickersByPackID(packID string) ([]model.Sticker, error) {
	return s.db.GetStickersByPackID(packID)
}

func (s *PackService) GetStickerByID(id string) (*model.Sticker, error) {
	return s.db.GetStickerByID(id)
}

func (s *PackService) SetPackCover(packID, stickerID, ext string) error {
	coverURL := "/api/stickers/" + stickerID + "/file"
	return s.db.UpdatePackCover(packID, coverURL)
}

func (s *PackService) GetBaseURL() string {
	return s.baseURL
}

func generateID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}

func generateShareCode() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}
