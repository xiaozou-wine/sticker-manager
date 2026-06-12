import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class GallerySaveService {
  /// 获取已保存 hash 记录文件路径
  static Future<File> _hashFile(String packName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gallery_hashes_$packName.txt');
  }

  /// 读取已保存的 hash 集合
  static Future<Set<String>> _loadSavedHashes(String packName) async {
    try {
      final file = await _hashFile(packName);
      if (!await file.exists()) return {};
      final lines = await file.readAsLines();
      return lines.where((l) => l.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  /// 保存 hash 集合到本地
  static Future<void> _saveHashes(String packName, Set<String> hashes) async {
    final file = await _hashFile(packName);
    await file.writeAsString(hashes.join('\n'));
  }

  /// 删除本地 hash 记录
  static Future<void> _clearHashes(String packName) async {
    try {
      final file = await _hashFile(packName);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

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

    // 覆盖模式：清空本地 hash 记录
    if (mode == 'replace') {
      await _clearHashes(name);
    }

    final savedHashes = mode == 'replace' ? <String>{} : await _loadSavedHashes(name);

    int saved = 0;
    int skipped = 0;
    int failed = 0;
    final total = validStickers.length;

    for (int i = 0; i < total; i++) {
      try {
        final file = File(validStickers[i].localPath!);
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();

        if (savedHashes.contains(hash)) {
          skipped++;
        } else {
          if (mode == 'rename' && savedHashes.contains(hash)) {
            // 重命名模式下如果 hash 重复，加后缀
            final ext = file.path.contains('.') ? '.${file.path.split('.').last}' : '';
            final baseName = file.uri.pathSegments.last;
            final base = ext.isNotEmpty ? baseName.substring(0, baseName.length - ext.length) : baseName;
            final tempDir = await Directory.systemTemp.createTemp('sticker_');
            final newName = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
            final renamedFile = await file.copy('${tempDir.path}/$newName');
            await Gal.putImage(renamedFile.path, album: galAlbum);
            try { await renamedFile.delete(); await tempDir.delete(); } catch (_) {}
          } else {
            await Gal.putImage(file.path, album: galAlbum);
          }
          savedHashes.add(hash);
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
