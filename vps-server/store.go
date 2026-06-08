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
	conn, err := sql.Open("sqlite", path+"?_journal_mode=WAL")
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
	for _, q := range []string{
		`CREATE TABLE IF NOT EXISTS sticker_packs (
			id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '',
			cover_url TEXT DEFAULT '', share_code TEXT UNIQUE NOT NULL,
			sticker_count INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS stickers (
			id TEXT PRIMARY KEY, pack_id TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'image',
			width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, size_bytes INTEGER DEFAULT 0,
			extension TEXT DEFAULT '.bin', created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (pack_id) REFERENCES sticker_packs(id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_stickers_pack_id ON stickers(pack_id)`,
		`CREATE INDEX IF NOT EXISTS idx_packs_share_code ON sticker_packs(share_code)`,
	} {
		if _, err := db.conn.Exec(q); err != nil {
			return err
		}
	}
	_, err := db.conn.Exec("PRAGMA foreign_keys = ON")
	return err
}

// --- Models ---

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

func (s Sticker) FileURL() string { return "/api/stickers/" + s.ID + "/file" }

// --- Pack CRUD ---

func (db *DB) CreatePack(p *StickerPack) error {
	_, err := db.conn.Exec(
		`INSERT INTO sticker_packs (id,name,description,cover_url,share_code,sticker_count,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)`,
		p.ID, p.Name, p.Description, p.CoverURL, p.ShareCode, p.StickerCount, p.CreatedAt, p.UpdatedAt)
	return err
}

func (db *DB) GetPackByShareCode(code string) (*StickerPack, error) {
	p := &StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id,name,description,cover_url,share_code,sticker_count,created_at,updated_at FROM sticker_packs WHERE share_code=?`, code,
	).Scan(&p.ID, &p.Name, &p.Description, &p.CoverURL, &p.ShareCode, &p.StickerCount, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (db *DB) GetPackByID(id string) (*StickerPack, error) {
	p := &StickerPack{}
	err := db.conn.QueryRow(
		`SELECT id,name,description,cover_url,share_code,sticker_count,created_at,updated_at FROM sticker_packs WHERE id=?`, id,
	).Scan(&p.ID, &p.Name, &p.Description, &p.CoverURL, &p.ShareCode, &p.StickerCount, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (db *DB) DeletePack(id string) error {
	_, err := db.conn.Exec("DELETE FROM sticker_packs WHERE id=?", id)
	return err
}

func (db *DB) UpdatePackCover(id, coverURL string) error {
	_, err := db.conn.Exec("UPDATE sticker_packs SET cover_url=?, updated_at=? WHERE id=?", coverURL, time.Now(), id)
	return err
}

func (db *DB) IncrementPackCount(id string, delta int) error {
	_, err := db.conn.Exec("UPDATE sticker_packs SET sticker_count=sticker_count+?, updated_at=? WHERE id=?", delta, time.Now(), id)
	return err
}

// --- Sticker CRUD ---

func (db *DB) CreateSticker(s *Sticker) error {
	_, err := db.conn.Exec(
		`INSERT INTO stickers (id,pack_id,type,width,height,size_bytes,extension,created_at) VALUES (?,?,?,?,?,?,?,?)`,
		s.ID, s.PackID, s.Type, s.Width, s.Height, s.SizeBytes, s.Extension, s.CreatedAt)
	return err
}

func (db *DB) GetStickersByPackID(packID string) ([]Sticker, error) {
	rows, err := db.conn.Query(
		`SELECT id,pack_id,type,width,height,size_bytes,extension,created_at FROM stickers WHERE pack_id=? ORDER BY created_at`, packID)
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
		`SELECT id,pack_id,type,width,height,size_bytes,extension,created_at FROM stickers WHERE id=?`, id,
	).Scan(&s.ID, &s.PackID, &s.Type, &s.Width, &s.Height, &s.SizeBytes, &s.Extension, &s.CreatedAt)
	if err != nil {
		return nil, err
	}
	return s, nil
}
