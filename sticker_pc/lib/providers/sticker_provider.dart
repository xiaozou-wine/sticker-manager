import 'package:flutter/material.dart';
import '../models/sticker.dart';
import '../services/storage_service.dart';

class StickerProvider extends ChangeNotifier {
  final StorageService storage;
  List<Sticker> stickers = [];
  bool isLoading = false;

  StickerProvider(this.storage);

  Future<void> loadStickers(String packId) async {
    isLoading = true;
    notifyListeners();
    stickers = await storage.getStickersByPackId(packId);
    isLoading = false;
    notifyListeners();
  }

  Future<void> addStickers(String packId, List<Sticker> newStickers) async {
    await storage.insertStickers(newStickers);
    await storage.updatePackStickerCount(packId);
    await loadStickers(packId);
  }

  Future<void> deleteSticker(String packId, String stickerId) async {
    await storage.deleteSticker(stickerId);
    await storage.updatePackStickerCount(packId);
    stickers.removeWhere((s) => s.id == stickerId);
    notifyListeners();
  }

  Future<void> deleteStickers(String packId, List<String> ids) async {
    if (ids.isEmpty) return;
    await storage.deleteStickers(ids);
    await storage.updatePackStickerCount(packId);
    stickers.removeWhere((s) => ids.contains(s.id));
    notifyListeners();
  }
}
