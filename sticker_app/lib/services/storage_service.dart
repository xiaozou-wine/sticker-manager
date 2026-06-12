import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class StorageService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stickers.db');
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        // #8 FK pragma must be in onConfigure to work for all connections
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
            sort_order INTEGER DEFAULT 0,
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
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE sticker_packs ADD COLUMN sort_order INTEGER DEFAULT 0');
          final rows = await db.query('sticker_packs', orderBy: 'updated_at DESC');
          for (int i = 0; i < rows.length; i++) {
            final id = rows[i]['id'] as String;
            await db.update('sticker_packs', {'sort_order': i},
                where: 'id = ?', whereArgs: [id]);
            final cover = rows[i]['cover_local'] as String?;
            if (cover == null || cover.isEmpty) {
              final stickers = await db.query('stickers',
                  where: 'pack_id = ?', whereArgs: [id],
                  orderBy: 'created_at', limit: 1);
              if (stickers.isNotEmpty) {
                final localPath = stickers.first['local_path'] as String?;
                if (localPath != null && localPath.isNotEmpty) {
                  await db.update('sticker_packs', {'cover_local': localPath},
                      where: 'id = ?', whereArgs: [id]);
                }
              }
            }
          }
        }
      },
    );
  }

  // --- StickerPack CRUD ---

  Future<void> insertPack(StickerPack pack) async {
    final db = await database;
    await db.insert('sticker_packs', pack.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StickerPack>> getAllPacks({String sortMode = 'updated'}) async {
    final db = await database;
    String orderBy;
    switch (sortMode) {
      case 'created':
        orderBy = 'created_at DESC';
        break;
      case 'name':
        orderBy = 'name COLLATE NOCASE ASC';
        break;
      case 'count':
        orderBy = 'sticker_count DESC';
        break;
      case 'manual':
        orderBy = 'sort_order ASC';
        break;
      default:
        orderBy = 'updated_at DESC';
    }
    final maps = await db.query('sticker_packs', orderBy: orderBy);
    final packs = maps.map((m) => StickerPack.fromMap(m)).toList();
    for (final pack in packs) {
      if (pack.coverLocal == null || pack.coverLocal!.isEmpty || !File(pack.coverLocal!).existsSync()) {
        final stickers = await db.query('stickers',
            where: 'pack_id = ?', whereArgs: [pack.id],
            orderBy: 'created_at', limit: 1);
        if (stickers.isNotEmpty) {
          final localPath = stickers.first['local_path'] as String?;
          if (localPath != null && localPath.isNotEmpty) {
            pack.coverLocal = localPath;
            await db.update('sticker_packs', {'cover_local': localPath},
                where: 'id = ?', whereArgs: [pack.id]);
          }
        }
      }
    }
    return packs;
  }

  Future<void> updateSortOrders(Map<String, int> orders) async {
    final db = await database;
    final batch = db.batch();
    orders.forEach((id, order) {
      batch.update('sticker_packs', {'sort_order': order},
          where: 'id = ?', whereArgs: [id]);
    });
    await batch.commit(noResult: true);
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
    // 先查出所有表情文件路径
    final stickers = await getStickersByPackId(id);
    await db.delete('stickers', where: 'pack_id = ?', whereArgs: [id]);
    await db.delete('sticker_packs', where: 'id = ?', whereArgs: [id]);
    // 删除文件
    for (final s in stickers) {
      if (s.localPath != null) {
        try { await File(s.localPath!).delete(); } catch (_) {}
      }
    }
    // 删除 pack 目录
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final packDir = Directory(join(appDir.path, 'stickers', id));
      if (await packDir.exists()) await packDir.delete(recursive: true);
    } catch (_) {}
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
    // 先查出文件路径
    final maps = await db.query('stickers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final localPath = maps[0]['local_path'] as String?;
      if (localPath != null) {
        try { await File(localPath).delete(); } catch (_) {}
      }
    }
    await db.delete('stickers', where: 'id = ?', whereArgs: [id]);
  }

  /// 批量删除表情（含文件）
  Future<void> deleteStickers(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    // 查出所有文件路径
    final maps = await db.query('stickers', where: 'id IN ($placeholders)', whereArgs: ids);
    for (final m in maps) {
      final localPath = m['local_path'] as String?;
      if (localPath != null) {
        try { await File(localPath).delete(); } catch (_) {}
      }
    }
    await db.delete('stickers', where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Future<void> updatePackStickerCount(String packId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM stickers WHERE pack_id = ?', [packId]));
    await db.update('sticker_packs', {'sticker_count': count ?? 0},
        where: 'id = ?', whereArgs: [packId]);
  }
}
