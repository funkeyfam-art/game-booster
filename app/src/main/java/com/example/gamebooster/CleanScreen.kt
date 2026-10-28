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
