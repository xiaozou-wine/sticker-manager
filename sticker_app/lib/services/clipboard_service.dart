import 'dart:io';

/// Clipboard service stub for mobile platforms.
/// Desktop (Windows) FFI implementation is in main_desktop.dart.
class ClipboardService {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> copyImage(String filePath) async {
    // No-op on mobile — stickers go through gallery save instead.
  }
}
