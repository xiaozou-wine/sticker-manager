import 'dart:io';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'storage_service.dart';

enum SaveMode { skip, rename, replace }

class GallerySaveService {
  static const _channel = MethodChannel('com.stickerapp/sticker_accessibility');

  /// 检查重复数量，通过 Kotlin MediaStore 查询
  static Future<int> checkDuplicateCount(String albumName, List<String> filePaths) async {
    try {
      final results = await _channel.invokeMethod('checkDuplicates', {
        'filePaths': filePaths,
        'folderName': 'StickerApp/$albumName',
      });
      if (results is List) {
        return results.where((e) => e == true).length;
      }
    } catch (_) {}
    return 0;
  }

  static Future<Map<String, int>> savePackToGallery(
    StorageService storage,
    String packId, {
    String? albumName,
    SaveMode mode = SaveMode.skip,
    void Function(int current, int total)? onProgress,
  }) async {
    final pack = await storage.getPackById(packId);
    final name = albumName ?? pack?.name ?? "StickerManager";
    final folderName = 'StickerApp/$name';
    final stickers = await storage.getStickersByPackId(packId);
    final validStickers = stickers.where((s) => s.localPath != null && File(s.localPath!).existsSync()).toList();

    final dedupModeStr = mode == SaveMode.rename ? 'rename' : (mode == SaveMode.replace ? 'replace' : 'skip');

    int saved = 0;
    int skipped = 0;
    int failed = 0;
    final total = validStickers.length;

    for (int i = 0; i < total; i++) {
      try {
        final result = await _channel.invokeMethod('saveToGallery', {
          'filePath': validStickers[i].localPath!,
          'folderName': folderName,
          'index': i,
          'total': total,
          'dedupMode': dedupModeStr,
        });
        if (result is Map) {
          saved += (result['saved'] as int?) ?? 0;
          skipped += (result['skipped'] as int?) ?? 0;
          failed += (result['failed'] as int?) ?? 0;
        } else {
          saved++;
        }
      } catch (e) {
        // channel 失败，回退到 Gal
        try {
          await Gal.putImage(validStickers[i].localPath!, album: folderName);
          saved++;
        } catch (_) {
          failed++;
        }
      }
      onProgress?.call(i + 1, total);
    }
    return {'saved': saved, 'skipped': skipped, 'failed': failed};
  }
}
