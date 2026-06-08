import 'package:flutter/foundation.dart';
import '../models/sticker_pack.dart';
import '../services/storage_service.dart';

class PackProvider extends ChangeNotifier {
  final StorageService _storage;

  List<StickerPack> _packs = [];
  bool _isLoading = false;
  String? _error;

  PackProvider(this._storage);

  List<StickerPack> get packs => _packs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPacks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _packs = await _storage.getAllPacks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<StickerPack> createPack(String name, {String description = ''}) async {
    final pack = StickerPack(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      description: description,
    );
    await _storage.insertPack(pack);
    _packs.insert(0, pack);
    notifyListeners();
    return pack;
  }

  Future<void> deletePack(String id) async {
    await _storage.deletePack(id);
    _packs.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> refreshPack(String id) async {
    final pack = await _storage.getPackById(id);
    if (pack != null) {
      final idx = _packs.indexWhere((p) => p.id == id);
      if (idx >= 0) {
        _packs[idx] = pack;
        notifyListeners();
      }
    }
  }
}
