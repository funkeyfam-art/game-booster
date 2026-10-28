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
