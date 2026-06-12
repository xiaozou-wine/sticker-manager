import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class HotkeyConfig {
  final String keyLabel;      // e.g. "keyS"
  final int keyCode;          // physical key code
  final List<String> modifiers; // e.g. ["ctrl", "shift", "alt"]

  const HotkeyConfig({
    required this.keyLabel,
    required this.keyCode,
    required this.modifiers,
  });

  Map<String, dynamic> toMap() => {
    'keyLabel': keyLabel,
    'keyCode': keyCode,
    'modifiers': modifiers,
  };

  factory HotkeyConfig.fromMap(Map<String, dynamic> map) => HotkeyConfig(
    keyLabel: map['keyLabel'] ?? 'keyS',
    keyCode: map['keyCode'] ?? 0,
    modifiers: List<String>.from(map['modifiers'] ?? ['ctrl', 'shift']),
  );

  String get displayText {
    final parts = <String>[];
    if (modifiers.contains('ctrl')) parts.add('Ctrl');
    if (modifiers.contains('shift')) parts.add('Shift');
    if (modifiers.contains('alt')) parts.add('Alt');
    parts.add(_prettyKey(keyLabel));
    return parts.join(' + ');
  }

  static String _prettyKey(String label) {
    // "keyS" -> "S", "digit1" -> "1", "f1" -> "F1"
    if (label.startsWith('key') && label.length == 4) {
      return label.substring(3).toUpperCase();
    }
    if (label.startsWith('digit') && label.length == 6) {
      return label.substring(5);
    }
    return label.toUpperCase();
  }

  static const defaultConfig = HotkeyConfig(
    keyLabel: 'keyS',
    keyCode: 0,
    modifiers: ['ctrl', 'shift'],
  );
}

class SettingsService {
  static const _fileName = 'settings.json';

  static Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'sticker_pc', _fileName));
  }

  static Future<HotkeyConfig> loadHotkeyConfig() async {
    try {
      final f = await _file;
      if (!await f.exists()) return HotkeyConfig.defaultConfig;
      final data = json.decode(await f.readAsString());
      return HotkeyConfig.fromMap(data['hotkey'] ?? {});
    } catch (_) {
      return HotkeyConfig.defaultConfig;
    }
  }

  static Future<void> saveHotkeyConfig(HotkeyConfig config) async {
    final f = await _file;
    Map<String, dynamic> data = {};
    if (await f.exists()) {
      data = json.decode(await f.readAsString());
    }
    data['hotkey'] = config.toMap();
    await f.create(recursive: true);
    await f.writeAsString(json.encode(data));
  }

  static Future<String> loadApiBaseUrl() async {
    try {
      final f = await _file;
      if (!await f.exists()) return '';
      final data = json.decode(await f.readAsString());
      return data['apiBaseUrl'] ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveApiBaseUrl(String url) async {
    final f = await _file;
    Map<String, dynamic> data = {};
    if (await f.exists()) {
      data = json.decode(await f.readAsString());
    }
    data['apiBaseUrl'] = url;
    await f.create(recursive: true);
    await f.writeAsString(json.encode(data));
  }

  static Future<String> loadSortMode() async {
    try {
      final f = await _file;
      if (!await f.exists()) return 'updated';
      final data = json.decode(await f.readAsString());
      return data['sortMode'] ?? 'updated';
    } catch (_) {
      return 'updated';
    }
  }

  static Future<void> saveSortMode(String mode) async {
    final f = await _file;
    Map<String, dynamic> data = {};
    if (await f.exists()) {
      data = json.decode(await f.readAsString());
    }
    data['sortMode'] = mode;
    await f.create(recursive: true);
    await f.writeAsString(json.encode(data));
  }
}
