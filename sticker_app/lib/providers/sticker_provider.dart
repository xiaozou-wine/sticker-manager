import 'package:flutter/foundation.dart';
import '../models/sticker.dart';
import '../services/storage_service.dart';

class StickerProvider extends ChangeNotifier {
  final StorageService _storage;

  List<Sticker> _stickers = [];
  bool _isLoading = false;
  String? _currentPackId;

  StickerProvider(this._storage);

  List<Sticker> get stickers => _stickers;
  bool get isLoading => _isLoading;

  Future<void> loadStickers(String packId) async {
    _currentPackId = packId;
    _isLoading = true;
    notifyListeners();

    try {
      _stickers = await _storage.getStickersByPackId(packId);
    } catch (e) {
      _stickers = [];
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
    await _storage.deleteSticker(stickerId);
    await _storage.updatePackStickerCount(packId);
    _stickers.removeWhere((s) => s.id == stickerId);
    notifyListeners();
  }
}
