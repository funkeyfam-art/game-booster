package com.example.gamebooster

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Environment
import android.os.StatFs
import rikka.shizuku.Shizuku

/** Advanced actions that need Shizuku (shell-level permission). */
object Pro {

    fun available(): Boolean = try {
        Shizuku.pingBinder()
    } catch (e: Throwable) {
        false
    }

    fun granted(): Boolean = try {
        available() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (e: Throwable) {
        false
    }

    fun request() {
        try {
            Shizuku.requestPermission(1001)
        } catch (e: Throwable) {
        }
    }

    /** Runs a shell command with shell (adb) privileges. Call off the main thread. */
    fun run(cmd: String): String {
        return try {
            val m = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java
            )
            m.isAccessible = true
            val p = m.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            p.waitFor()
            (out + err).trim()
        } catch (e: Throwable) {
            "Error: ${e.message ?: e.toString()}"
        }
    }

    fun freeStorage(): Long = StatFs(Environment.getDataDirectory().path).availableBytes

    private fun homePackage(ctx: Context): String? {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return ctx.packageManager
            .resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
    }

    /** Force-stops every app that has a launcher icon, except this app, the home screen and Shizuku. */
    fun forceStopAll(ctx: Context, keep: String?): Int {
        val home = homePackage(ctx)
        val pkgs = Apps.launchablePackages(ctx).filter {
            it != keep && it != home && it != ctx.packageName && it != "moe.shizuku.privileged.api"
        }
        if (pkgs.isEmpty()) return 0
        run(pkgs.joinToString("; ") { "am force-stop $it" })
        return pkgs.size
    }

    fun clearAllCache(): String = run("pm trim-caches 999999999999")

    fun lockRefresh(hz: Int): String = run(
        "settings put system peak_refresh_rate $hz; " +
                "settings put system min_refresh_rate $hz; " +
                "settings put system user_refresh_rate $hz"
    )

    fun resetRefresh(): String = run(
        "settings delete system min_refresh_rate; " +
                "settings delete system peak_refresh_rate; " +
                "settings delete system user_refresh_rate"
    )

    fun animationScale(scale: String): String = run(
        "settings put global window_animation_scale $scale; " +
                "settings put global transition_animation_scale $scale; " +
                "settings put global animator_duration_scale $scale"
    )

    /** mode: "performance", "standard" or "battery" (Android 12+). */
    fun gameMode(pkg: String, mode: String): String {
        val code = when (mode) {
            "performance" -> 2
            "battery" -> 3
            else -> 1
        }
        return run("cmd game mode $mode $pkg || cmd game set --mode $code $pkg")
    }

    fun restore(ctx: Context, pkg: String) {
        gameMode(pkg, "standard")
        if (Prefs.getInt(ctx, Prefs.REFRESH, 0) > 0) resetRefresh()
    }
}
