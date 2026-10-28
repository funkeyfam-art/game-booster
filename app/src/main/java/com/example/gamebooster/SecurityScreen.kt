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
