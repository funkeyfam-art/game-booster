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
