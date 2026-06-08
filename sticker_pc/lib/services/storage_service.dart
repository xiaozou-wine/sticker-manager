import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class StorageService {
  static Database? _database;

  /// Must be called before using StorageService on desktop.
  static void initFfi() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sticker_pc.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sticker_packs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            cover_url TEXT,
            cover_local TEXT,
            source TEXT DEFAULT 'gallery',
            share_code TEXT,
            is_uploaded INTEGER DEFAULT 0,
            sticker_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE stickers (
            id TEXT PRIMARY KEY,
            pack_id TEXT NOT NULL,
            type TEXT DEFAULT 'image',
            width INTEGER DEFAULT 0,
            height INTEGER DEFAULT 0,
            size_bytes INTEGER DEFAULT 0,
            extension TEXT DEFAULT '.png',
            local_path TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (pack_id) REFERENCES sticker_packs(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_stickers_pack_id ON stickers(pack_id)');
      },
    );
  }

  // --- StickerPack CRUD ---

  Future<void> insertPack(StickerPack pack) async {
    final db = await database;
    await db.insert('sticker_packs', pack.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StickerPack>> getAllPacks() async {
    final db = await database;
    final maps = await db.query('sticker_packs', orderBy: 'updated_at DESC');
    return maps.map((m) => StickerPack.fromMap(m)).toList();
  }

  Future<StickerPack?> getPackById(String id) async {
    final db = await database;
    final maps =
        await db.query('sticker_packs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return StickerPack.fromMap(maps.first);
  }

  Future<void> updatePack(StickerPack pack) async {
    final db = await database;
    pack.updatedAt = DateTime.now();
    await db.update('sticker_packs', pack.toMap(),
        where: 'id = ?', whereArgs: [pack.id]);
  }

  Future<void> deletePack(String id) async {
    final db = await database;
    await db.delete('stickers', where: 'pack_id = ?', whereArgs: [id]);
    await db.delete('sticker_packs', where: 'id = ?', whereArgs: [id]);
  }

  // --- Sticker CRUD ---

  Future<void> insertStickers(List<Sticker> stickers) async {
    final db = await database;
    final batch = db.batch();
    for (final s in stickers) {
      batch.insert('stickers', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Sticker>> getStickersByPackId(String packId) async {
    final db = await database;
    final maps = await db.query('stickers',
        where: 'pack_id = ?', whereArgs: [packId], orderBy: 'created_at');
    return maps.map((m) => Sticker.fromMap(m)).toList();
  }

  Future<void> deleteSticker(String id) async {
    final db = await database;
    await db.delete('stickers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePackStickerCount(String packId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM stickers WHERE pack_id = ?', [packId]);
    final count = (result.first['cnt'] as int?) ?? 0;
    await db.update('sticker_packs', {'sticker_count': count},
        where: 'id = ?', whereArgs: [packId]);
  }
}
