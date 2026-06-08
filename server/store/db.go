package store

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

type DB struct {
	conn *sql.DB
}

func New(dbPath string) (*DB, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	conn, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL")
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

func (db *DB) Close() error {
	return db.conn.Close()
}

func (db *DB) Tx(fn func(tx *sql.Tx) error) error {
	tx, err := db.conn.Begin()
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func (db *DB) migrate() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS sticker_packs (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			cover_url TEXT DEFAULT '',
			share_code TEXT UNIQUE NOT NULL,
			sticker_count INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS stickers (
			id TEXT PRIMARY KEY,
			pack_id TEXT NOT NULL,
			type TEXT NOT NULL DEFAULT 'image',
			width INTEGER DEFAULT 0,
			height INTEGER DEFAULT 0,
			size_bytes INTEGER DEFAULT 0,
			extension TEXT DEFAULT '.png',
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (pack_id) REFERENCES sticker_packs(id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_stickers_pack_id ON stickers(pack_id)`,
		`CREATE INDEX IF NOT EXISTS idx_packs_share_code ON sticker_packs(share_code)`,
	}

	for _, q := range queries {
		if _, err := db.conn.Exec(q); err != nil {
			return fmt.Errorf("exec migration: %w", err)
		}
	}

	// Enable foreign keys
	_, err := db.conn.Exec("PRAGMA foreign_keys = ON")
	return err
}
