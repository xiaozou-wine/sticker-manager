import 'dart:io';
import 'package:gal/gal.dart';
import 'storage_service.dart';

class GallerySaveService {
  static Future<Map<String, int>> savePackToGallery(
    StorageService storage,
    String packId, {
    String? albumName,
    void Function(int current, int total)? onProgress,
  }) async {
    final pack = await storage.getPackById(packId);
    final name = albumName ?? pack?.name ?? "StickerManager";
    final stickers = await storage.getStickersByPackId(packId);
    final validStickers = stickers.where((s) => s.localPath != null && File(s.localPath!).existsSync()).toList();

    int saved = 0;
    int failed = 0;
    for (int i = 0; i < validStickers.length; i++) {
      try {
        final file = File(validStickers[i].localPath!);
        final ext = file.path.split('.').last.toLowerCase();
        if (ext == 'gif') {
          await Gal.putImage(file.path, album: name);
        } else {
          await Gal.putImage(file.path, album: name);
        }
        saved++;
      } catch (e) {
        failed++;
      }
      onProgress?.call(i + 1, validStickers.length);
    }
    return {'saved': saved, 'failed': failed};
  }
}
