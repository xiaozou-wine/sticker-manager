package store

import (
	"fmt"
	"sticker-server/model"
)

func (db *DB) CreateSticker(s *model.Sticker) error {
	_, err := db.conn.Exec(
		`INSERT INTO stickers (id, pack_id, type, width, height, size_bytes, extension, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.ID, s.PackID, s.Type, s.Width, s.Height, s.SizeBytes, s.Extension, s.CreatedAt,
	)
	return err
}

func (db *DB) GetStickersByPackID(packID string) ([]model.Sticker, error) {
	rows, err := db.conn.Query(
		`SELECT id, pack_id, type, width, height, size_bytes, extension, created_at
		 FROM stickers WHERE pack_id = ? ORDER BY created_at`, packID,
	)
	if err != nil {
		return nil, fmt.Errorf("query stickers: %w", err)
	}
	defer rows.Close()

	var stickers []model.Sticker
	for rows.Next() {
		var s model.Sticker
		if err := rows.Scan(&s.ID, &s.PackID, &s.Type, &s.Width, &s.Height, &s.SizeBytes, &s.Extension, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan sticker: %w", err)
		}
		stickers = append(stickers, s)
	}
	return stickers, rows.Err()
}

func (db *DB) GetStickerByID(id string) (*model.Sticker, error) {
	s := &model.Sticker{}
	err := db.conn.QueryRow(
		`SELECT id, pack_id, type, width, height, size_bytes, extension, created_at
		 FROM stickers WHERE id = ?`, id,
	).Scan(&s.ID, &s.PackID, &s.Type, &s.Width, &s.Height, &s.SizeBytes, &s.Extension, &s.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("sticker not found: %w", err)
	}
	return s, nil
}

func (db *DB) DeleteSticker(id string) error {
	_, err := db.conn.Exec("DELETE FROM stickers WHERE id = ?", id)
	return err
}

func (db *DB) DeleteStickersByPackID(packID string) error {
	_, err := db.conn.Exec("DELETE FROM stickers WHERE pack_id = ?", packID)
	return err
}
