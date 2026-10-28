package com.example.gamebooster

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class AppRisk(val label: String, val pkg: String, val score: Int, val reasons: List<String>) {
    val level: String get() = when {
        score >= 8 -> "High"
        score >= 4 -> "Medium"
        else -> "Low"
    }
}

data class DeviceCheck(val title: String, val ok: Boolean, val detail: String)

data class SecurityReport(val apps: List<AppRisk>, val device: List<DeviceCheck>, val score: Int)

object Security {

    private val STORES = setOf(
        "com.android.vending", "com.sec.android.app.samsungapps", "com.xiaomi.mipicks",
        "com.xiaomi.market", "com.huawei.appmarket", "com.amazon.venezia",
        "com.heytap.market", "com.oppo.market", "com.vivo.appstore", "com.transsion.appstore"
    )

    private val PERMS = mapOf(
        "android.permission.READ_SMS" to Pair(3, "Reads your SMS"),
        "android.permission.SEND_SMS" to Pair(3, "Can send SMS"),
        "android.permission.RECEIVE_SMS" to Pair(2, "Receives SMS"),
        "android.permission.READ_CALL_LOG" to Pair(3, "Reads call log"),
        "android.permission.READ_CONTACTS" to Pair(1, "Reads contacts"),
        "android.permission.RECORD_AUDIO" to Pair(2, "Uses microphone"),
        "android.permission.CAMERA" to Pair(1, "Uses camera"),
        "android.permission.ACCESS_FINE_LOCATION" to Pair(1, "Precise location"),
        "android.permission.ACCESS_BACKGROUND_LOCATION" to Pair(2, "Location in background"),
        "android.permission.SYSTEM_ALERT_WINDOW" to Pair(2, "Draws over other apps"),
        "android.permission.REQUEST_INSTALL_PACKAGES" to Pair(2, "Can install apps"),
        "android.permission.MANAGE_EXTERNAL_STORAGE" to Pair(2, "Access to all files"),
        "android.permission.PACKAGE_USAGE_STATS" to Pair(1, "Sees app usage"),
        "android.permission.QUERY_ALL_PACKAGES" to Pair(1, "Sees all installed apps"),
        "android.permission.BIND_DEVICE_ADMIN" to Pair(3, "Device admin")
    )

    @Suppress("DEPRECATION")
    private fun installerOf(pm: PackageManager, pkg: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= 30) {
                pm.getInstallSourceInfo(pkg).installingPackageName
            } else {
                pm.getInstallerPackageName(pkg)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun accessibilityPackages(context: Context): Set<String> {
        return try {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .map { it.resolveInfo.serviceInfo.packageName }
                .toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    @Suppress("DEPRECATION")
    fun scan(context: Context): SecurityReport {
        val pm = context.packageManager
        val acc = accessibilityPackages(context)
        val risks = ArrayList<AppRisk>()

        for (pi in pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)) {
            val ai = pi.applicationInfo ?: continue
            if ((ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0) continue
            if (pi.packageName == context.packageName) continue

            var score = 0
            val reasons = ArrayList<String>()
            val requested = pi.requestedPermissions
            if (requested != null) {
                for (p in requested) {
                    val w = PERMS[p]
                    if (w != null) {
                        score += w.first
                        reasons.add(w.second)
                    }
                }
            }
            if (pi.packageName in acc) {
                score += 4
                reasons.add("Accessibility service enabled")
            }
            val installer = installerOf(pm, pi.packageName)
            if (installer == null || installer !in STORES) {
                score += 3
                reasons.add("Not installed from an app store")
            }
            if (score > 0) {
                risks.add(AppRisk(pm.getApplicationLabel(ai).toString(), pi.packageName, score, reasons))
            }
        }
        risks.sortByDescending { it.score }

        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val cr = context.contentResolver
        val adb = Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, 0) == 1
        val dev = Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
        val patch = Build.VERSION.SECURITY_PATCH
        val days = try {
            ChronoUnit.DAYS.between(LocalDate.parse(patch), LocalDate.now())
        } catch (e: Exception) {
            -1L
        }

        val device = listOf(
            DeviceCheck("Screen lock", km.isDeviceSecure, if (km.isDeviceSecure) "PIN/pattern/password set" else "No screen lock set"),
            DeviceCheck("USB debugging", !adb, if (adb) "ON, turn off if not needed" else "Off"),
            DeviceCheck("Developer options", !dev, if (dev) "ON" else "Off"),
            DeviceCheck("Security patch", days in 0..365, "Patch date: $patch")
        )

        var score = 100
        for (d in device) if (!d.ok) score -= 15
        for (a in risks) {
            if (a.level == "High") score -= 5 else if (a.level == "Medium") score -= 2
        }
        if (score < 0) score = 0

        return SecurityReport(risks, device, score)
    }
}
