package model

import "time"

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
