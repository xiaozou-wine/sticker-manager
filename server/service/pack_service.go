package service

import (
	"crypto/rand"
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
	if err := s.db.CreateSticker(sticker); err != nil {
		return err
	}
	return s.db.IncrementPackCount(packID, 1)
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
	rand.Read(b)
	return hex.EncodeToString(b)
}

func generateShareCode() string {
	b := make([]byte, 4)
	rand.Read(b)
	return hex.EncodeToString(b)
}
