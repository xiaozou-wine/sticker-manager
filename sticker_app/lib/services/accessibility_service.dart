import 'package:flutter/services.dart';

/// Dart interface for the native Android Accessibility Service.
/// Communicates with StickerAccessibilityService via MethodChannel.
class AccessibilityService {
  static const _channel = MethodChannel('com.stickerapp/sticker_accessibility');

  /// Check if the accessibility service is currently running.
  static Future<bool> isServiceEnabled() async {
    final result = await _channel.invokeMethod<bool>('isServiceEnabled');
    return result ?? false;
  }

  /// Check if overlay (SYSTEM_ALERT_WINDOW) permission is granted.
  static Future<bool> isOverlayPermissionGranted() async {
    final result = await _channel.invokeMethod<bool>('isOverlayPermissionGranted');
    return result ?? false;
  }

  /// Open Android accessibility settings page.
  static Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  /// Open overlay permission settings for this app.
  static Future<void> openOverlayPermissionSettings() async {
    await _channel.invokeMethod('openOverlayPermissionSettings');
  }

  /// Show the sticker overlay (floating window).
  /// Only works if accessibility service is running.
  static Future<bool> showOverlay() async {
    final result = await _channel.invokeMethod<bool>('showOverlay');
    return result ?? false;
  }

  /// Hide the sticker overlay.
  static Future<bool> hideOverlay() async {
    final result = await _channel.invokeMethod<bool>('hideOverlay');
    return result ?? false;
  }

  /// Dump the current UI tree from the accessibility service.
  /// Returns a list of node info maps with: depth, class, text, desc, vid, id,
  /// bounds, clickable, editable, enabled, visible, focusable, childCount.
  static Future<List<Map<String, dynamic>>> dumpNodeTree() async {
    final result = await _channel.invokeMethod<List>('dumpNodeTree');
    if (result == null) return [];
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Request to be exempt from battery optimization.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  /// Open auto-start settings for Chinese ROMs.
  static Future<void> openAutoStartSettings() async {
    await _channel.invokeMethod('openAutoStartSettings');
  }

  /// Save a file to the phone's public gallery (Pictures/{folderName}).
  static Future<String?> saveToGallery(String filePath, {String folderName = 'StickerApp'}) async {
    final result = await _channel.invokeMethod<String>('saveToGallery', {
      'filePath': filePath,
      'folderName': folderName,
    });
    return result;
  }
}
