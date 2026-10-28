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
