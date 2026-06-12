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
                    val total = call.argument<Int>("total") ?: 1
                    val dedupMode = call.argument<String>("dedupMode") ?: "skip"
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val saved = saveToGallery(filePath, folderName, index, total, dedupMode)
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

        return filePaths.map { filePath ->
            val fileName = File(filePath).name
            val projection = arrayOf(MediaStore.Images.Media._ID)
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ?"
            val selectionArgs = arrayOf(fileName)

            resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { cursor ->
                cursor.count > 0
            } ?: false
        }
    }

    private fun saveToGallery(filePath: String, folderName: String, index: Int, total: Int, dedupMode: String): Map<String, Int> {
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

        val paddedIndex = String.format("%03d", total - index)
        val prefixedName = "${paddedIndex}_${sourceFile.name}"

        // skip 模式：检查带前缀名是否已存在
        if (dedupMode == "skip") {
            val exists = fileExists(prefixedName, resolver, imageUri)
            if (exists) return mapOf("saved" to 0, "skipped" to 1, "failed" to 0)
        }

        // Honor 相册按 DATE_ADDED 升序显示（旧的在前）
        // index 越小 → 时间越旧 → 排在前面 → 正序
        val baseTime = System.currentTimeMillis() / 1000 - 10000 + index
        val baseTimeMs = baseTime * 1000

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, prefixedName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.DATE_ADDED, baseTime)
            put(MediaStore.Images.Media.DATE_MODIFIED, baseTime)
            put(MediaStore.Images.Media.DATE_TAKEN, baseTimeMs)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
            }
        }

        val uri = resolver.insert(imageUri, values)
            ?: throw Exception("Failed to create MediaStore entry")

        resolver.openOutputStream(uri)?.use { out ->
            FileInputStream(sourceFile).use { input -> input.copyTo(out) }
        }

        return mapOf("saved" to 1, "skipped" to 0, "failed" to 0)
    }

    private fun fileExists(displayName: String, resolver: android.content.ContentResolver, imageUri: android.net.Uri): Boolean {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(displayName)
        return resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { it.count > 0 } ?: false
    }

    private fun deleteExistingFiles(
        originalName: String,
        resolver: android.content.ContentResolver,
        imageUri: android.net.Uri
    ) {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ? OR ${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf(originalName, "%\\_$originalName")
        resolver.query(imageUri, projection, selection, selectionArgs, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext()) {
                try { resolver.delete(imageUri, "_id=?", arrayOf(cursor.getLong(idIdx).toString())) } catch (_: Exception) {}
            }
        }
    }
}
