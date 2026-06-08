import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';
import 'storage_service.dart';
import '../models/sticker.dart';
import 'accessibility_service.dart';

class DownloadService {
  final ApiService apiService;
  final StorageService storageService;

  DownloadService({required this.apiService, required this.storageService});

  /// Download all stickers from a remote pack and save locally
  Future<DownloadResult> downloadPack({
    required String shareCode,
    required String packName,
    Function(int completed, int total)? onProgress,
  }) async {
    // Get pack info
    final pack = await apiService.getPackByCode(shareCode);
    final remoteStickers = await apiService.getPackStickers(shareCode);

    if (remoteStickers.isEmpty) {
      return DownloadResult(packId: pack.id, stickerCount: 0);
    }

    // Save pack to local DB
    pack.source = 'link';
    await storageService.insertPack(pack);

    // Get local cache directory
    final appDir = await getApplicationDocumentsDirectory();
    final packDir = Directory(p.join(appDir.path, 'stickers', pack.id));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    // Download each sticker
    final stickers = <Sticker>[];
    final failedIds = <String>[];
    for (int i = 0; i < remoteStickers.length; i++) {
      final remote = remoteStickers[i];
      try {
        final ext = remote.extension.isNotEmpty ? remote.extension : '.png';
        final localPath = p.join(packDir.path, '${remote.id}$ext');
        await apiService.downloadSticker(remote.fileUrl, localPath);

        // Save to phone gallery (Android only)
        if (Platform.isAndroid) {
          await AccessibilityService.saveToGallery(localPath, folderName: 'StickerApp/$packName');
        }

        final sticker = Sticker(
          id: remote.id,
          packId: pack.id,
          type: remote.type,
          width: remote.width,
          height: remote.height,
          sizeBytes: remote.sizeBytes,
          extension: ext,
          localPath: localPath,
        );
        stickers.add(sticker);
        onProgress?.call(i + 1, remoteStickers.length);
      } catch (e) {
        failedIds.add(remote.id);
        continue;
      }
    }

    // Batch insert stickers
    await storageService.insertStickers(stickers);
    await storageService.updatePackStickerCount(pack.id);

    // Update cover
    if (stickers.isNotEmpty) {
      pack.coverLocal = stickers.first.localPath;
      pack.coverUrl = remoteStickers.first.fileUrl;
      await storageService.updatePack(pack);
    }

    return DownloadResult(
      packId: pack.id,
      stickerCount: stickers.length,
      failedCount: failedIds.length,
    );
  }

}

class DownloadResult {
  final String packId;
  final int stickerCount;
  final int failedCount;

  DownloadResult({required this.packId, required this.stickerCount, this.failedCount = 0});
}
