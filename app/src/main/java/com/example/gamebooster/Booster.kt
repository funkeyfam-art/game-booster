package com.example.gamebooster

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.Settings

object Booster {

    private fun start(ctx: Context, intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
    }

    // ---------- RAM ----------
    fun freeRam(context: Context): Long {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        return mi.availMem
    }

    fun killBackground(context: Context, keep: String?): Int {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        var count = 0
        for (pkg in Apps.launchablePackages(context)) {
            if (pkg == keep) continue
            am.killBackgroundProcesses(pkg)
            count++
        }
        return count
    }

    // ---------- Do Not Disturb ----------
    private fun nm(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun hasDndAccess(context: Context): Boolean = nm(context).isNotificationPolicyAccessGranted

    fun isDndOn(context: Context): Boolean {
        val f = nm(context).currentInterruptionFilter
        return f != NotificationManager.INTERRUPTION_FILTER_ALL &&
                f != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
    }

    fun setDnd(context: Context, on: Boolean) {
        if (!hasDndAccess(context)) return
        nm(context).setInterruptionFilter(
            if (on) NotificationManager.INTERRUPTION_FILTER_PRIORITY
            else NotificationManager.INTERRUPTION_FILTER_ALL
        )
    }

    fun openDndAccess(context: Context) =
        start(context, Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))

    // ---------- Special permissions ----------
    @Suppress("DEPRECATION")
    fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openUsageAccess(context: Context) =
        start(context, Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))

    fun canOverlay(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun openOverlay(context: Context) = start(
        context,
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
    )

    fun hasAllFiles(): Boolean =
        Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()

    fun openAllFiles(context: Context) {
        try {
            start(
                context,
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                )
            )
        } catch (e: Exception) {
            start(context, Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    fun openAppInfo(context: Context, pkg: String) = start(
        context,
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
    )

    // ---------- Launch ----------
    fun launch(context: Context, pkg: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return
        start(context, intent)
    }
}
