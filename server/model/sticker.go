package model

import "time"

type Sticker struct {
	ID        string    `json:"id"`
	PackID    string    `json:"pack_id"`
	Type      string    `json:"type"` // image or gif
	Width     int       `json:"width"`
	Height    int       `json:"height"`
	SizeBytes int64     `json:"size_bytes"`
	Extension string    `json:"extension"` // .jpg, .png, .gif
	CreatedAt time.Time `json:"created_at"`
}

func (s Sticker) FileURL() string {
	return "/api/stickers/" + s.ID + "/file"
}
