#!/bin/bash
# Step 5: Shizuku Pro mode. Run: bash setup5.sh
set -e
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/GameService.kt" <<'GB_EOF'
package com.example.gamebooster

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Watches which app is in the foreground. When a game opens it can
 * auto-boost (close background apps), turn on Do Not Disturb and show a live overlay.
 */
class GameService : Service() {

    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.Default + job)
    private val main = Handler(Looper.getMainLooper())

    private var overlay: TextView? = null
    private var activeGame: String? = null
    private var turnedDndOn = false
    private var lastHotWarn = 0L
    private var ping = -1
    private var currentFg: String? = null
    private var lastCheck = System.currentTimeMillis() - 10 * 60 * 1000L
    private var games: Set<String> = emptySet()
    private var gamesRefreshed = 0L
    @Volatile private var proApplied = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel("monitor", "Game monitor", NotificationManager.IMPORTANCE_LOW)
        )
        nm.createNotificationChannel(
            NotificationChannel("alerts", "Alerts", NotificationManager.IMPORTANCE_HIGH)
        )
        val n = note("Watching for games...", "monitor")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
        scope.launch {
            var tick = 0
            while (true) {
                try {
                    step(tick)
                } catch (e: Exception) {
                    // ignore and try again on next tick
                }
                tick++
                delay(2000)
            }
        }
    }

    override fun onDestroy() {
        endGame()
        job.cancel()
        super.onDestroy()
    }

    private fun note(text: String, channel: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, channel)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle("Game Booster")
            .setContentText(text)
            .setContentIntent(pi)
            .setOngoing(channel == "monitor")
            .build()
    }

    private fun notifyUser(id: Int, n: Notification) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, n)
    }

    @Suppress("DEPRECATION")
    private fun updateForeground(now: Long) {
        if (!Booster.hasUsageAccess(this)) return
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(lastCheck, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                currentFg = e.packageName
            } else if (e.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND && e.packageName == currentFg) {
                currentFg = null
            }
        }
        lastCheck = now
    }

    private fun step(tick: Int) {
        val now = System.currentTimeMillis()
        if (now - gamesRefreshed > 60_000L) {
            games = Apps.gamePackages(this)
            gamesRefreshed = now
        }
        updateForeground(now)

        val fg = currentFg
        if (fg != null && fg in games) {
            if (activeGame != fg) startGame(fg)
        } else if (activeGame != null) {
            endGame()
        }

        if (activeGame != null) {
            if (tick % 2 == 0) {
                scope.launch(Dispatchers.IO) { ping = Net.pingMs() }
            }
            updateOverlay()
            thermalCheck(now)
        }
    }

    private fun startGame(pkg: String) {
        if (activeGame != null) endGame()
        activeGame = pkg
        if (Prefs.get(this, Prefs.AUTO_BOOST, true)) {
            if (Pro.granted()) {
                proApplied = true
                scope.launch(Dispatchers.IO) {
                    Pro.forceStopAll(this@GameService, pkg)
                    Pro.gameMode(pkg, "performance")
                    val hz = Prefs.getInt(this@GameService, Prefs.REFRESH, 0)
                    if (hz > 0) Pro.lockRefresh(hz)
                }
            } else {
                scope.launch(Dispatchers.IO) { Booster.killBackground(this@GameService, pkg) }
            }
        }
        if (Prefs.get(this, Prefs.AUTO_DND, false) && Booster.hasDndAccess(this) && !Booster.isDndOn(this)) {
            Booster.setDnd(this, true)
            turnedDndOn = true
        }
        if (Prefs.get(this, Prefs.OVERLAY, true) && Booster.canOverlay(this)) {
            showOverlay()
        }
        notifyUser(1, note("Game boost active", "monitor"))
    }

    private fun endGame() {
        if (activeGame == null && overlay == null) return
        hideOverlay()
        val g = activeGame
        if (g != null && proApplied) {
            proApplied = false
            Thread { Pro.restore(this, g) }.start()
        }
        if (turnedDndOn) {
            Booster.setDnd(this, false)
            turnedDndOn = false
        }
        activeGame = null
        notifyUser(1, note("Watching for games...", "monitor"))
    }

    private fun showOverlay() {
        main.post {
            if (overlay != null) return@post
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val tv = TextView(this)
            tv.setTextColor(Color.WHITE)
            tv.textSize = 12f
            tv.setPadding(20, 10, 20, 10)
            tv.setBackgroundColor(0x99000000.toInt())
            tv.text = "Game Booster"
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            lp.gravity = Gravity.TOP or Gravity.START
            lp.x = 24
            lp.y = 120
            try {
                wm.addView(tv, lp)
                overlay = tv
            } catch (e: Exception) {
                // overlay permission missing
            }
        }
    }

    private fun hideOverlay() {
        main.post {
            val v = overlay ?: return@post
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            try {
                wm.removeView(v)
            } catch (e: Exception) {
            }
            overlay = null
        }
    }

    private fun updateOverlay() {
        if (overlay == null) return
        val s = SystemStats.read(this)
        val pingText = if (ping < 0) "--" else "$ping ms"
        val t = "RAM ${(s.ramFraction * 100).toInt()}%   " +
                "%.1f°C   ".format(s.batteryTempC) +
                "${s.thermal}   Ping $pingText"
        main.post { overlay?.text = t }
    }

    private fun thermalCheck(now: Long) {
        if (!Prefs.get(this, Prefs.THERMAL, true)) return
        if (now - lastHotWarn < 5 * 60_000L) return
        val s = SystemStats.read(this)
        val hot = s.thermal == "Critical" || s.thermal == "Emergency" ||
                (s.thermal == "Severe" && s.batteryTempC >= 40f)
        if (hot) {
            lastHotWarn = now
            notifyUser(
                2,
                note("Your phone is very hot. Take a short break to avoid slowdown.", "alerts")
            )
        }
    }

    companion object {
        fun start(c: Context) {
            ContextCompat.startForegroundService(c, Intent(c, GameService::class.java))
        }

        fun stop(c: Context) {
            c.stopService(Intent(c, GameService::class.java))
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Prefs.kt" <<'GB_EOF'
package com.example.gamebooster

import android.content.Context

object Prefs {
    const val MONITOR = "monitor"
    const val AUTO_BOOST = "auto_boost"
    const val AUTO_DND = "auto_dnd"
    const val OVERLAY = "overlay"
    const val THERMAL = "thermal"
    const val REFRESH = "refresh_hz"

    private fun sp(c: Context) = c.getSharedPreferences("gb_prefs", Context.MODE_PRIVATE)

    fun get(c: Context, key: String, def: Boolean): Boolean = sp(c).getBoolean(key, def)

    fun set(c: Context, key: String, value: Boolean) {
        sp(c).edit().putBoolean(key, value).apply()
    }

    fun getInt(c: Context, key: String, def: Int): Int = sp(c).getInt(key, def)

    fun setInt(c: Context, key: String, value: Int) {
        sp(c).edit().putInt(key, value).apply()
    }

    fun pinned(c: Context): Set<String> =
        HashSet(sp(c).getStringSet("pinned", emptySet()) ?: emptySet())

    fun togglePinned(c: Context, pkg: String) {
        val s = HashSet(pinned(c))
        if (!s.remove(pkg)) s.add(pkg)
        sp(c).edit().putStringSet("pinned", s).apply()
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Pro.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/ProScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ProScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(Pro.available()) }
    var granted by remember { mutableStateOf(Pro.granted()) }
    var busy by remember { mutableStateOf(false) }
    var log by remember { mutableStateOf<String?>(null) }
    var hzGame by remember { mutableStateOf(Prefs.getInt(ctx, Prefs.REFRESH, 0)) }
    var fastAnim by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        while (true) {
            running = Pro.available()
            granted = Pro.granted()
            delay(1000)
        }
    }

    val act: (() -> String) -> Unit = { block ->
        scope.launch {
            busy = true
            log = withContext(Dispatchers.IO) { block() }
            busy = false
        }
    }

    ScreenColumn {
        Text("Pro mode (Shizuku)", style = MaterialTheme.typography.headlineMedium)

        if (!running) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Shizuku is not running. Open Shizuku and tap Start, then come back.")
                    Button(onClick = { Booster.launch(ctx, "moe.shizuku.privileged.api") }) {
                        Text("Open Shizuku")
                    }
                }
            }
        } else if (!granted) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Shizuku is running. Allow this app to use it.")
                    Button(onClick = { Pro.request() }) { Text("Allow Shizuku permission") }
                }
            }
        } else {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Deep boost", style = MaterialTheme.typography.titleMedium)
                    Text("Force-stops all other apps (the ones with an icon). Home screen and Shizuku are kept.")
                    Button(
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            act {
                                val before = Booster.freeRam(ctx)
                                val n = Pro.forceStopAll(ctx, null)
                                Thread.sleep(1500)
                                val freed = (Booster.freeRam(ctx) - before).coerceAtLeast(0)
                                "Force-stopped $n apps. RAM freed: ${fmt(freed)}"
                            }
                        }
                    ) { Text(if (busy) "Working..." else "Force-stop all apps") }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Clear all app cache", style = MaterialTheme.typography.titleMedium)
                    Text("Clears the cache of every app in one go.")
                    Button(
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            act {
                                val before = Pro.freeStorage()
                                val out = Pro.clearAllCache()
                                Thread.sleep(1500)
                                val freed = (Pro.freeStorage() - before).coerceAtLeast(0)
                                "Cache cleared. Storage freed: ${fmt(freed)}" +
                                        (if (out.isNotEmpty()) "\n$out" else "")
                            }
                        }
                    ) { Text("Clear cache") }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Refresh rate (now)", style = MaterialTheme.typography.titleMedium)
                    Text("Locks the screen refresh rate. Works only if your screen supports that rate.")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(60, 90, 120).forEach { hz ->
                            OutlinedButton(
                                enabled = !busy,
                                modifier = Modifier.weight(1f),
                                onClick = { act { Pro.lockRefresh(hz); "Refresh rate set to $hz Hz" } }
                            ) { Text("$hz") }
                        }
                        OutlinedButton(
                            enabled = !busy,
                            modifier = Modifier.weight(1f),
                            onClick = { act { Pro.resetRefresh(); "Refresh rate reset to automatic" } }
                        ) { Text("Reset") }
                    }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ToggleRow(
                        "Fast animations",
                        "Makes the phone feel faster (0.5x animation time)",
                        fastAnim
                    ) { v ->
                        fastAnim = v
                        act { Pro.animationScale(if (v) "0.5" else "1.0"); if (v) "Animations: 0.5x" else "Animations: normal" }
                    }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("When a game starts", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "With Auto boost on, the Boost tab's game monitor will force-stop other apps, " +
                                "set the game to Performance mode, and lock the refresh rate below. " +
                                "Everything is restored when you leave the game."
                    )
                    Text("Refresh rate while gaming", style = MaterialTheme.typography.titleSmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(0, 60, 90, 120).forEach { hz ->
                            val label = if (hz == 0) "Off" else "$hz"
                            val pick = {
                                hzGame = hz
                                Prefs.setInt(ctx, Prefs.REFRESH, hz)
                            }
                            if (hzGame == hz) {
                                Button(onClick = pick, modifier = Modifier.weight(1f)) { Text(label) }
                            } else {
                                OutlinedButton(onClick = pick, modifier = Modifier.weight(1f)) { Text(label) }
                            }
                        }
                    }
                }
            }
        }

        log?.let {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Result", style = MaterialTheme.typography.titleSmall)
                    Text(it)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Root.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

@Composable
fun Root() {
    var tab by remember { mutableStateOf(0) }
    val tabs = listOf(
        "Boost" to "⚡", "Games" to "🎮", "Clean" to "🧹",
        "Security" to "🛡", "Apps" to "📱", "Pro" to "🚀"
    )

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i,
                        onClick = { tab = i },
                        icon = { Text(t.second) },
                        label = { Text(t.first, maxLines = 1) }
                    )
                }
            }
        }
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when (tab) {
                0 -> HomeScreen()
                1 -> GamesScreen()
                2 -> CleanScreen()
                3 -> SecurityScreen()
                4 -> AppsScreen()
                else -> ProScreen()
            }
        }
    }
}
GB_EOF
python3 - <<'PY'
p = 'app/src/main/AndroidManifest.xml'
s = open(p).read()
if 'ShizukuProvider' not in s:
    s = s.replace('</application>', '''        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
    </application>''')
    s = s.replace('<queries>', '<uses-permission android:name="moe.shizuku.manager.permission.API_V23" />\n\n    <queries>', 1)
    open(p, 'w').write(s)
p = 'app/build.gradle.kts'
s = open(p).read()
if 'shizuku' not in s:
    s = s.replace('implementation("androidx.compose.material3:material3")',
                  'implementation("androidx.compose.material3:material3")\n    implementation("dev.rikka.shizuku:api:13.1.5")\n    implementation("dev.rikka.shizuku:provider:13.1.5")')
    open(p, 'w').write(s)
PY
grep -c ShizukuProvider app/src/main/AndroidManifest.xml
grep -c shizuku app/build.gradle.kts
echo "Step 5 files updated!"
