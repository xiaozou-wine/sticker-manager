import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class AppSettings {
  static const _fileName = 'app_settings.json';

  static Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
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
