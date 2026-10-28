package com.example.gamebooster

import android.os.Environment
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

data class FileItem(val path: String, val size: Long)

data class ScanResult(
    val junk: List<FileItem>,
    val apks: List<FileItem>,
    val large: List<FileItem>,
    val dups: List<FileItem>,
    val byType: Map<String, Long>,
    val scanned: Int
)

object Cleaner {

    private val SAFE_TOP = setOf("DCIM", "Pictures", "Download", "Downloads", "Movies", "Music", "Documents")
    private val JUNK_EXT = setOf("tmp", "temp", "log", "bak", "old", "chk", "dmp")
    private val IMG = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "bmp")
    private val VID = setOf("mp4", "mkv", "avi", "mov", "3gp", "webm")
    private val AUD = setOf("mp3", "m4a", "wav", "aac", "ogg", "flac", "opus")
    private val DOC = setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "epub")
    private val ZIP = setOf("zip", "rar", "7z", "tar", "gz")

    private const val LARGE = 100L * 1024 * 1024

    fun scan(): ScanResult {
        val root = Environment.getExternalStorageDirectory()
        val rootPath = root.absolutePath
        val junk = ArrayList<FileItem>()
        val apks = ArrayList<FileItem>()
        val large = ArrayList<FileItem>()
        val dups = ArrayList<FileItem>()
        val bySize = HashMap<Long, MutableList<File>>()
        val types = linkedMapOf(
            "Images" to 0L, "Videos" to 0L, "Audio" to 0L, "Documents" to 0L,
            "Archives" to 0L, "APK files" to 0L, "Other" to 0L
        )
        var count = 0

        root.walkTopDown()
            .onEnter { d -> d.absolutePath != "$rootPath/Android" }
            .forEach { f ->
                if (!f.isFile) return@forEach
                if (count > 300_000) return@forEach
                count++
                val name = f.name.lowercase()
                val ext = name.substringAfterLast('.', "")
                val size = f.length()

                val key = when {
                    ext == "apk" -> "APK files"
                    ext in IMG -> "Images"
                    ext in VID -> "Videos"
                    ext in AUD -> "Audio"
                    ext in DOC -> "Documents"
                    ext in ZIP -> "Archives"
                    else -> "Other"
                }
                types[key] = (types[key] ?: 0L) + size

                val path = f.absolutePath
                val isJunk = ext in JUNK_EXT || name.startsWith(".trashed-") ||
                        path.contains("/.thumbnails/")
                if (isJunk) {
                    junk.add(FileItem(path, size))
                } else if (ext == "apk") {
                    apks.add(FileItem(path, size))
                } else if (size >= LARGE) {
                    large.add(FileItem(path, size))
                }

                if (size > 100 * 1024 && !isJunk) {
                    val top = path.removePrefix("$rootPath/").substringBefore('/')
                    if (top in SAFE_TOP) {
                        bySize.getOrPut(size) { mutableListOf() }.add(f)
                    }
                }
            }

        for ((size, files) in bySize) {
            if (files.size < 2 || size > 300L * 1024 * 1024) continue
            val byHash = HashMap<String, MutableList<File>>()
            for (f in files) {
                val h = hashOf(f) ?: continue
                byHash.getOrPut(h) { mutableListOf() }.add(f)
            }
            for (g in byHash.values) {
                if (g.size >= 2) {
                    val sorted = g.sortedBy { it.lastModified() }
                    for (x in sorted.drop(1)) dups.add(FileItem(x.absolutePath, size))
                }
            }
        }

        return ScanResult(
            junk = junk.sortedByDescending { it.size },
            apks = apks.sortedByDescending { it.size },
            large = large.sortedByDescending { it.size },
            dups = dups.sortedByDescending { it.size },
            byType = types,
            scanned = count
        )
    }

    private fun hashOf(f: File): String? {
        return try {
            val md = MessageDigest.getInstance("MD5")
            FileInputStream(f).use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    md.update(buf, 0, n)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            null
        }
    }

    fun delete(items: List<FileItem>): Int = items.count { File(it.path).delete() }
}
