import 'services/settings_service.dart';

class AppConfig {
  static const _compileTimeDefault = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static String _resolvedBaseUrl = _compileTimeDefault;
  static String get apiBaseUrl => _resolvedBaseUrl;

  static Future<void> init() async {
    final saved = await SettingsService.loadApiBaseUrl();
    if (saved.isNotEmpty) {
      _resolvedBaseUrl = saved;
    }
  }
}
