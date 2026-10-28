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
