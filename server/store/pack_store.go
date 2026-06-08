package store

import (
	"fmt"
	"sticker-server/model"
	"time"
)

func (db *DB) CreatePack(pack *model.StickerPack) error {
	_, err := db.conn.Exec(
		`INSERT INTO sticker_packs (id, name, description, cover_url, share_code, sticker_count, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		pack.ID, pack.Name, pack.Description, pack.CoverURL, pack.ShareCode, pack.StickerCount, pack.CreatedAt, pack.UpdatedAt,
	)
	return err
}

func (db *DB) GetPackByShareCode(code string) (*model.StickerPack, error) {
	pack := &model.StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id, name, description, cover_url, share_code, sticker_count, created_at, updated_at
		 FROM sticker_packs WHERE share_code = ?`, code,
	).Scan(&pack.ID, &pack.Name, &pack.Description, &pack.CoverURL, &pack.ShareCode, &pack.StickerCount, &pack.CreatedAt, &pack.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("pack not found: %w", err)
	}
	return pack, nil
}

func (db *DB) GetPackByID(id string) (*model.StickerPack, error) {
	pack := &model.StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id, name, description, cover_url, share_code, sticker_count, created_at, updated_at
		 FROM sticker_packs WHERE id = ?`, id,
	).Scan(&pack.ID, &pack.Name, &pack.Description, &pack.CoverURL, &pack.ShareCode, &pack.StickerCount, &pack.CreatedAt, &pack.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("pack not found: %w", err)
	}
	return pack, nil
}

func (db *DB) DeletePack(id string) error {
	// Stickers will be cascade deleted
	_, err := db.conn.Exec("DELETE FROM sticker_packs WHERE id = ?", id)
	return err
}

func (db *DB) UpdatePackCover(id, coverURL string) error {
	_, err := db.conn.Exec(
		"UPDATE sticker_packs SET cover_url = ?, updated_at = ? WHERE id = ?",
		coverURL, time.Now(), id,
	)
	return err
}

func (db *DB) IncrementPackCount(id string, delta int) error {
	_, err := db.conn.Exec(
		"UPDATE sticker_packs SET sticker_count = sticker_count + ?, updated_at = ? WHERE id = ?",
		delta, time.Now(), id,
	)
	return err
}
