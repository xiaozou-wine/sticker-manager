import 'dart:io';
import 'package:flutter/services.dart';
import 'storage_service.dart';

class GallerySaveService {
  static const _channel = MethodChannel('com.stickerapp/sticker_accessibility');

  /// 检查相册中是否存在同名文件，返回每个文件是否存在
  static Future<List<bool>> checkDuplicates(List<String> filePaths, String albumName) async {
    final result = await _channel.invokeMethod('checkDuplicates', {
      'filePaths': filePaths,
      'folderName': albumName,
    });
    return (result as List).map((e) => e == true).toList();
  }

  /// 保存表情包到相册
  /// dedupMode: "skip" 跳过已存在, "rename" 重命名保存
  static Future<Map<String, int>> savePackToGallery(
    StorageService storage,
    String packId, {
    String? albumName,
    String dedupMode = 'skip',
    void Function(int current, int total)? onProgress,
  }) async {
    final pack = await storage.getPackById(packId);
    final name = albumName ?? pack?.name ?? "StickerManager";
    final stickers = await storage.getStickersByPackId(packId);
    final validStickers = stickers.where((s) => s.localPath != null && File(s.localPath!).existsSync()).toList();

    int saved = 0;
    int skipped = 0;
    int failed = 0;
    for (int i = 0; i < validStickers.length; i++) {
      try {
        final result = await _channel.invokeMethod('saveToGallery', {
          'filePath': validStickers[i].localPath!,
          'folderName': name,
          'index': i,
          'dedupMode': dedupMode,
        });
        if (result is Map) {
          saved += (result['saved'] as int?) ?? 0;
          skipped += (result['skipped'] as int?) ?? 0;
          failed += (result['failed'] as int?) ?? 0;
        } else {
          saved++;
        }
      } catch (e) {
        failed++;
      }
      onProgress?.call(i + 1, validStickers.length);
    }
    return {'saved': saved, 'skipped': skipped, 'failed': failed};
  }
}
