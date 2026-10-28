package com.example.gamebooster

import android.app.usage.StorageStatsManager
import android.content.Context
import android.os.Process
import android.os.storage.StorageManager
import androidx.compose.ui.graphics.ImageBitmap

data class AppUsageItem(
    val label: String,
    val pkg: String,
    val total: Long,
    val cache: Long,
    val icon: ImageBitmap?
)

object AppManager {
    /** Needs Usage access. Call from a background thread. */
    fun load(context: Context): List<AppUsageItem> {
        val ssm = context.getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
        val user = Process.myUserHandle()
        return Apps.launchable(context).mapNotNull { a ->
            try {
                val st = ssm.queryStatsForPackage(StorageManager.UUID_DEFAULT, a.pkg, user)
                AppUsageItem(a.label, a.pkg, st.appBytes + st.dataBytes + st.cacheBytes, st.cacheBytes, a.icon)
            } catch (e: Exception) {
                null
            }
        }.sortedByDescending { it.total }
    }
}
