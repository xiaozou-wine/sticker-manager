import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';
import 'storage_service.dart';
import '../models/sticker.dart';

class DownloadService {
  final ApiService apiService;
  final StorageService storageService;
  /// 并行下载数
  static const int _maxConcurrent = 5;

  DownloadService({required this.apiService, required this.storageService});

  Future<DownloadResult> downloadPack({
    required String shareCode,
    required String packName,
    Function(int completed, int total)? onProgress,
  }) async {
    final pack = await apiService.getPackByCode(shareCode);
    final remoteStickers = await apiService.getPackStickers(shareCode);

    if (remoteStickers.isEmpty) {
      return DownloadResult(packId: pack.id, stickerCount: 0);
    }

    pack.source = 'link';
    await storageService.insertPack(pack);

    final appDir = await getApplicationDocumentsDirectory();
    final packDir = Directory(p.join(appDir.path, 'stickers', pack.id));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final stickers = <Sticker>[];
    final failedIds = <String>[];
    int completed = 0;

    // 并行下载：每批 _maxConcurrent 个同时下载
    for (int start = 0; start < remoteStickers.length; start += _maxConcurrent) {
      final end = (start + _maxConcurrent).clamp(0, remoteStickers.length);
      final futures = <Future<void>>[];

      for (int i = start; i < end; i++) {
        final remote = remoteStickers[i];
        futures.add(() async {
          try {
            final ext = remote.extension.isNotEmpty ? remote.extension : '.png';
            final localPath = p.join(packDir.path, '${remote.id}$ext');
            await apiService.downloadSticker(remote.fileUrl, localPath);

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
          } catch (e) {
            failedIds.add(remote.id);
          } finally {
            completed++;
            onProgress?.call(completed, remoteStickers.length);
          }
        }());
      }

      await Future.wait(futures);
    }

    await storageService.insertStickers(stickers);
    await storageService.updatePackStickerCount(pack.id);

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
