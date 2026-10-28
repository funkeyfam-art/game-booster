package com.example.gamebooster

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

object Booster {

    fun freeRam(context: Context): Long {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        return mi.availMem
    }

    /** Asks Android to close background processes of all other launcher apps. */
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

    fun openDndAccess(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    fun launch(context: Context, pkg: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
