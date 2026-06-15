import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/sticker.dart';
import '../services/storage_service.dart';
import '../services/gallery_save_service.dart';

class StickerProvider extends ChangeNotifier {
  final StorageService _storage;

  List<Sticker> _stickers = [];
  bool _isLoading = false;
  String? _error;
  String? _currentPackId;

  StickerProvider(this._storage);

  List<Sticker> get stickers => _stickers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadStickers(String packId) async {
    _currentPackId = packId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stickers = await _storage.getStickersByPackId(packId);
    } catch (e) {
      _stickers = [];
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addStickers(String packId, List<Sticker> newStickers) async {
    await _storage.insertStickers(newStickers);
    await _storage.updatePackStickerCount(packId);
    if (_currentPackId == packId) {
      _stickers.addAll(newStickers);
      notifyListeners();
    }
  }

  Future<void> deleteSticker(String packId, String stickerId) async {
    // 删除前计算 hash，从 hash 文件中清除
    final sticker = _stickers.firstWhere((s) => s.id == stickerId, orElse: () => Sticker(id: '', packId: '', type: ''));
    if (sticker.localPath != null) {
      try {
        final bytes = await File(sticker.localPath!).readAsBytes();
        final hash = sha256.convert(bytes).toString();
        await GallerySaveService.removeHashes(packId, [hash]);
      } catch (_) {}
    }
    await _storage.deleteSticker(stickerId);
    await _storage.updatePackStickerCount(packId);
    _stickers.removeWhere((s) => s.id == stickerId);
    notifyListeners();
  }

  Future<void> deleteStickers(String packId, List<String> ids) async {
    // 批量删除前计算 hash
    final hashes = <String>[];
    for (final id in ids) {
      final s = _stickers.firstWhere((st) => st.id == id, orElse: () => Sticker(id: '', packId: '', type: ''));
      if (s.localPath != null) {
        try {
          final bytes = await File(s.localPath!).readAsBytes();
          hashes.add(sha256.convert(bytes).toString());
        } catch (_) {}
      }
    }
    if (hashes.isNotEmpty) {
      await GallerySaveService.removeHashes(packId, hashes);
    }
    await _storage.deleteStickers(ids);
    await _storage.updatePackStickerCount(packId);
    _stickers.removeWhere((s) => ids.contains(s.id));
    notifyListeners();
  }
}
