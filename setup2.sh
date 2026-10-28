#!/bin/bash
# Step 2: run with  bash setup2.sh
set -e
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'GB_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.KILL_BACKGROUND_PROCESSES" />
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />

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
    </application>
</manifest>
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/Booster.kt" <<'GB_EOF'
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
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/DashboardScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private fun fmt(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1) "%.1f GB".format(gb) else "%.0f MB".format(bytes / (1024.0 * 1024.0))
}

@Composable
fun DashboardScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var snap by remember { mutableStateOf(SystemStats.read(context)) }
    var apps by remember { mutableStateOf<List<AppItem>>(emptyList()) }
    var showAll by remember { mutableStateOf(false) }
    var dndGranted by remember { mutableStateOf(Booster.hasDndAccess(context)) }
    var dndOn by remember { mutableStateOf(Booster.isDndOn(context)) }
    var boosting by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) { Apps.launchable(context) }
    }

    // Refresh live values every second
    LaunchedEffect(Unit) {
        while (true) {
            snap = SystemStats.read(context)
            dndGranted = Booster.hasDndAccess(context)
            dndOn = Booster.isDndOn(context)
            delay(1000)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Game Booster", style = MaterialTheme.typography.headlineMedium)

        // ---- BOOST ----
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
                            val before = Booster.freeRam(context)
                            val n = withContext(Dispatchers.IO) { Booster.killBackground(context, null) }
                            delay(2000)
                            val freed = (Booster.freeRam(context) - before).coerceAtLeast(0)
                            result = "Asked $n apps to close. RAM freed: ${fmt(freed)}"
                            boosting = false
                        }
                    }
                ) { Text(if (boosting) "Boosting..." else "Boost now") }
                result?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            }
        }

        // ---- DND ----
        Card(Modifier.fillMaxWidth()) {
            Row(
                Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Do Not Disturb", style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (dndGranted) "Silence notifications while gaming"
                        else "Tap the switch and allow access"
                    )
                }
                Switch(
                    checked = dndOn && dndGranted,
                    onCheckedChange = { want ->
                        if (!Booster.hasDndAccess(context)) {
                            Booster.openDndAccess(context)
                        } else {
                            Booster.setDnd(context, want)
                            dndOn = want
                        }
                    }
                )
            }
        }

        // ---- LIVE STATS ----
        StatCard("RAM", "${fmt(snap.ramUsed)} / ${fmt(snap.ramTotal)}", snap.ramFraction)
        StatCard("Storage", "${fmt(snap.storageUsed)} / ${fmt(snap.storageTotal)}", snap.storageFraction)
        StatCard(
            "Battery",
            "${snap.batteryPercent}%" + if (snap.charging) " (charging)" else "",
            snap.batteryPercent / 100f
        )
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Temperature", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text("Battery: %.1f °C".format(snap.batteryTempC))
                Text("Thermal status: ${snap.thermal}")
            }
        }

        // ---- GAMES ----
        Text("Games", style = MaterialTheme.typography.titleLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!showAll) Button(onClick = { showAll = false }) { Text("Games") }
            else OutlinedButton(onClick = { showAll = false }) { Text("Games") }
            if (showAll) Button(onClick = { showAll = true }) { Text("All apps") }
            else OutlinedButton(onClick = { showAll = true }) { Text("All apps") }
        }

        val shown = if (showAll) apps else apps.filter { it.isGame }
        if (shown.isEmpty()) {
            Text(
                if (apps.isEmpty()) "Loading apps..."
                else "No games detected. Tap \"All apps\" and pick your game."
            )
        }
        shown.forEach { app ->
            Card(Modifier.fillMaxWidth()) {
                Row(
                    Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
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
                    Button(onClick = {
                        scope.launch {
                            withContext(Dispatchers.IO) { Booster.killBackground(context, app.pkg) }
                            Booster.launch(context, app.pkg)
                        }
                    }) { Text("Boost & Play") }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun StatCard(title: String, value: String, fraction: Float) {
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
GB_EOF
echo "Step 2 files updated!"
