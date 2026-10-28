#!/bin/bash
# Step 3: full app (overlay, auto-boost, cleaner, security, app manager). Run: bash setup3.sh
set -e
rm -f app/src/main/java/com/example/gamebooster/DashboardScreen.kt
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'GB_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.KILL_BACKGROUND_PROCESSES" />
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
        tools:ignore="ProtectedPermissions" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>

    <application
        android:allowBackup="true"
        android:label="Game Booster"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".GameService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="game_performance_monitor_overlay" />
        </service>
    </application>
</manifest>
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/AppManager.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Apps.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/AppsScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

@Composable
fun AppsScreen() {
    val ctx = LocalContext.current
    var usageOk by remember { mutableStateOf(Booster.hasUsageAccess(ctx)) }
    var items by remember { mutableStateOf<List<AppUsageItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        while (true) {
            usageOk = Booster.hasUsageAccess(ctx)
            delay(1000)
        }
    }

    LaunchedEffect(usageOk) {
        if (usageOk) {
            loading = true
            items = withContext(Dispatchers.IO) { AppManager.load(ctx) }
            loading = false
        }
    }

    ScreenColumn {
        Text("App manager", style = MaterialTheme.typography.headlineMedium)

        if (!usageOk) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Allow usage access to see how much space each app uses.")
                    Button(onClick = { Booster.openUsageAccess(ctx) }) { Text("Allow usage access") }
                }
            }
        } else {
            if (loading) Text("Loading...")
            if (items.isNotEmpty()) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Apps use ${fmt(items.sumOf { it.total })} in total", style = MaterialTheme.typography.titleMedium)
                        Text("Cache: ${fmt(items.sumOf { it.cache })}. Open an app's settings to clear its cache or uninstall it.")
                    }
                }
            }
            items.take(50).forEach { a ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        a.icon?.let {
                            Image(bitmap = it, contentDescription = null, modifier = Modifier.size(40.dp))
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(a.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                "${fmt(a.total)} · cache ${fmt(a.cache)}",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        TextButton(onClick = { Booster.openAppInfo(ctx, a.pkg) }) { Text("Manage") }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Booster.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/CleanScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun CleanScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var allFiles by remember { mutableStateOf(Booster.hasAllFiles()) }
    var scanning by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<ScanResult?>(null) }
    var pending by remember { mutableStateOf<List<FileItem>?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        while (true) {
            allFiles = Booster.hasAllFiles()
            delay(1000)
        }
    }

    val runScan: () -> Unit = {
        scope.launch {
            scanning = true
            result = withContext(Dispatchers.IO) { Cleaner.scan() }
            scanning = false
        }
    }

    pending?.let { list ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text("Delete ${list.size} file(s)?") },
            text = { Text("${fmt(list.sumOf { it.size })} will be deleted permanently. This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    scope.launch {
                        val n = withContext(Dispatchers.IO) { Cleaner.delete(list) }
                        message = "Deleted $n file(s)"
                        runScan()
                    }
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text("Cancel") } }
        )
    }

    ScreenColumn {
        Text("Clean and storage", style = MaterialTheme.typography.headlineMedium)

        if (Build.VERSION.SDK_INT < 30) {
            Text("The file cleaner needs Android 11 or newer.")
        } else if (!allFiles) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("To find junk, old APKs, large and duplicate files, the app needs access to all files.")
                    Button(onClick = { Booster.openAllFiles(ctx) }) { Text("Allow file access") }
                }
            }
        } else {
            Button(
                enabled = !scanning,
                modifier = Modifier.fillMaxWidth(),
                onClick = { runScan() }
            ) { Text(if (scanning) "Scanning..." else "Scan storage") }
            message?.let { Text(it) }

            result?.let { r ->
                Text("Scanned ${r.scanned} files", style = MaterialTheme.typography.bodySmall)

                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("What is using your storage", style = MaterialTheme.typography.titleMedium)
                        val total = r.byType.values.sum().coerceAtLeast(1L)
                        r.byType.forEach { (k, v) ->
                            Text("$k: ${fmt(v)}")
                            LinearProgressIndicator(
                                progress = { v.toFloat() / total },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }

                CleanSection("Junk files", r.junk) { pending = r.junk }
                CleanSection("Old APK files", r.apks) { pending = r.apks }
                CleanSection("Duplicate files (extra copies)", r.dups) { pending = r.dups }

                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "Large files (${r.large.size})",
                            style = MaterialTheme.typography.titleMedium
                        )
                        if (r.large.isEmpty()) Text("No files over 100 MB.")
                        r.large.take(15).forEach { item ->
                            val f = File(item.path)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(f.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(
                                        "${fmt(item.size)} · ${f.parentFile?.name ?: ""}",
                                        style = MaterialTheme.typography.bodySmall
                                    )
                                }
                                TextButton(onClick = { pending = listOf(item) }) { Text("Delete") }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun CleanSection(title: String, items: List<FileItem>, onDeleteAll: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            if (items.isEmpty()) {
                Text("Nothing found.")
            } else {
                Text("${items.size} files · ${fmt(items.sumOf { it.size })}")
                Button(onClick = onDeleteAll) { Text("Delete all") }
            }
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Cleaner.kt" <<'GB_EOF'
package com.example.gamebooster

import android.os.Environment
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

data class FileItem(val path: String, val size: Long)

data class ScanResult(
    val junk: List<FileItem>,
    val apks: List<FileItem>,
    val large: List<FileItem>,
    val dups: List<FileItem>,
    val byType: Map<String, Long>,
    val scanned: Int
)

object Cleaner {

    private val SAFE_TOP = setOf("DCIM", "Pictures", "Download", "Downloads", "Movies", "Music", "Documents")
    private val JUNK_EXT = setOf("tmp", "temp", "log", "bak", "old", "chk", "dmp")
    private val IMG = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "bmp")
    private val VID = setOf("mp4", "mkv", "avi", "mov", "3gp", "webm")
    private val AUD = setOf("mp3", "m4a", "wav", "aac", "ogg", "flac", "opus")
    private val DOC = setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "epub")
    private val ZIP = setOf("zip", "rar", "7z", "tar", "gz")

    private const val LARGE = 100L * 1024 * 1024

    fun scan(): ScanResult {
        val root = Environment.getExternalStorageDirectory()
        val rootPath = root.absolutePath
        val junk = ArrayList<FileItem>()
        val apks = ArrayList<FileItem>()
        val large = ArrayList<FileItem>()
        val dups = ArrayList<FileItem>()
        val bySize = HashMap<Long, MutableList<File>>()
        val types = linkedMapOf(
            "Images" to 0L, "Videos" to 0L, "Audio" to 0L, "Documents" to 0L,
            "Archives" to 0L, "APK files" to 0L, "Other" to 0L
        )
        var count = 0

        root.walkTopDown()
            .onEnter { d -> d.absolutePath != "$rootPath/Android" }
            .forEach { f ->
                if (!f.isFile) return@forEach
                if (count > 300_000) return@forEach
                count++
                val name = f.name.lowercase()
                val ext = name.substringAfterLast('.', "")
                val size = f.length()

                val key = when {
                    ext == "apk" -> "APK files"
                    ext in IMG -> "Images"
                    ext in VID -> "Videos"
                    ext in AUD -> "Audio"
                    ext in DOC -> "Documents"
                    ext in ZIP -> "Archives"
                    else -> "Other"
                }
                types[key] = (types[key] ?: 0L) + size

                val path = f.absolutePath
                val isJunk = ext in JUNK_EXT || name.startsWith(".trashed-") ||
                        path.contains("/.thumbnails/")
                if (isJunk) {
                    junk.add(FileItem(path, size))
                } else if (ext == "apk") {
                    apks.add(FileItem(path, size))
                } else if (size >= LARGE) {
                    large.add(FileItem(path, size))
                }

                if (size > 100 * 1024 && !isJunk) {
                    val top = path.removePrefix("$rootPath/").substringBefore('/')
                    if (top in SAFE_TOP) {
                        bySize.getOrPut(size) { mutableListOf() }.add(f)
                    }
                }
            }

        for ((size, files) in bySize) {
            if (files.size < 2 || size > 300L * 1024 * 1024) continue
            val byHash = HashMap<String, MutableList<File>>()
            for (f in files) {
                val h = hashOf(f) ?: continue
                byHash.getOrPut(h) { mutableListOf() }.add(f)
            }
            for (g in byHash.values) {
                if (g.size >= 2) {
                    val sorted = g.sortedBy { it.lastModified() }
                    for (x in sorted.drop(1)) dups.add(FileItem(x.absolutePath, size))
                }
            }
        }

        return ScanResult(
            junk = junk.sortedByDescending { it.size },
            apks = apks.sortedByDescending { it.size },
            large = large.sortedByDescending { it.size },
            dups = dups.sortedByDescending { it.size },
            byType = types,
            scanned = count
        )
    }

    private fun hashOf(f: File): String? {
        return try {
            val md = MessageDigest.getInstance("MD5")
            FileInputStream(f).use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    md.update(buf, 0, n)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            null
        }
    }

    fun delete(items: List<FileItem>): Int = items.count { File(it.path).delete() }
}
GB_EOF
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/GamesScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun GamesScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var apps by remember { mutableStateOf<List<AppItem>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var showAll by remember { mutableStateOf(false) }
    var pinned by remember { mutableStateOf(Prefs.pinned(ctx)) }

    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) { Apps.launchable(ctx) }
        loaded = true
    }

    ScreenColumn {
        Text("Games", style = MaterialTheme.typography.headlineMedium)
        Text("Tap ☆ to add a game to your list. Auto game mode only works for games in this list.")

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!showAll) Button(onClick = { showAll = false }) { Text("My games") }
            else OutlinedButton(onClick = { showAll = false }) { Text("My games") }
            if (showAll) Button(onClick = { showAll = true }) { Text("All apps") }
            else OutlinedButton(onClick = { showAll = true }) { Text("All apps") }
        }

        val shown = if (showAll) apps else apps.filter { it.isGame || it.pkg in pinned }
        if (shown.isEmpty()) {
            Text(
                if (!loaded) "Loading apps..."
                else "No games detected. Tap \"All apps\" and star your game."
            )
        }

        shown.forEach { app ->
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    app.icon?.let {
                        Image(bitmap = it, contentDescription = null, modifier = Modifier.size(44.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(
                        app.label,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    TextButton(onClick = {
                        Prefs.togglePinned(ctx, app.pkg)
                        pinned = Prefs.pinned(ctx)
                    }) { Text(if (app.pkg in pinned) "★" else "☆") }
                    Button(onClick = {
                        scope.launch {
                            withContext(Dispatchers.IO) { Booster.killBackground(ctx, app.pkg) }
                            Booster.launch(ctx, app.pkg)
                        }
                    }) { Text("Play") }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/HomeScreen.kt" <<'GB_EOF'
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
fun HomeScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var snap by remember { mutableStateOf(SystemStats.read(ctx)) }
    var ping by remember { mutableStateOf(-1) }
    var usageOk by remember { mutableStateOf(Booster.hasUsageAccess(ctx)) }
    var overlayOk by remember { mutableStateOf(Booster.canOverlay(ctx)) }
    var dndGranted by remember { mutableStateOf(Booster.hasDndAccess(ctx)) }
    var dndOn by remember { mutableStateOf(Booster.isDndOn(ctx)) }
    var monitor by remember { mutableStateOf(Prefs.get(ctx, Prefs.MONITOR, false)) }
    var autoBoost by remember { mutableStateOf(Prefs.get(ctx, Prefs.AUTO_BOOST, true)) }
    var autoDnd by remember { mutableStateOf(Prefs.get(ctx, Prefs.AUTO_DND, false)) }
    var overlayPref by remember { mutableStateOf(Prefs.get(ctx, Prefs.OVERLAY, true)) }
    var thermalWarn by remember { mutableStateOf(Prefs.get(ctx, Prefs.THERMAL, true)) }
    var boosting by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        while (true) {
            snap = SystemStats.read(ctx)
            usageOk = Booster.hasUsageAccess(ctx)
            overlayOk = Booster.canOverlay(ctx)
            dndGranted = Booster.hasDndAccess(ctx)
            dndOn = Booster.isDndOn(ctx)
            delay(1000)
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            ping = withContext(Dispatchers.IO) { Net.pingMs() }
            delay(3000)
        }
    }

    LaunchedEffect(monitor) {
        if (monitor) GameService.start(ctx) else GameService.stop(ctx)
    }

    ScreenColumn {
        Text("Game Booster", style = MaterialTheme.typography.headlineMedium)

        // ---- Manual boost ----
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Boost RAM", style = MaterialTheme.typography.titleMedium)
                Text("Closes background apps to free memory.")
                Button(
                    enabled = !boosting,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            boosting = true
                            result = null
                            val before = Booster.freeRam(ctx)
                            val n = withContext(Dispatchers.IO) { Booster.killBackground(ctx, null) }
                            delay(2000)
                            val freed = (Booster.freeRam(ctx) - before).coerceAtLeast(0)
                            result = "Asked $n apps to close. RAM freed: ${fmt(freed)}"
                            boosting = false
                        }
                    }
                ) { Text(if (boosting) "Boosting..." else "Boost now") }
                result?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            }
        }

        // ---- Game monitor ----
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Auto game mode", style = MaterialTheme.typography.titleMedium)
                ToggleRow(
                    "Game monitor",
                    "Detects when you open a game from your Games list",
                    monitor
                ) { v ->
                    monitor = v
                    Prefs.set(ctx, Prefs.MONITOR, v)
                }
                ToggleRow("Auto boost", "Close background apps when a game starts", autoBoost) { v ->
                    autoBoost = v
                    Prefs.set(ctx, Prefs.AUTO_BOOST, v)
                }
                ToggleRow("Auto Do Not Disturb", "Silence notifications while gaming", autoDnd) { v ->
                    autoDnd = v
                    Prefs.set(ctx, Prefs.AUTO_DND, v)
                }
                ToggleRow("Live overlay", "RAM, temperature, thermal and ping over the game", overlayPref) { v ->
                    overlayPref = v
                    Prefs.set(ctx, Prefs.OVERLAY, v)
                }
                ToggleRow("Overheat warning", "Notify when the phone gets too hot", thermalWarn) { v ->
                    thermalWarn = v
                    Prefs.set(ctx, Prefs.THERMAL, v)
                }
                Spacer(Modifier.height(4.dp))
                Text("Permissions needed", style = MaterialTheme.typography.titleSmall)
                PermRow("Usage access (detect games)", usageOk) { Booster.openUsageAccess(ctx) }
                PermRow("Draw over apps (overlay)", overlayOk) { Booster.openOverlay(ctx) }
                PermRow("Do Not Disturb access", dndGranted) { Booster.openDndAccess(ctx) }
            }
        }

        // ---- Manual DND ----
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                ToggleRow(
                    "Do Not Disturb now",
                    if (dndGranted) "Turn on or off right now" else "Tap the switch and allow access",
                    dndOn && dndGranted
                ) { want ->
                    if (!Booster.hasDndAccess(ctx)) {
                        Booster.openDndAccess(ctx)
                    } else {
                        Booster.setDnd(ctx, want)
                        dndOn = want
                    }
                }
            }
        }

        // ---- Live stats ----
        StatCard("RAM", "${fmt(snap.ramUsed)} / ${fmt(snap.ramTotal)}", snap.ramFraction)
        StatCard("Storage", "${fmt(snap.storageUsed)} / ${fmt(snap.storageTotal)}", snap.storageFraction)
        StatCard(
            "Battery",
            "${snap.batteryPercent}%" + if (snap.charging) " (charging)" else "",
            snap.batteryPercent / 100f
        )
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Temperature and network", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text("Battery: %.1f °C".format(snap.batteryTempC))
                Text("Thermal status: ${snap.thermal}")
                Text("Ping: " + if (ping < 0) "no internet" else "$ping ms")
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/MainActivity.kt" <<'GB_EOF'
package com.example.gamebooster

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface

