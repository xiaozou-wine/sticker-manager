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
}
