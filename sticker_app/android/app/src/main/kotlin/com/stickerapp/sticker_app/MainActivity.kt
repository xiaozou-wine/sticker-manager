package com.stickerapp.sticker_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
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
                    val index = call.argument<Int>("index") ?: 0
                    val dedupMode = call.argument<String>("dedupMode") ?: "skip"
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val saved = saveToGallery(filePath, folderName, index, dedupMode)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                "checkDuplicates" -> {
                    val filePaths = call.argument<List<String>>("filePaths")
                    val folderName = call.argument<String>("folderName") ?: "StickerApp"
                    if (filePaths == null) {
                        result.error("INVALID_ARGS", "filePaths is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val duplicates = checkDuplicates(filePaths, folderName)
                        result.success(duplicates)
                    } catch (e: Exception) {
                        result.error("CHECK_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkDuplicates(filePaths: List<String>, folderName: String): List<Boolean> {
        val resolver = contentResolver
        val imageUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_PICTURES}/$folderName"

        return filePaths.map { filePath ->
            val fileName = File(filePath).name
            val projection = arrayOf(MediaStore.Images.Media._ID)
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${MediaStore.Images.Media.RELATIVE_PATH} = ?"
            val selectionArgs = arrayOf(fileName, relativePath)

            resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { cursor ->
                cursor.count > 0
            } ?: false
        }
    }

    private fun saveToGallery(filePath: String, folderName: String, index: Int, dedupMode: String): Map<String, Int> {
        val sourceFile = File(filePath)
        if (!sourceFile.exists()) throw Exception("Source file not found: $filePath")

        val mimeType = when (sourceFile.extension.lowercase()) {
            "gif" -> "image/gif"
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }

        val resolver = contentResolver
        val imageUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_PICTURES}/$folderName"

        // 检查是否已存在同名文件
        val existingName = getExistingFileName(sourceFile.name, relativePath, dedupMode, resolver, imageUri)
        if (existingName == null) {
            // skip 模式下文件已存在，跳过
            return mapOf("saved" to 0, "skipped" to 1, "failed" to 0)
        }

        val baseTime = System.currentTimeMillis() / 1000 - 10000 + index

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, existingName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.DATE_ADDED, baseTime)
            put(MediaStore.Images.Media.DATE_MODIFIED, baseTime)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(imageUri, values)
            ?: throw Exception("Failed to create MediaStore entry")

        resolver.openOutputStream(uri)?.use { out ->
            FileInputStream(sourceFile).use { input ->
                input.copyTo(out)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return mapOf("saved" to 1, "skipped" to 0, "failed" to 0)
    }

    /**
     * 返回要保存的文件名，null 表示跳过
     */
    private fun getExistingFileName(
        originalName: String,
        relativePath: String,
        dedupMode: String,
        resolver: android.content.ContentResolver,
        imageUri: android.net.Uri
    ): String? {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${MediaStore.Images.Media.RELATIVE_PATH} = ?"
        val selectionArgs = arrayOf(originalName, relativePath)

        val exists = resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { cursor ->
            cursor.count > 0
        } ?: false

        if (!exists) return originalName

        return when (dedupMode) {
            "skip" -> null
            "rename" -> generateUniqueName(originalName, relativePath, resolver, imageUri)
            else -> null
        }
    }

    private fun generateUniqueName(
        originalName: String,
        relativePath: String,
        resolver: android.content.ContentResolver,
        imageUri: android.net.Uri
    ): String {
        val dotIndex = originalName.lastIndexOf('.')
        val nameWithoutExt = if (dotIndex > 0) originalName.substring(0, dotIndex) else originalName
        val ext = if (dotIndex > 0) originalName.substring(dotIndex) else ""

        for (i in 1..999) {
            val candidate = "${nameWithoutExt}_$i$ext"
            val projection = arrayOf(MediaStore.Images.Media._ID)
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${MediaStore.Images.Media.RELATIVE_PATH} = ?"
            val selectionArgs = arrayOf(candidate, relativePath)

            val exists = resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { cursor ->
                cursor.count > 0
            } ?: false

            if (!exists) return candidate
        }
        return "${nameWithoutExt}_${System.currentTimeMillis()}$ext"
    }
}