class MainActivity : ComponentActivity() {

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            MaterialTheme {
                Surface { Root() }
            }
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Net.kt" <<'GB_EOF'
package com.example.gamebooster

import java.net.InetSocketAddress
import java.net.Socket

object Net {
    /** TCP connect time to Cloudflare DNS in ms, or -1 if no internet. Call off the main thread. */
    fun pingMs(): Int {
        return try {
            val s = Socket()
            val t0 = System.nanoTime()
            s.connect(InetSocketAddress("1.1.1.1", 443), 1500)
            val ms = ((System.nanoTime() - t0) / 1_000_000).toInt()
            s.close()
            ms
        } catch (e: Exception) {
            -1
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

    private fun sp(c: Context) = c.getSharedPreferences("gb_prefs", Context.MODE_PRIVATE)

    fun get(c: Context, key: String, def: Boolean): Boolean = sp(c).getBoolean(key, def)

    fun set(c: Context, key: String, value: Boolean) {
        sp(c).edit().putBoolean(key, value).apply()
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
    val tabs = listOf("Boost" to "⚡", "Games" to "🎮", "Clean" to "🧹", "Security" to "🛡", "Apps" to "📱")

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
                else -> AppsScreen()
            }
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Security.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/SecurityScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SecurityScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var report by remember { mutableStateOf<SecurityReport?>(null) }
    var scanning by remember { mutableStateOf(false) }

    ScreenColumn {
        Text("Security", style = MaterialTheme.typography.headlineMedium)
        Text("Checks app permissions, where apps came from, and key device settings. This is not a virus-signature scanner.")

        Button(
            enabled = !scanning,
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    scanning = true
                    report = withContext(Dispatchers.IO) { Security.scan(ctx) }
                    scanning = false
                }
            }
        ) { Text(if (scanning) "Scanning..." else "Run security scan") }

        report?.let { r ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Security score: ${r.score} / 100", style = MaterialTheme.typography.titleLarge)
                }
            }
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Device checks", style = MaterialTheme.typography.titleMedium)
                    r.device.forEach { d ->
                        Text((if (d.ok) "✓ " else "⚠ ") + d.title + ": " + d.detail)
                    }
                }
            }
            Text("Apps to review (${r.apps.size})", style = MaterialTheme.typography.titleLarge)
            r.apps.take(30).forEach { a ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(a.label, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                            Text(a.level)
                        }
                        Text(a.reasons.joinToString(", "), style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { Booster.openAppInfo(ctx, a.pkg) }) {
                            Text("Open app settings")
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/SystemStats.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Ui.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

fun fmt(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return when {
        gb >= 1 -> "%.1f GB".format(gb)
        bytes >= 1024L * 1024L -> "%.0f MB".format(bytes / (1024.0 * 1024.0))
        else -> "%.0f KB".format(bytes / 1024.0)
    }
}

@Composable
fun ScreenColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content
    )
}

@Composable
fun StatCard(title: String, value: String, fraction: Float) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(value)
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { fraction.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
fun ToggleRow(title: String, sub: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(sub, style = MaterialTheme.typography.bodySmall)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
fun PermRow(name: String, granted: Boolean, onGrant: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(name, Modifier.weight(1f))
        if (granted) {
            Text("✓ allowed")
        } else {
            OutlinedButton(onClick = onGrant) { Text("Allow") }
        }
    }
}
GB_EOF
echo "Step 3 files updated!"
