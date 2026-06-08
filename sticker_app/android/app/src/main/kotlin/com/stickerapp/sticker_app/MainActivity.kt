package com.stickerapp.sticker_app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.stickerapp/sticker_accessibility"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> {
                    result.success(StickerAccessibilityService.isRunning)
                }
                "isOverlayPermissionGranted" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "openOverlayPermissionSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        android.net.Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }
                "showOverlay" -> {
                    val success = StickerAccessibilityService.instance?.showOverlay() ?: false
                    result.success(success)
                }
                "hideOverlay" -> {
                    val success = StickerAccessibilityService.instance?.hideOverlay() ?: false
                    result.success(success)
                }
                "dumpNodeTree" -> {
                    val nodes = StickerAccessibilityService.instance?.dumpNodeTree()
                    if (nodes != null) {
                        result.success(nodes)
                    } else {
                        result.error("SERVICE_NOT_RUNNING", "Accessibility service not running", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
