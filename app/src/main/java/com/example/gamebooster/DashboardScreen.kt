package com.example.gamebooster

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

private fun fmt(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1) "%.1f GB".format(gb) else "%.0f MB".format(bytes / (1024.0 * 1024.0))
}

@Composable
fun DashboardScreen() {
    val context = LocalContext.current
    var snap by remember { mutableStateOf(SystemStats.read(context)) }

    // Refresh every second
    LaunchedEffect(Unit) {
        while (true) {
            snap = SystemStats.read(context)
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

        StatCard(
            title = "RAM",
            value = "${fmt(snap.ramUsed)} / ${fmt(snap.ramTotal)}",
            fraction = snap.ramFraction
        )
        StatCard(
            title = "Storage",
            value = "${fmt(snap.storageUsed)} / ${fmt(snap.storageTotal)}",
            fraction = snap.storageFraction
        )
        StatCard(
            title = "Battery",
            value = "${snap.batteryPercent}%" + if (snap.charging) " (charging)" else "",
            fraction = snap.batteryPercent / 100f
        )

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Temperature", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text("Battery: %.1f °C".format(snap.batteryTempC))
                Text("Thermal status: ${snap.thermal}")
            }
        }
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
