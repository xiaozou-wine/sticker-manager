import 'package:flutter/material.dart';
import '../models/sticker_pack.dart';
import '../services/storage_service.dart';

class PackProvider extends ChangeNotifier {
  final StorageService storage;
  List<StickerPack> packs = [];
  bool isLoading = false;
  String? error;

  PackProvider(this.storage);

  Future<void> loadPacks() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      packs = await storage.getAllPacks();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<StickerPack> createPack(String name) async {
    final pack = StickerPack(id: _generateId(), name: name);
    await storage.insertPack(pack);
    await loadPacks();
    return pack;
  }

  Future<void> deletePack(String id) async {
    await storage.deletePack(id);
    await loadPacks();
  }

  Future<void> refreshPack(String id) async {
    final idx = packs.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      final updated = await storage.getPackById(id);
      if (updated != null) {
        packs[idx] = updated;
        notifyListeners();
      }
    }
  }

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }
}
