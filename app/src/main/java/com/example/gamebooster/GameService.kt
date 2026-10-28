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
            scope.launch(Dispatchers.IO) { Booster.killBackground(this@GameService, pkg) }
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
