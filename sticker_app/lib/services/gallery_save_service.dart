import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'storage_service.dart';

class GallerySaveService {
  /// 获取已保存 hash 记录文件路径
  static Future<File> _hashFile(String packName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gallery_hashes_$packName.txt');
  }

  /// 格式: hash行 "hash:true"=已保存到相册, "hash:false"=已导入但未保存到相册
  static Future<Map<String, bool>> _loadSavedHashes(String packName) async {
    try {
      final file = await _hashFile(packName);
      if (!await file.exists()) return {};
      final lines = await file.readAsLines();
      final map = <String, bool>{};
      for (final line in lines) {
        if (line.isEmpty) continue;
        final parts = line.split(':');
        if (parts.length == 2) {
          map[parts[0]] = parts[1] == 'true';
        } else {
          // 兼容旧格式（纯 hash，无 :true/false）
          map[line] = true;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveHashes(String packName, Map<String, bool> hashes) async {
    final file = await _hashFile(packName);
    final lines = hashes.entries.map((e) => '${e.key}:${e.value}').toList();
    await file.writeAsString(lines.join('\n'));
  }

  /// 记录导入的 hash（import 时调用）
  /// [savedToGallery] 表示导入时是否已经调了 Gal.putImage
  static Future<void> recordImportHashes(String packName, List<String> hashes, {bool savedToGallery = false}) async {
    final existing = await _loadSavedHashes(packName);
    for (final h in hashes) {
      existing[h] = savedToGallery;
    }
    await _saveHashes(packName, existing);
  }

  /// 删除本地 hash 记录
  static Future<void> _clearHashes(String packName) async {
    try {
      final file = await _hashFile(packName);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 删除指定 hash 记录（删除表情时调用）
  static Future<void> removeHashes(String packName, List<String> hashes) async {
    try {
      final existing = await _loadSavedHashes(packName);
      for (final h in hashes) {
        existing.remove(h);
      }
      await _saveHashes(packName, existing);
    } catch (_) {}
  }

  /// 用 photo_manager 找到 album 并返回 AssetEntity 列表
  static Future<List<AssetEntity>> _getAlbumAssets(String albumName) async {
    try {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final album = albums.where((a) => a.name == albumName).toList();
      if (album.isEmpty) return [];
      final count = await album[0].assetCountAsync;
      return await album[0].getAssetListRange(start: 0, end: count);
    } catch (_) {
      return [];
    }
  }

  /// 覆盖保存：先删相册所有文件，再全量保存
  /// mode: "skip"=去重跳过, "rename"=重命名保存, "replace"=覆盖保存
  static Future<Map<String, dynamic>> savePackToGallery(
    StorageService storage,
    String packId, {
    String? albumName,
    String mode = 'skip',
    void Function(int current, int total)? onProgress,
  }) async {
    final pack = await storage.getPackById(packId);
    final name = albumName ?? pack?.name ?? "StickerManager";
    final galAlbum = 'StickerApp/$name';
    final stickers = await storage.getStickersByPackId(packId);
    final validStickers = stickers
        .where((s) => s.localPath != null && File(s.localPath!).existsSync())
        .toList();

    // 覆盖模式：清空本地 hash + 删除相册文件
    if (mode == 'replace') {
      await _clearHashes(name);
      try {
        final assets = await _getAlbumAssets(name);
        if (assets.isNotEmpty) {
          await PhotoManager.editor.deleteWithIds(assets.map((a) => a.id).toList());
        }
      } catch (_) {}
    }

    // 加载 hash 记录（覆盖模式已清空，得到空 map）
    final savedHashes = mode == 'replace' ? <String, bool>{} : await _loadSavedHashes(name);

    int saved = 0;
    int skipped = 0;
    int failed = 0;
    final total = validStickers.length;

    for (int i = 0; i < total; i++) {
      try {
        final file = File(validStickers[i].localPath!);
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();

        final alreadySaved = savedHashes[hash] == true;

        if (alreadySaved) {
          if (mode == 'rename') {
            final tempDir = await Directory.systemTemp.createTemp('sticker_');
            final ext = file.path.contains('.') ? '.${file.path.split('.').last}' : '';
            final padded = (i + 1).toString().padLeft(3, '0');
            final renamedFile = await file.copy('${tempDir.path}/${padded}_$ext');
            await Gal.putImage(renamedFile.path, album: galAlbum);
            try { await renamedFile.delete(); await tempDir.delete(); } catch (_) {}
            savedHashes[hash] = true;
            saved++;
          } else {
            skipped++;
          }
        } else {
          // 用零补位序号重命名，保证相册按名称排序正确
          final tempDir = await Directory.systemTemp.createTemp('sticker_');
          final ext = file.path.contains('.') ? '.${file.path.split('.').last}' : '';
          final padded = (i + 1).toString().padLeft(3, '0');
          final renamedFile = await file.copy('${tempDir.path}/${padded}_$ext');
          await Gal.putImage(renamedFile.path, album: galAlbum);
          try { await renamedFile.delete(); await tempDir.delete(); } catch (_) {}
          savedHashes[hash] = true;
          saved++;
        }
      } catch (e) {
        failed++;
      }
      onProgress?.call(i + 1, total);
    }

    // 保存更新后的 hash 记录
    await _saveHashes(name, savedHashes);

    final debug = 'mode:$mode new:$saved skip:$skipped total_hash:${savedHashes.length}';
    return {'saved': saved, 'skipped': skipped, 'failed': failed, 'debug': debug};
  }
}
