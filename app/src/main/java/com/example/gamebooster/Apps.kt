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

    /** Package names of every app that has a launcher icon (except this app). */
    fun launchablePackages(context: Context): List<String> {
        val pm = context.packageManager
        return pm.queryIntentActivities(launcherIntent(), 0)
            .map { it.activityInfo.packageName }
            .filter { it != context.packageName }
            .distinct()
    }

    /** Full list with name, icon and "is this a game" flag. Call from a background thread. */
    @Suppress("DEPRECATION")
    fun launchable(context: Context): List<AppItem> {
        val pm = context.packageManager
        return pm.queryIntentActivities(launcherIntent(), 0)
            .mapNotNull { ri ->
                val ai = ri.activityInfo.applicationInfo
                if (ai.packageName == context.packageName) return@mapNotNull null
                val game = ai.category == ApplicationInfo.CATEGORY_GAME ||
                        (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0
                val icon = try {
                    ri.loadIcon(pm).toBitmap(96, 96).asImageBitmap()
                } catch (e: Exception) {
                    null
                }
                AppItem(ri.loadLabel(pm).toString(), ai.packageName, game, icon)
            }
            .distinctBy { it.pkg }
            .sortedBy { it.label.lowercase() }
    }
}
