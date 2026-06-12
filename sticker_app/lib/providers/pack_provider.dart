import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/sticker_pack.dart';
import '../services/storage_service.dart';
import '../services/app_settings.dart';

class PackProvider extends ChangeNotifier {
  final StorageService _storage;

  List<StickerPack> _packs = [];
  bool _isLoading = false;
  String? _error;
  String _sortMode = 'updated';

  PackProvider(this._storage);

  List<StickerPack> get packs => _packs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get sortMode => _sortMode;

  Future<void> loadSortMode() async {
    _sortMode = await AppSettings.loadSortMode();
    notifyListeners();
  }

  Future<void> setSortMode(String mode) async {
    _sortMode = mode;
    notifyListeners();
    await AppSettings.saveSortMode(mode);
    await loadPacks();
  }

  Future<void> loadPacks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _packs = await _storage.getAllPacks(sortMode: _sortMode);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<StickerPack> createPack(String name, {String description = ''}) async {
    final pack = StickerPack(
      id: const Uuid().v4(),
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

  Future<void> reorderPacks(int oldIndex, int newIndex) async {
    final pack = _packs.removeAt(oldIndex);
    _packs.insert(newIndex, pack);
    notifyListeners();
    final orders = <String, int>{};
    for (int i = 0; i < _packs.length; i++) {
      orders[_packs[i].id] = i;
    }
    await _storage.updateSortOrders(orders);
    _sortMode = 'manual';
    notifyListeners();
    await AppSettings.saveSortMode('manual');
  }
}
