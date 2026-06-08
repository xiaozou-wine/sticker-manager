package com.stickerapp.sticker_app

import android.media.MediaScannerConnection
import android.os.Environment
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
                else -> result.notImplemented()
            }
        }
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
        return targetFile.absolutePath
    }
}
