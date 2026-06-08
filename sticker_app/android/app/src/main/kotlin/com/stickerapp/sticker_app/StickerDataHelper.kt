package com.stickerapp.sticker_app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File

/**
 * Reads sticker data directly from the same SQLite database that Flutter's sqflite uses.
 * This avoids needing platform channel for data transfer.
 */
class StickerDataHelper(private val context: Context) {

    companion object {
        private const val TAG = "StickerDataHelper"
        private const val DB_NAME = "stickers.db"
    }

    data class StickerItem(
        val id: String,
        val packId: String,
        val path: String,
        val type: String
    )

    data class StickerPackInfo(
        val id: String,
        val name: String,
        val stickerCount: Int
    )

    private fun getDatabasePath(): String {
        // sqflite stores databases in the standard Android databases directory
        val dbFile = context.getDatabasePath(DB_NAME)
        if (dbFile.exists()) return dbFile.absolutePath

        // Fallback: check app_flutter directory (older sqflite versions)
        val flutterDb = File(context.applicationInfo.dataDir, "databases/$DB_NAME")
        if (flutterDb.exists()) return flutterDb.absolutePath

        return dbFile.absolutePath
    }

    fun getStickers(): List<StickerItem> {
        val dbPath = getDatabasePath()
        if (!File(dbPath).exists()) {
            Log.w(TAG, "Database not found at $dbPath")
            return emptyList()
        }

        val stickers = mutableListOf<StickerItem>()
        val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        try {
            db.rawQuery(
                "SELECT id, pack_id, local_path, type FROM stickers ORDER BY created_at DESC",
                null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val packId = cursor.getString(1)
                    val localPath = cursor.getString(2) ?: continue
                    val type = cursor.getString(3) ?: "image"

                    if (File(localPath).exists()) {
                        stickers.add(StickerItem(id, packId, localPath, type))
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read stickers from database", e)
        } finally {
            db.close()
        }

        return stickers
    }

    fun getStickersByPack(packId: String): List<StickerItem> {
        val dbPath = getDatabasePath()
        if (!File(dbPath).exists()) return emptyList()

        val stickers = mutableListOf<StickerItem>()
        val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        try {
            db.rawQuery(
                "SELECT id, pack_id, local_path, type FROM stickers WHERE pack_id = ? ORDER BY created_at",
                arrayOf(packId)
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val pid = cursor.getString(1)
                    val localPath = cursor.getString(2) ?: continue
                    val type = cursor.getString(3) ?: "image"
                    if (File(localPath).exists()) {
                        stickers.add(StickerItem(id, pid, localPath, type))
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read stickers for pack $packId", e)
        } finally {
            db.close()
        }

        return stickers
    }

    fun getStickerPacks(): List<StickerPackInfo> {
        val dbPath = getDatabasePath()
        if (!File(dbPath).exists()) return emptyList()

        val packs = mutableListOf<StickerPackInfo>()
        val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        try {
            db.rawQuery(
                "SELECT id, name, sticker_count FROM sticker_packs ORDER BY updated_at DESC",
                null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val name = cursor.getString(1) ?: ""
                    val count = cursor.getInt(2)
                    packs.add(StickerPackInfo(id, name, count))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read sticker packs", e)
        } finally {
            db.close()
        }

        return packs
    }

    /**
     * Get all stickers grouped by pack in a single DB connection.
     * Returns list of (StickerPackInfo, List<StickerItem>) pairs.
     */
    fun getAllStickersGrouped(): List<Pair<StickerPackInfo, List<StickerItem>>> {
        val dbPath = getDatabasePath()
        if (!File(dbPath).exists()) return emptyList()

        val result = mutableListOf<Pair<StickerPackInfo, List<StickerItem>>>()
        val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        try {
            // Load packs
            val packs = mutableListOf<StickerPackInfo>()
            db.rawQuery(
                "SELECT id, name, sticker_count FROM sticker_packs ORDER BY updated_at DESC",
                null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    packs.add(StickerPackInfo(cursor.getString(0), cursor.getString(1) ?: "", cursor.getInt(2)))
                }
            }

            // Load all stickers in one query
            val stickersByPack = mutableMapOf<String, MutableList<StickerItem>>()
            db.rawQuery(
                "SELECT id, pack_id, local_path, type FROM stickers ORDER BY pack_id, created_at",
                null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val localPath = cursor.getString(2) ?: continue
                    if (!File(localPath).exists()) continue
                    val item = StickerItem(cursor.getString(0), cursor.getString(1), localPath, cursor.getString(3) ?: "image")
                    stickersByPack.getOrPut(item.packId) { mutableListOf() }.add(item)
                }
            }

            for (pack in packs) {
                val stickers = stickersByPack[pack.id] ?: continue
                if (stickers.isNotEmpty()) {
                    result.add(Pair(pack, stickers))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read grouped stickers", e)
        } finally {
            db.close()
        }

        return result
    }
}
