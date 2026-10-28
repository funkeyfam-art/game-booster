package com.example.gamebooster

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs

data class SystemSnapshot(
    val ramTotal: Long,
    val ramUsed: Long,
    val storageTotal: Long,
    val storageUsed: Long,
    val batteryPercent: Int,
    val batteryTempC: Float,
    val charging: Boolean,
    val thermal: String
) {
    val ramFraction: Float get() = if (ramTotal > 0) ramUsed.toFloat() / ramTotal else 0f
    val storageFraction: Float get() = if (storageTotal > 0) storageUsed.toFloat() / storageTotal else 0f
}

object SystemStats {

    fun read(context: Context): SystemSnapshot {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }

        val stat = StatFs(Environment.getDataDirectory().path)
        val sTotal = stat.totalBytes
        val sUsed = sTotal - stat.availableBytes

        val bat = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bat?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = bat?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) level * 100 / scale else 0
        val temp = (bat?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10f
        val status = bat?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        return SystemSnapshot(
            ramTotal = mi.totalMem,
            ramUsed = mi.totalMem - mi.availMem,
            storageTotal = sTotal,
            storageUsed = sUsed,
            batteryPercent = pct,
            batteryTempC = temp,
            charging = charging,
            thermal = thermalStatus(context)
        )
    }

    private fun thermalStatus(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "N/A"
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "Normal"
            PowerManager.THERMAL_STATUS_LIGHT -> "Light"
            PowerManager.THERMAL_STATUS_MODERATE -> "Moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "Severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "Critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "Emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "Shutdown"
            else -> "Unknown"
        }
    }
}
