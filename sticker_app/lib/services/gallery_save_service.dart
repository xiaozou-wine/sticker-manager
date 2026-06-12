import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import 'storage_service.dart';

class GallerySaveService {
  /// 读取相册中所有图片的 SHA256 hash
  static Future<Set<String>> _getAlbumHashes(String albumName) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return {};

      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final album = albums.where((a) => a.name == albumName).toList();
      if (album.isEmpty) return {};

      final count = await album[0].assetCountAsync;
      if (count == 0) return {};

      final assets = await album[0].getAssetListRange(start: 0, end: count);
      final hashes = <String>{};
      for (final asset in assets) {
        final file = await asset.file;
        if (file != null && file.existsSync()) {
          final bytes = await file.readAsBytes();
          hashes.add(sha256.convert(bytes).toString());
        }
      }
      return hashes;
    } catch (_) {
      return {};
    }
  }

  /// 删除相册中所有图片
  static Future<void> _deleteAlbum(String albumName) async {
    try {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final album = albums.where((a) => a.name == albumName).toList();
      if (album.isEmpty) return;

      final count = await album[0].assetCountAsync;
      if (count == 0) return;

      final assets = await album[0].getAssetListRange(start: 0, end: count);
      final ids = assets.map((a) => a.id).toList();
      if (ids.isNotEmpty) {
        await PhotoManager.editor.deleteWithIds(ids);
      }
    } catch (_) {}
  }

  /// mode: "skip"=SHA256去重跳过, "rename"=重命名保存, "replace"=覆盖保存
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

    // 覆盖模式：先删除整个相册
    if (mode == 'replace') {
      await _deleteAlbum(name);
    }

    // 读取相册已有 hash（覆盖模式删完后为空）
    final existingHashes = mode == 'replace' ? <String>{} : await _getAlbumHashes(name);

    int saved = 0;
    int skipped = 0;
    int failed = 0;
    final total = validStickers.length;

    for (int i = 0; i < total; i++) {
      try {
        final file = File(validStickers[i].localPath!);
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();

        if (existingHashes.contains(hash)) {
          if (mode == 'rename') {
            // 重命名：加时间戳后缀
            final ext = file.path.contains('.') ? '.${file.path.split('.').last}' : '';
            final base = ext.isNotEmpty
                ? file.uri.pathSegments.last.substring(0, file.uri.pathSegments.last.length - ext.length)
                : file.uri.pathSegments.last;
            final tempDir = await Directory.systemTemp.createTemp('sticker_');
            final newName = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
            final renamedFile = await file.copy('${tempDir.path}/$newName');
            await Gal.putImage(renamedFile.path, album: galAlbum);
            existingHashes.add(hash);
            try { await renamedFile.delete(); await tempDir.delete(); } catch (_) {}
            saved++;
          } else {
            // skip 模式：跳过
            skipped++;
          }
        } else {
          await Gal.putImage(file.path, album: galAlbum);
          existingHashes.add(hash);
          saved++;
        }
      } catch (e) {
        failed++;
      }
      onProgress?.call(i + 1, total);
    }

    final debug = 'mode:$mode saved:$saved skip:$skipped fail:$failed';
    return {'saved': saved, 'skipped': skipped, 'failed': failed, 'debug': debug};
  }
}
