package com.example.gamebooster

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap

data class AppItem(
    val label: String,
    val pkg: String,
    val isGame: Boolean,
    val icon: ImageBitmap?
)

object Apps {

    private fun launcherIntent() =
        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

    fun launchablePackages(context: Context): List<String> {
        val pm = context.packageManager
        return pm.queryIntentActivities(launcherIntent(), 0)
            .map { it.activityInfo.packageName }
            .filter { it != context.packageName }
            .distinct()
    }

    @Suppress("DEPRECATION")
    private fun looksLikeGame(ai: ApplicationInfo): Boolean =
        ai.category == ApplicationInfo.CATEGORY_GAME ||
                (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0

    /** Packages that count as games: detected games + the ones the user starred. */
    fun gamePackages(context: Context): Set<String> {
        val pm = context.packageManager
        val set = HashSet<String>()
        for (ri in pm.queryIntentActivities(launcherIntent(), 0)) {
            val ai = ri.activityInfo.applicationInfo
            if (looksLikeGame(ai)) set.add(ai.packageName)
        }
        set.addAll(Prefs.pinned(context))
        return set
    }

    /** Full list with icons. Call from a background thread. */
    fun launchable(context: Context): List<AppItem> {
        val pm = context.packageManager
        return pm.queryIntentActivities(launcherIntent(), 0)
            .mapNotNull { ri ->
                val ai = ri.activityInfo.applicationInfo
                if (ai.packageName == context.packageName) return@mapNotNull null
                val icon = try {
                    ri.loadIcon(pm).toBitmap(96, 96).asImageBitmap()
                } catch (e: Exception) {
                    null
                }
                AppItem(ri.loadLabel(pm).toString(), ai.packageName, looksLikeGame(ai), icon)
            }
            .distinctBy { it.pkg }
            .sortedBy { it.label.lowercase() }
    }
}
