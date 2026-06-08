package com.stickerapp.sticker_app

import android.content.ComponentName
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import java.io.File
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
                    result.success(false)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "openOverlayPermissionSettings" -> {
                    result.success(true)
                }
                "showOverlay" -> {
                    result.success(false)
                }
                "hideOverlay" -> {
                    result.success(false)
                }
                "dumpNodeTree" -> {
                    val nodes = StickerAccessibilityService.instance?.dumpNodeTree()
                    if (nodes != null) {
                        result.success(nodes)
                    } else {
                        result.error("SERVICE_NOT_RUNNING", "Accessibility service not running", null)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                "saveToGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    val folderName = call.argument<String>("folderName") ?: "StickerApp"
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savedPath = saveToGallery(filePath, folderName)
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        } catch (e: Exception) {
            // Fallback: open battery optimization settings list
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                android.util.Log.e("MainActivity", "Cannot open battery optimization settings", e2)
            }
        }
    }

    private fun openAutoStartSettings() {
        // Try various Chinese ROM auto-start intents
        val autoStartIntents = listOf(
            // Xiaomi/MIUI
            Intent().apply {
                component = ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
            },
            // Huawei/EMUI
            Intent().apply {
                component = ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
            },
            Intent().apply {
                component = ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")
            },
            // OPPO/ColorOS
            Intent().apply {
                action = "oppo.intent.action.AUTO_START"
                addCategory(Intent.CATEGORY_DEFAULT)
            },
            Intent().apply {
                component = ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")
            },
            Intent().apply {
                component = ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")
            },
            // Vivo
            Intent().apply {
                action = "vivo.intent.action.AUTO_START"
            },
            Intent().apply {
                component = ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
            },
            // Samsung
            Intent().apply {
                component = ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity")
            },
            // OnePlus
            Intent().apply {
                component = ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")
            }
        )

        for (intent in autoStartIntents) {
            try {
                startActivity(intent)
                return
            } catch (_: Exception) {
                // This ROM doesn't have this activity, try next
            }
        }

        // All ROM-specific intents failed, fallback to battery optimization settings
        requestIgnoreBatteryOptimizations()
    }

    private fun saveToGallery(filePath: String, folderName: String): String {
        val sourceFile = File(filePath)
        if (!sourceFile.exists()) throw Exception("Source file not found: $filePath")

        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val targetDir = File(picturesDir, folderName)
        if (!targetDir.exists()) targetDir.mkdirs()

        val targetFile = File(targetDir, sourceFile.name)
        sourceFile.copyTo(targetFile, overwrite = true)

        MediaScannerConnection.scanFile(this, arrayOf(targetFile.absolutePath), null, null)

        android.util.Log.i("MainActivity", "Saved to gallery: ${targetFile.absolutePath}")
        return targetFile.absolutePath
    }
}
